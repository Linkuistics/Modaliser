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
;;      correlation (cf. tmux/zellij) is required.
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
          build-herdr-tree
          ;; Pure round-robin ring helper (parsed `agent list` + focused
          ;; pane_id → next blocked pane_id | #f), exported for unit tests —
          ;; the jump-to-blocked op (`b`) is a thin shell around it.
          next-blocked-pane-id
          ;; Pure worktree switch-target parser (k14's tagged "ws:<id>" /
          ;; "br:<branch>" target + focused source workspace id → herdr command
          ;; args | #f), exported for unit tests — the smart-switch focus-fn
          ;; behind the `g` Worktrees digit range is a thin shell around it.
          worktree-switch-command
          ;; The four async fire-and-forget herdr ops (ADR-0014), exported for
          ;; unit tests — each is also bound into build-herdr-tree's Tabs /
          ;; Workspaces / Worktrees groups.
          rename-focused-tab!
          rename-focused-workspace!
          new-worktree!
          remove-focused-worktree!
          ;; Test seams (ADR-0014): parameterized indirection points a test
          ;; can override so no test spawns herdr
          ;; (feedback_no_live_env_mutation_in_tests) — current-herdr-query-runner
          ;; stubs canned JSON in place of a live `herdr <query>`, mirroring
          ;; `current-frontmost-bundle-id` in (modaliser terminal);
          ;; current-herdr-async-runner captures the exact verb string in
          ;; place of firing run-shell-async.
          current-herdr-query-runner
          current-herdr-async-runner)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser util)
          (modaliser shell)
          (modaliser json)
          ;; sq-escape: the one canonical POSIX single-quote escaper (ADR-0014's
          ;; (modaliser dialogs) is its home); used here for shell-safe branch-
          ;; name interpolation, unrelated to that library's dialog concern.
          (only (modaliser dialogs) sq-escape)
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
    ;; tree — or #f when the command produced nothing or non-JSON. Routed
    ;; through `current-herdr-query-runner` (mirrors `current-frontmost-
    ;; bundle-id` in (modaliser terminal)) so a test can hand back canned
    ;; JSON without a live herdr session (feedback_no_live_env_mutation_in_tests).
    ;; The `guard` in the real runner is the safety net: herdr's output is
    ;; reliably JSON (even errors are `{"error":{…}}`, which parse fine and
    ;; simply lack a "result" key), but a truncated/garbage line must not
    ;; raise through a leader press.
    (define current-herdr-query-runner
      (make-parameter
        (lambda (args)
          (let ((out (string-trim
                       (run-shell
                         (string-append path-prefix "herdr " args " 2>/dev/null")))))
            (if (string=? out "")
                #f
                (guard (e (#t #f))
                  (json-parse out)))))))

    (define (herdr-json args) ((current-herdr-query-runner) args))

    ;; Fire a mutating pane op; output is ignored (2>/dev/null keeps
    ;; innocuous edge-of-layout errors out of the GUI app log).
    (define (herdr-cmd args)
      (run-shell (string-append path-prefix "herdr " args " 2>/dev/null")))

    ;; ─── Async command dispatch (ADR-0014) ───────────────────────────
    ;;
    ;; Ops whose external UI needs the user's keyboard — herdr's own rename
    ;; / worktree-create / worktree-remove prompts — must not fire through
    ;; the synchronous herdr-cmd above. Dispatch has already released modal
    ;; capture for these terminal leaves (ADR-0015), but release alone is
    ;; not enough: a synchronous run-shell blocks the Scheme thread, and a
    ;; leader press while herdr's prompt is up would then stall the
    ;; keyboard tap (ADR-0014's stalled-tap failure mode). herdr-cmd-async
    ;; fires through run-shell-async and returns immediately; the callback
    ;; only logs a non-zero exit — no continuation payload, since the
    ;; argument-gathering is herdr's UI, not Modaliser's. Routed through
    ;; `current-herdr-async-runner` so a test can capture the exact verb
    ;; string instead of shelling out (feedback_no_live_env_mutation_in_tests).
    (define current-herdr-async-runner
      (make-parameter
        (lambda (args callback)
          (run-shell-async (string-append path-prefix "herdr " args) callback))))

    (define (herdr-cmd-async args)
      ((current-herdr-async-runner) args
        (lambda (code out err)
          (when (not (eqv? code 0))
            (log "herdr: '" args "' failed (exit " code "): " err)))))

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

    ;; Zoom: herdr's `--toggle` is a stateless flip.
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
    ;;
    ;; NO tab-reorder op (k17, reconfirmed against herdr 0.7.1). The `tab`
    ;; CLI exposes only list · create · get · focus · rename · close, and
    ;; `tab list`/`tab get` carry a read-only `number` (display order) with
    ;; no verb to set it — `tab rename` mutates the label only. herdr *can*
    ;; reorder tabs, but only by MOUSE-DRAG in the TUI (persisted to
    ;; session.json); that primitive is deliberately NOT exposed on the
    ;; socket API / CLI (upstream ogulcancelik/herdr#770 "Add tab.reorder to
    ;; socket API + CLI", CLOSED not-planned). Driving reorder would mean
    ;; injecting mouse/keystrokes — barred by the socket-API-only charter —
    ;; so tab reorder is a v1 exclusion blocked on upstream herdr, NOT a
    ;; Move-Tab affordance in the `t` drill below (contrast `m` Move Pane,
    ;; which `pane swap` backs). Revisit if herdr exposes a tab-order verb.

    (define (new-tab)       (herdr-cmd "tab create --focus"))
    (define (new-workspace) (herdr-cmd "workspace create --focus"))

    (define (close-focused-tab)
      (let ((id (focused-tab-id)))
        (when id (herdr-cmd (string-append "tab close " id)))))
    (define (close-focused-workspace)
      (let ((id (focused-workspace-id)))
        (when id (herdr-cmd (string-append "workspace close " id)))))

    ;; Rename ops fire the verb WITHOUT the new label: herdr requires the
    ;; label positionally (`tab rename <id> <label>`), and prompt-on-
    ;; missing-arg is unshipped herdr-repo work with no ETA, so today the
    ;; verb just errors harmlessly (stderr swallowed by the log-only
    ;; callback) — the guard + async-fire shape is still fully verifiable.
    ;; Per ADR-0014 (reworked at herdr-rename-prompt-ownership-k9) these two
    ;; ops are moving to a Modaliser-owned `chooser-prompt` instead of
    ;; waiting on herdr — see that leaf/node for the wiring
    ;; (chooser-prompt-herdr-rename-k10).
    (define (rename-focused-tab!)
      (let ((id (focused-tab-id)))
        (when id (herdr-cmd-async (string-append "tab rename " id)))))
    (define (rename-focused-workspace!)
      (let ((id (focused-workspace-id)))
        (when id (herdr-cmd-async (string-append "workspace rename " id)))))

    ;; ─── Worktree ops (the `g` Worktrees drill, W1–W4) ──────────────
    ;;
    ;; All three verbs are source-repo pinned via `--workspace
    ;; <focused-workspace-id>` (read from `pane current`) rather than herdr's
    ;; implicit focused-workspace resolution — deterministic, and matches the
    ;; sibling tab/workspace ops. herdr's `worktree` CLI (0.7.1):
    ;;   worktree list   [--workspace ID] [--json]
    ;;   worktree create [--workspace ID] [--branch NAME] [--base REF] [--focus]
    ;;   worktree open   [--workspace ID] (--path P | --branch NAME) [--focus]
    ;;   worktree remove  --workspace ID [--force]

    ;; Smart-switch target parser (W4). k14 encodes each worktree row's switch
    ;; target as a tagged string it computes purely over the `worktree list`
    ;; payload (git refs cannot contain ':', so the tag split is unambiguous):
    ;;   "ws:<id>"     open worktree     → `workspace focus <id>` (clean verb)
    ;;   "br:<branch>" dormant worktree  → `worktree open --branch <branch>
    ;;                                      --focus` (opens a fresh workspace)
    ;; Returns the herdr command-args string, or #f for a malformed / empty
    ;; target (a detached-dormant worktree carries no target → never dispatched).
    ;; Pure (target + source ws-id → string | #f) so it is fixture-testable with
    ;; no live herdr; the `--workspace` pin is folded in only when SOURCE-WS-ID
    ;; is a real string (degrades to herdr's implicit resolution otherwise).
    (define (worktree-switch-command target source-ws-id)
      (and (string? target)
           (>= (string-length target) 3)
           (let ((tag  (substring target 0 3))
                 (rest (substring target 3 (string-length target))))
             (and (not (string=? rest ""))
                  (cond
                    ((string=? tag "ws:")
                     (string-append "workspace focus " rest))
                    ((string=? tag "br:")
                     (string-append
                       "worktree open"
                       (if (and (string? source-ws-id)
                                (not (string=? source-ws-id "")))
                           (string-append " --workspace " source-ws-id)
                           "")
                       " --branch '" (sq-escape rest) "' --focus"))
                    (else #f))))))

    ;; The digit focus-fn behind the worktrees list: parse k14's tagged target
    ;; against the live focused workspace, then fire — a thin shell over the
    ;; pure parser (mirrors `agent focus` / `tab focus` for the other kinds).
    (define (switch-worktree target)
      (let ((cmd (worktree-switch-command target (focused-workspace-id))))
        (when cmd (herdr-cmd cmd))))

    ;; New (`n`, W1). Guard on the focused workspace id — a #f means herdr is
    ;; unreachable, so no-op — then fire `worktree create` async with no
    ;; `--branch` (ADR-0014): herdr's own UI prompts for the branch name, not
    ;; a Modaliser dialog. `--focus` still switches to the new workspace once
    ;; herdr finishes creating it.
    (define (new-worktree!)
      (let ((wsid (focused-workspace-id)))
        (when wsid
          (herdr-cmd-async (string-append "worktree create --workspace " wsid " --focus")))))

    ;; Remove (`d`, W2). Acts on the FOCUSED worktree — always a valid,
    ;; unambiguous target (the focused workspace's worktree), mirroring
    ;; close-pane/tab/workspace. NO `--force`: a dirty worktree or the main
    ;; checkout makes herdr/git refuse, no data loss. No Modaliser confirm
    ;; dialog (ADR-0014) — the remove-confirm UX is herdr-side; the safety
    ;; that survives here is the missing --force. #f ws-id → no-op.
    (define (remove-focused-worktree!)
      (let ((wsid (focused-workspace-id)))
        (when wsid
          (herdr-cmd-async (string-append "worktree remove --workspace " wsid)))))

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
    ;; Agents list (D1/D7): the 'agents kind reorders status-priority
    ;; (blocked-first) and paints a status badge; digit → focus the agent's
    ;; pane by id via the universal `agent focus`. No chips (D6) — the list is
    ;; the visualization, and agents can live cross-workspace (off-screen).
    (define (agent-list-block)
      (herdr-list-block 'agents
        (lambda (id) (herdr-cmd (string-append "agent focus " id))) #f))
    ;; Worktrees list (W3/W4): the 'worktrees kind whose digit target is a
    ;; COMPUTED tagged string (open → "ws:<id>", dormant → "br:<branch>"), so the
    ;; focus-fn is the smart-switch parser, not a bare `<x> focus`. Branch title +
    ;; ●/○ path detail; no chips (worktrees have no on-screen rect — the list is
    ;; the visualization, like agents).
    (define (worktree-list-block)
      (herdr-list-block 'worktrees switch-worktree #f))

    ;; ─── Jump to next blocked agent (top-level `b`, D4/D5) ──────────
    ;;
    ;; Round-robin over blocked agents, keyed on CURRENT FOCUS with no stored
    ;; cursor (stateless, not a Walk — D4). `next-blocked-pane-id` is pure
    ;; (parsed `agent list` + focused pane_id → next blocked pane_id | #f) and
    ;; exported for fixture tests; the op below is a thin shell that reads the
    ;; live list + focus, then focuses the target or — zero blocked — pops a
    ;; herdr toast with no focus change (D5).

    ;; Smallest string in STRS by string<?, or #f when empty. Picks the ring's
    ;; next element without a full sort — LispKit ships no stable list-sort
    ;; (see (modaliser blocks herdr-list)).
    (define (min-string strs)
      (if (null? strs)
          #f
          (let loop ((rest (cdr strs)) (m (car strs)))
            (if (null? rest)
                m
                (loop (cdr rest)
                      (if (string<? (car rest) m) (car rest) m))))))

    ;; Blocked pane_ids from a parsed `agent list` (agent_status == "blocked"),
    ;; in JSON order. #f / malformed parse → '() (the notification path).
    (define (blocked-pane-ids parsed)
      (let ((arr (and parsed
                      (json-ref (json-ref parsed "result") "agents"))))
        (if (not (vector? arr))
            '()
            (let loop ((k 0) (acc '()))
              (if (>= k (vector-length arr))
                  (reverse acc)
                  (let* ((item (vector-ref arr k))
                         (st   (json-ref item "agent_status"))
                         (pid  (json-ref item "pane_id")))
                    (loop (+ k 1)
                          (if (and (equal? st "blocked") (string? pid))
                              (cons pid acc)
                              acc))))))))

    ;; The ring: the smallest blocked pane_id sorting strictly AFTER
    ;; FOCUSED-PANE-ID (round-robin's next), wrapping to the smallest overall
    ;; when focus is at/after the last blocked pane (or unknown / #f). #f when
    ;; nothing is blocked. pane_id compare is lexical ("p10" < "p2") —
    ;; acceptable for v1 while ids share a width; numeric-aware ordering
    ;; deferred (noted so a later id widening doesn't surprise).
    (define (next-blocked-pane-id parsed focused-pane-id)
      (let ((blocked (blocked-pane-ids parsed)))
        (if (null? blocked)
            #f
            (let ((after (if (string? focused-pane-id)
                             (filter (lambda (p) (string<? focused-pane-id p))
                                     blocked)
                             '())))
              (if (pair? after)
                  (min-string after)
                  (min-string blocked))))))

    ;; The op bound to `b`: focus the next blocked agent (server-wide, D2), or
    ;; toast when none. A plain key (Terminal, not a Walk) so the overlay
    ;; dismisses and the user interacts with the agent immediately (D4).
    (define (jump-to-next-blocked)
      (let ((target (next-blocked-pane-id (herdr-json "agent list")
                                          (focused-pane-id))))
        (if target
            (herdr-cmd (string-append "agent focus " target))
            (herdr-cmd "notification show 'No blocked agents'"))))

    ;; The Walk top-level focus mode. The Focus panel's hjkl each carry
    ;; 'next 'herdr-panes-focus (build-herdr-tree, a cross edge), so the
    ;; first hjkl focuses AND crosses into this mode; each member here
    ;; carries 'next 'self (a cyclic edge back to itself), so subsequent
    ;; hjkl keep moving focus without another leader press (herdr owns the
    ;; top-level hjkl, root BRIEF).
    (define (focus-mode-register!)
      (register-tree! 'herdr-panes-focus
        'exit-on-unknown #t
        'display-name "Focus"
        (key "h" "Left"  focus-pane-left  'next 'self)
        (key "j" "Down"  focus-pane-down  'next 'self)
        (key "k" "Up"    focus-pane-up    'next 'self)
        (key "l" "Right" focus-pane-right 'next 'self)))

    ;; The herdr variant tree. herdr owns the top-level hjkl pane focus —
    ;; bound to the herdr-DIRECT ops above, never the façade, so it drives
    ;; herdr regardless of what active-backend resolves to. Returns a list of
    ;; nodes the config splices into (screen 'com.googlecode.iterm2/herdr …)
    ;; and, with the iTerm `i`-drill appended, (screen …/herdr+split …).
    ;;
    ;;   Focus panel  hjkl → focus (crosses into the 'herdr-panes-focus Walk)
    ;;   x Split      hjkl → new split that direction (left/up = split+swap)
    ;;   m Move Pane  Walk hjkl → swap focused pane with its neighbour
    ;;   z / d        toggle zoom / close pane
    ;;   t Tabs       n/r/d + the tabs list (digit → switch); no Move Tab —
    ;;                 herdr exposes no socket/CLI tab-reorder verb (see
    ;;                 Tab ops above)
    ;;   w Workspaces n/r/d + the workspaces list (digit → switch)
    ;;   g Worktrees  n/d + the worktrees list (digit → smart-switch)
    ;;   b Jump       focus the next blocked agent (round-robin; toast if none)
    ;;   a Agents     the agents list (status-badged, blocked-first; digit → focus)
    ;;   Panes panel  the panes list + chips (digit → focus by id)
    (define (build-herdr-tree)
      (list
        (panel "Focus"
          (key "h" "Left"  focus-pane-left  'next 'herdr-panes-focus)
          (key "j" "Down"  focus-pane-down  'next 'herdr-panes-focus)
          (key "k" "Up"    focus-pane-up    'next 'herdr-panes-focus)
          (key "l" "Right" focus-pane-right 'next 'herdr-panes-focus))
        (group "x" "Split"
          (key "h" "Left"  split-pane-left)
          (key "j" "Down"  split-pane-down)
          (key "k" "Up"    split-pane-up)
          (key "l" "Right" split-pane-right))
        (group "m" "Move Pane"
          'exit-on-unknown #t
          (key "h" "Left"  move-pane-left  'next 'self)
          (key "j" "Down"  move-pane-down  'next 'self)
          (key "k" "Up"    move-pane-up    'next 'self)
          (key "l" "Right" move-pane-right 'next 'self))
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
        ;; Worktrees surface (k6). `g` (= git worktree; `w` is Workspaces) drills
        ;; a live worktree list: digit → smart-switch (focus the live workspace
        ;; when open, else open the dormant worktree); `n` prompts a branch and
        ;; creates one; `d` removes the focused worktree behind a confirm (no
        ;; --force). All source-pinned via the focused workspace id.
        (open "g" "Worktrees"
          (key "n" "New"    new-worktree!)
          (key "d" "Remove" remove-focused-worktree!)
          (panel "Worktrees" (worktree-list-block)))
        ;; Agents surface (k5). `b` jumps to the next blocked agent in one
        ;; keystroke (the differentiator); `a` drills into the Agents live-list
        ;; (status-badged, blocked-first, digit → focus by id). v1 focus-only
        ;; (D8) — no send/read/explain, so the drill is just the list panel.
        (key "b" "Jump to Blocked" jump-to-next-blocked)
        (open "a" "Agents"
          (panel "Agents" (agent-list-block)))
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
        'herdr-pane-digit
        toggle-pane-zoom
        configured?))

    ;; Register the backend + the digit-jump mode + the Walk top-level
    ;; focus mode the herdr tree crosses into. Safe to call more than once:
    ;; register-backend! is last-write-wins on backend symbol; register-tree!
    ;; replaces any prior tree of the same id.
    (define (register!)
      (register-backend! backend)
      (pane-digit-register!)
      (focus-mode-register!))))
