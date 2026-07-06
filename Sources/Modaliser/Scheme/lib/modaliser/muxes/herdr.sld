;; (modaliser muxes herdr) — herdr mux backend behind the (modaliser
;; terminal) façade. herdr (herdr.dev) is an "agent multiplexer that lives
;; in the terminal": a client/server TUI run *inside* a host terminal (the
;; user runs it in iTerm), controlled through a JSON socket-API CLI
;; (`herdr pane …`) rather than keystrokes/AppleScript.
;;
;; Quick start (prefix-style import — recommended to avoid collisions with
;; peer backend modules and the façade):
;;
;;   (import (prefix (modaliser muxes herdr) herdr:))
;;   (herdr:register!)
;;
;; Once iTerm's host backend is also registered, ops dispatch through
;; (modaliser terminal): when the focused iTerm pane's foreground command
;; is "herdr", `(terminal:focus-pane-left)` resolves to this backend's
;; `herdr pane focus --direction left`.
;;
;; ── Detection, validated live against a herdr-in-iTerm client (leaf 2) ──
;;   #1 An iTerm pane running the herdr *client* reports tty foreground
;;      command "herdr" (verified: the client is the `herdr` binary running
;;      as a foreground TUI). So the façade's mux match-key "herdr"
;;      resolves it — no special detection path needed.
;;   #2/#3 The socket API scopes per *session* (one default session = one
;;      socket) with GLOBAL focus, NOT per client / tty. `herdr pane
;;      current` answers from server state and reflects the sole client's
;;      focused pane (verified: it answers even with no client attached).
;;      Two herdr clients attached to one session therefore share one
;;      global focus and cannot be disambiguated — a documented v1
;;      non-goal; the common single-client case is unambiguous. No tty
;;      correlation (cf. tmux/zellij ADR-0006) is required.
;;
;; ── JSON ──
;; herdr emits compact single-line nested JSON
;; ({"id":…,"result":{…},"type":…}). The multiline awk parsers used by
;; tmux/zellij do not transfer, so we parse with (modaliser json) — a
;; small portable reader (no host JSON primitive, stays in the portable
;; tree). `herdr-json` shells out, parses, and returns the alist/vector
;; tree; a `guard` degrades any non-JSON line to #f rather than breaking a
;; leader press.
;;
;; ── Op recipes (from `herdr pane --help`) ──
;;   focus  → `pane focus  --direction <dir> --current`
;;   move   → `pane swap   --direction <dir> --current`   (swap w/ neighbour)
;;   split  → `pane split  --current --direction right|down --focus` native;
;;            LEFT/UP have no native direction, so split the opposite
;;            native way with --focus (the new pane becomes --current
;;            atomically, server-side) then `pane swap` it back toward the
;;            requested side — no split/swap focus race (R7).
;;   zoom   → `pane zoom   --current --toggle`
;;
;; ── Digit-jump focus ──
;; herdr has no dedicated "focus pane <id>" verb, but `herdr agent focus
;; <pane_id>` is a UNIVERSAL pane focus: it focuses ANY pane by id (verified
;; live cross-tab). On a bare shell pane it also emits a cosmetic
;; agent_not_found, but the focus side-effect fires first so the pane still
;; lands focused (2>/dev/null swallows the error). Digit-jump therefore
;; focuses via `agent focus <pane_id>` for every pane. The panes list block
;; (build-herdr-tree's Panes panel) paints digit CHIPS over the on-screen
;; herdr panes in replace mode — see (modaliser blocks herdr-list). The
;; backend's own focus-pane-by-digit slot below (the generic-capability-tree
;; entry point, not on the shipping herdr variant path) stays chip-less.

(define-library (modaliser muxes herdr)
  (export register!
          backend
          ;; herdr-in-iTerm variant wiring (ADR-0013). The replace/augment
          ;; classifier + the herdr variant tree-builder. The context-suffix
          ;; COMPOSITION lives in the user config (a single global suffix slot
          ;; is last-write-wins, so herdr composes rather than installs): the
          ;; config gates on (terminal:in-chain? 'herdr) + the tab-scoped iTerm
          ;; split count, then calls classify-herdr-variant.
          classify-herdr-variant
          build-herdr-tree)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser util)
          (modaliser shell)
          (modaliser json)
          ;; The three herdr live-list blocks (panes / tabs / workspaces)
          ;; share one kind-parameterised constructor; build-herdr-tree wraps
          ;; each with a hidden digit key-range whose focus action lives here
          ;; (agent focus / tab focus / workspace focus). Mirrors apps/iterm
          ;; importing (modaliser blocks iterm-panes) / iterm-tabs.
          (modaliser blocks herdr-list)
          ;; The façade exports the 14 op names plus the predicates; this
          ;; module defines its own focus-pane-left etc. as record fields,
          ;; so import only the machinery we need. herdr's global-focus
          ;; socket API needs no tty correlation, so unlike zellij we do
          ;; not import correlate-mux-client-to-host-tty.
          (only (modaliser terminal)
                make-terminal-backend
                register-backend!
                modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that
    ;; doesn't include /opt/homebrew/bin (where herdr lives), so every
    ;; shell-out is prefixed with the tool path — same pattern as tmux,
    ;; zellij, and the nvim helpers in (modaliser terminal).
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; ─── Socket-API query ───────────────────────────────────────────
    ;;
    ;; Run `herdr <args>`, parse stdout as JSON, return the alist/vector
    ;; tree — or #f when the command produced nothing or non-JSON. The
    ;; `guard` is the safety net: herdr's output is reliably JSON (even
    ;; errors are `{"error":{…}}`, which parse fine and simply lack a
    ;; "result" key), but a truncated/garbage line must not raise through
    ;; a leader press.
    (define (herdr-json args)
      (let ((out (string-trim
                   (run-shell
                     (string-append path-prefix "herdr " args " 2>/dev/null")))))
        (if (string=? out "")
            #f
            (guard (e (#t #f))
              (json-parse out)))))

    ;; Fire a mutating pane op; output is ignored (2>/dev/null keeps
    ;; innocuous edge-of-layout errors out of the GUI app log).
    (define (herdr-cmd args)
      (run-shell (string-append path-prefix "herdr " args " 2>/dev/null")))

    ;; ─── Detection ──────────────────────────────────────────────────
    ;;
    ;; `focused-pane-id` → the server's globally-focused pane id
    ;; ("w9:p1"). `detect-fg-command` → the innermost foreground process
    ;; name of that pane, so the façade can descend one level further
    ;; (e.g. herdr → nvim) exactly as it does through tmux/zellij; a plain
    ;; shell pane reports "zsh", which matches no mux and leaves herdr the
    ;; leaf backend.

    ;; One `pane current` read, one field out of the focused pane record.
    ;; `pane current` carries the pane's own id plus its enclosing tab_id /
    ;; workspace_id, so the close/rename ops below get their target ids from
    ;; the same query without a second shell-out.
    (define (focused-pane-field field)
      (let ((j (herdr-json "pane current")))
        (and j
             (let ((v (json-ref (json-ref (json-ref j "result") "pane") field)))
               (and (string? v) v)))))

    (define (focused-pane-id)      (focused-pane-field "pane_id"))
    (define (focused-tab-id)       (focused-pane-field "tab_id"))
    (define (focused-workspace-id) (focused-pane-field "workspace_id"))

    (define (detect-fg-command)
      (let ((j (herdr-json "pane process-info --current")))
        (and j
             (let* ((pi  (json-ref (json-ref j "result") "process_info"))
                    (fps (and pi (json-ref pi "foreground_processes"))))
               (and (vector? fps)
                    (> (vector-length fps) 0)
                    (let ((name (json-ref
                                  (vector-ref fps (- (vector-length fps) 1))
                                  "name")))
                      (and (string? name) name)))))))

    ;; ─── Op primitives ──────────────────────────────────────────────

    (define (focus-pane-left)  (herdr-cmd "pane focus --direction left --current"))
    (define (focus-pane-right) (herdr-cmd "pane focus --direction right --current"))
    (define (focus-pane-up)    (herdr-cmd "pane focus --direction up --current"))
    (define (focus-pane-down)  (herdr-cmd "pane focus --direction down --current"))

    ;; Native splits (right/down): new pane on that side, focus follows it.
    (define (split-pane-right) (herdr-cmd "pane split --current --direction right --focus"))
    (define (split-pane-down)  (herdr-cmd "pane split --current --direction down --focus"))

    ;; Left/up: no native direction. Split the opposite native way with
    ;; --focus so the new pane is the server's current pane, then swap it
    ;; toward the requested side. `--focus` makes the swap target
    ;; unambiguous (it is --current), avoiding the split/swap race R7
    ;; describes; focus rides with the pane through the swap.
    (define (split-pane-left)
      (herdr-cmd "pane split --current --direction right --focus")
      (herdr-cmd "pane swap --direction left --current"))
    (define (split-pane-up)
      (herdr-cmd "pane split --current --direction down --focus")
      (herdr-cmd "pane swap --direction up --current"))

    ;; Move = swap the focused pane with its directional neighbour.
    (define (move-pane-left)   (herdr-cmd "pane swap --direction left --current"))
    (define (move-pane-right)  (herdr-cmd "pane swap --direction right --current"))
    (define (move-pane-up)     (herdr-cmd "pane swap --direction up --current"))
    (define (move-pane-down)   (herdr-cmd "pane swap --direction down --current"))

    ;; Zoom: herdr's `--toggle` is a stateless flip (ADR-0007 semantics).
    (define (toggle-pane-zoom) (herdr-cmd "pane zoom --current --toggle"))

    ;; Close the focused pane. `pane close` needs an explicit id (no
    ;; --current form), so resolve the focused pane first. Bound to `d` at
    ;; the herdr tree top level.
    (define (close-pane)
      (let ((pid (focused-pane-id)))
        (when pid (herdr-cmd (string-append "pane close " pid)))))

    ;; ─── Digit-jump (façade slot; chip-less) ───────────────────────
    ;;
    ;; Snapshot the pane ids at mode-enter (labels 1..0 in list order),
    ;; then focus pane N via `herdr agent focus <pane_id>`.
    ;;
    ;; `agent focus <pane_id>` is a UNIVERSAL pane focus: it focuses ANY
    ;; pane by id — verified live cross-tab against p1/p2/p3. On a
    ;; non-agent (bare shell) pane it *also* emits an `agent_not_found`
    ;; error, but the focus side-effect fires first, so the pane still
    ;; lands focused (2>/dev/null in herdr-cmd swallows the cosmetic
    ;; error). This corrects the leaf-2 assumption that it no-ops on
    ;; shell panes — it does not. No `pane neighbor` geometric walk is
    ;; needed. This façade slot (the generic-capability-tree entry point)
    ;; is chip-less; the shipping herdr variant tree instead uses the
    ;; panes list block, whose Panes panel paints digit chips over the
    ;; on-screen herdr panes (see (modaliser blocks herdr-list)).

    (define (list-pane-ids)
      (let ((j (herdr-json "pane list")))
        (if (not j)
            '()
            (let ((panes (json-ref (json-ref j "result") "panes")))
              (if (vector? panes)
                  (let loop ((k 0) (acc '()))
                    (if (>= k (vector-length panes))
                        (reverse acc)
                        (let ((pid (json-ref (vector-ref panes k) "pane_id")))
                          (loop (+ k 1)
                                (if (string? pid) (cons pid acc) acc)))))
                  '())))))

    (define digit-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Snapshot taken at mode-enter so the digit-action closures don't
    ;; reissue the JSON query at keystroke time (same pattern as tmux /
    ;; zellij *current-panes*).
    (define *current-pane-ids* '())
    (define (set-current-pane-ids! ids) (set! *current-pane-ids* ids))

    (define (focus-by-digit d)
      (let ((idx (string->number d))
            (ids *current-pane-ids*))
        (when idx
          ;; Digit "0" labels the 10th pane in the 1..0 sequence.
          (let* ((zero-based (if (= idx 0) 9 (- idx 1)))
                 (id (and (< zero-based (length ids))
                          (list-ref ids zero-based))))
            (when id
              (herdr-cmd (string-append "agent focus " id)))))))

    (define (digit-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              digit-labels
              (lambda (k) (focus-by-digit k)))))

    (define (pane-digit-register!)
      (register-tree! 'herdr-pane-digit
        'on-enter
        (lambda () (set-current-pane-ids! (list-pane-ids)))
        'on-leave (lambda () #f)
        (digit-range)))

    (define (focus-pane-by-digit)
      (enter-mode! 'herdr-pane-digit))

    ;; ─── herdr-in-iTerm variant wiring (ADR-0013) ───────────────────
    ;;
    ;; On each local-leader press the iTerm context-suffix hook picks a
    ;; variant tree by the herdr situation in the frontmost iTerm window.
    ;; herdr owns the top-level hjkl pane focus in BOTH variant trees
    ;; (identical muscle memory); the augment tree = this tree + the iTerm
    ;; `i`-splits drill (spliced in by the config from
    ;; (modaliser apps iterm) build-iterm-splits-drill).

    ;; The replace/augment classifier (R1). Keyed on the CURRENT-TAB iTerm
    ;; split count — the config sources it from the tab-scoped
    ;; (iterm:iterm-list-session-ids), NOT an all-tabs AX scroll-area count
    ;; that would misfire on a herdr window carrying a second tab. herdr the
    ;; sole current-tab split → "/herdr" (replace: herdr owns the whole
    ;; window, zero iTerm controls); herdr plus other current-tab splits →
    ;; "/herdr+split" (augment). A 0 count (AppleScript hiccup while herdr is
    ;; confirmed focused) degrades to replace — the safe default, since the
    ;; augment tree binds iTerm ops that would be wrong with no iTerm splits.
    (define (classify-herdr-variant current-tab-split-count)
      (if (> current-tab-split-count 1) "/herdr+split" "/herdr"))

    ;; ─── Tab & workspace ops ────────────────────────────────────────
    ;;
    ;; `create --focus` makes and switches to the new tab/workspace;
    ;; close/rename need the focused id, read from `pane current` (one
    ;; query yields pane_id + tab_id + workspace_id).

    (define (new-tab)       (herdr-cmd "tab create --focus"))
    (define (new-workspace) (herdr-cmd "workspace create --focus"))

    (define (close-focused-tab)
      (let ((id (focused-tab-id)))
        (when id (herdr-cmd (string-append "tab close " id)))))
    (define (close-focused-workspace)
      (let ((id (focused-workspace-id)))
        (when id (herdr-cmd (string-append "workspace close " id)))))

    ;; Rewrite each ' to the POSIX '\'' idiom so a user-typed label is safe
    ;; to interpolate inside a single-quoted zsh word (same idiom as
    ;; apps/iterm.sld's shell-sq-escape).
    (define (sq-escape s)
      (let loop ((cs (string->list s)) (acc '()))
        (if (null? cs)
            (list->string (reverse acc))
            (loop (cdr cs)
                  (if (char=? (car cs) #\')
                      (cons #\' (cons #\' (cons #\\ (cons #\' acc))))
                      (cons (car cs) acc))))))

    ;; Native text prompt via AppleScript `display dialog … default answer`
    ;; — herdr's rename takes the new label as a CLI arg (unlike iTerm's
    ;; menu-driven inline editor), and Modaliser has no in-overlay free-text
    ;; input, so a one-shot dialog is the cheapest complete path. Returns the
    ;; typed text, or #f when cancelled (osascript errors → empty stdout).
    ;; TITLE is a constant with no quotes, so it inlines safely.
    (define (prompt-text title)
      (let ((out (string-trim
                   (run-shell
                     (string-append
                       "osascript -e 'text returned of "
                       "(display dialog \"" title "\" default answer \"\" "
                       "buttons {\"Cancel\", \"OK\"} default button \"OK\")' "
                       "2>/dev/null")))))
        (if (string=? out "") #f out)))

    (define (rename-focused-tab!)
      (let ((id (focused-tab-id)))
        (when id
          (let ((name (prompt-text "Rename herdr tab:")))
            (when (and name (not (string=? name "")))
              (herdr-cmd (string-append "tab rename " id " '" (sq-escape name) "'")))))))
    (define (rename-focused-workspace!)
      (let ((id (focused-workspace-id)))
        (when id
          (let ((name (prompt-text "Rename herdr workspace:")))
            (when (and name (not (string=? name "")))
              (herdr-cmd
                (string-append "workspace rename " id " '" (sq-escape name) "'")))))))

    ;; ─── Live-list blocks (panes / tabs / workspaces) ───────────────
    ;;
    ;; Each wraps the shared (modaliser blocks herdr-list) constructor and
    ;; bundles a hidden 1.. digit key-range whose action focuses the matching
    ;; id — panes via the universal `agent focus`, tabs/workspaces via their
    ;; clean `focus` verbs. cursor-*-fn wire the selection cursor to the
    ;; block's live targets / focused row (mirrors iterm:pane-list-block). A
    ;; digit pressed before the on-render snapshot ran re-snapshots on demand.
    (define (list-digit-range kind focus-fn)
      (cons (cons 'hidden #t)
            (key-range "1.." "Item <n>"
              digit-labels
              (lambda (k)
                (let ((entry (or (assoc k (herdr-list-current-targets))
                                 (begin
                                   (herdr-list-refresh! kind)
                                   (assoc k (herdr-list-current-targets))))))
                  (when entry (focus-fn (cdr entry))))))))

    (define (herdr-list-block kind focus-fn chips?)
      (append (make-herdr-list-block 'kind kind 'chips? chips?)
              (list (cons 'cursor-targets-fn herdr-list-current-targets)
                    (cons 'cursor-initial-index-fn herdr-list-focused-index)
                    (cons 'block-children
                          (list (list-digit-range kind focus-fn))))))

    ;; The panes block takes an optional 'chips? — when #t it paints digit
    ;; chips over the on-screen herdr panes (rects from `herdr pane layout`;
    ;; correct in replace mode, best-effort in augment — see the block header).
    ;; tabs/workspaces have no on-screen rects, so they never chip.
    (define (pane-list-block . opts)
      (let ((chips? (alist-ref (apply props->alist opts) 'chips? #f)))
        (herdr-list-block 'panes
          (lambda (id) (herdr-cmd (string-append "agent focus " id)))
          chips?)))
    (define (tab-list-block)
      (herdr-list-block 'tabs
        (lambda (id) (herdr-cmd (string-append "tab focus " id))) #f))
    (define (workspace-list-block)
      (herdr-list-block 'workspaces
        (lambda (id) (herdr-cmd (string-append "workspace focus " id))) #f))

    ;; Sticky top-level focus mode. The Focus panel's hjkl each carry a
    ;; 'sticky-target here (build-herdr-tree), so the first hjkl focuses AND
    ;; latches into this mode — subsequent hjkl keep moving focus without
    ;; another leader press (herdr owns the top-level hjkl, root BRIEF).
    (define (focus-mode-register!)
      (register-tree! 'herdr-panes-focus
        'sticky #t
        'exit-on-unknown #t
        'display-name "Focus"
        (key "h" "Left"  focus-pane-left)
        (key "j" "Down"  focus-pane-down)
        (key "k" "Up"    focus-pane-up)
        (key "l" "Right" focus-pane-right)))

    ;; The herdr variant tree. herdr owns the top-level hjkl pane focus —
    ;; bound to the herdr-DIRECT ops above, never the façade, so it drives
    ;; herdr regardless of what active-backend resolves to. Returns a list of
    ;; nodes the config splices into (screen 'com.googlecode.iterm2/herdr …)
    ;; and, with the iTerm `i`-drill appended, (screen …/herdr+split …).
    ;;
    ;;   Focus panel  hjkl → focus (sticky-latch into 'herdr-panes-focus)
    ;;   x Split      hjkl → new split that direction (left/up = split+swap)
    ;;   m Move Pane  sticky hjkl → swap focused pane with its neighbour
    ;;   z / d        toggle zoom / close pane
    ;;   t Tabs       n/r/d + the tabs list (digit → switch)
    ;;   w Workspaces n/r/d + the workspaces list (digit → switch)
    ;;   Panes panel  the panes list + chips (digit → focus by id)
    (define (build-herdr-tree)
      (list
        (panel "Focus"
          (key "h" "Left"  focus-pane-left  'sticky-target 'herdr-panes-focus)
          (key "j" "Down"  focus-pane-down  'sticky-target 'herdr-panes-focus)
          (key "k" "Up"    focus-pane-up    'sticky-target 'herdr-panes-focus)
          (key "l" "Right" focus-pane-right 'sticky-target 'herdr-panes-focus))
        (group "x" "Split"
          (key "h" "Left"  split-pane-left)
          (key "j" "Down"  split-pane-down)
          (key "k" "Up"    split-pane-up)
          (key "l" "Right" split-pane-right))
        (group "m" "Move Pane"
          'sticky #t
          'exit-on-unknown #t
          (key "h" "Left"  move-pane-left)
          (key "j" "Down"  move-pane-down)
          (key "k" "Up"    move-pane-up)
          (key "l" "Right" move-pane-right))
        (key "z" "Toggle Zoom" toggle-pane-zoom)
        (key "d" "Close Pane"  close-pane)
        (open "t" "Tabs"
          (key "n" "New"    new-tab)
          (key "r" "Rename" rename-focused-tab!)
          (key "d" "Close"  close-focused-tab)
          (panel "Tabs" (tab-list-block)))
        (open "w" "Workspaces"
          (key "n" "New"    new-workspace)
          (key "r" "Rename" rename-focused-workspace!)
          (key "d" "Close"  close-focused-workspace)
          (panel "Workspaces" (workspace-list-block)))
        (panel "Panes" (pane-list-block 'chips? #t))))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; configured? is constant #t — herdr has no provisioning step (no
    ;; config-file edits, no keybinding install); its socket-API CLI works
    ;; out of the box, earning herdr the full 14/14 surface like tmux and
    ;; zellij.
    (define (configured?) #t)

    (define backend
      (make-terminal-backend
        'herdr "herdr" 'mux "herdr"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        focus-pane-by-digit
        toggle-pane-zoom
        configured?))

    ;; Register the backend + the digit-jump mode + the sticky top-level
    ;; focus mode the herdr tree latches into. Safe to call more than once:
    ;; register-backend! is last-write-wins on backend symbol; register-tree!
    ;; replaces any prior tree of the same id.
    (define (register!)
      (register-backend! backend)
      (pane-digit-register!)
      (focus-mode-register!))))
