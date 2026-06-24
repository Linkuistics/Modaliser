;; (modaliser apps iterm) — iTerm dynamic-pane builder and sticky focus mode.
;;
;; The dynamic iTerm tree is rebuilt on every leader press (via
;; set-local-context-suffix!) so pane bindings track the current pane
;; layout. Pane chips are painted while the overlay is visible; each
;; chip's digit focuses that pane by UUID (race-free, no event injection).
;;
;; Quick start (prefix-style import — recommended; bare exports like
;; `register!`, `tree`, etc. collide with peer libraries):
;;   (import (prefix (modaliser apps iterm) iterm:))
;;   (iterm:register!)
;;
;; Chip appearance (font size, colour, border, etc.) lives in the .chip
;; CSS rule in base.css / ~/.config/modaliser/theme.css — see
;; (modaliser theming). Pass overrides by editing CSS, not by threading
;; option alists through the library.
;;
;; Defaults mirror the bundled seed: digit pane labels 1..0, transient
;; tree with "c Copy Mode"; "h/j/k/l Focus <dir>" (each fires the
;; corresponding Cmd+Alt+arrow keystroke AND transitions into the
;; sticky 'iterm-panes-focus mode, so subsequent hjkl presses keep
;; moving without another leader press); "z Toggle Zoom"; and a "x
;; Split" group. The sticky 'iterm-panes-focus tree contains only the
;; Cmd+Alt+arrow hjkl focus moves.
;;
;; If you've already installed your own (set-local-context-suffix! …),
;; pass 'install-context-suffix? #f and call context-suffix-handler
;; from inside your own composed handler.
;;
;; Pane selection bridges AX → iTerm AppleScript by walk-order index:
;; AX gives us each pane's frame (chip placement) and a 0-based 'idx
;; field; AppleScript's `id of every session of current tab` returns
;; session UUIDs in the same order (iTerm's session enumeration is the
;; NSView subview-tree DFS, same as AX walks). The N-th pane corresponds
;; to the N-th UUID. We resolve at discovery time so each chip action
;; binds directly to its UUID — race-free, no event injection. UUIDs are
;; URL-safe (alphanumeric + hyphens), so inlining into AppleScript
;; source needs no escaping.

(define-library (modaliser apps iterm)
  (export rebuild-tree!
          focus-mode-tree
          focus-mode-register!
          context-suffix-handler
          register!
          default-pane-labels
          pane-list-block
          select-session-by-id
          tab-list-block
          select-tab-by-index
          configure-entry iterm-configured?)
  (import (scheme base)
          (modaliser dsl)
          (modaliser state-machine)
          (modaliser event-dispatch)
          (modaliser util)
          (modaliser shell)
          (modaliser input)
          (modaliser accessibility)
          (modaliser hints)
          (modaliser ax-hints)
          ;; The 14 façade ops live on (modaliser terminal); this module's
          ;; own focus/split/move-pane-* defines are internal implementations
          ;; the iTerm backend record points at, not public surface. Importing
          ;; the façade without its op names would silently shadow them here;
          ;; importing with `except` is fine because the defines below are
          ;; the only callers.
          (except (modaliser terminal)
                  focus-pane-left focus-pane-right focus-pane-up focus-pane-down
                  split-pane-left split-pane-right split-pane-up split-pane-down
                  move-pane-left  move-pane-right  move-pane-up  move-pane-down
                  focus-pane-by-digit toggle-pane-zoom)
          (modaliser theming)
          (modaliser blocks iterm-panes)
          (modaliser blocks iterm-tabs))
  (begin

    (define default-pane-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Returns a thunk that fires send-keystroke on call. The thunk
    ;; lands cleanly as the third arg of `(key K L …)`: the macro
    ;; evaluates the call eagerly, gets a procedure back, and uses it
    ;; as the action thunk.
    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    ;; Query iTerm for the UUIDs of every session in the focused window's
    ;; current tab. iTerm's `id of every session` returns "U1, U2, ..."
    ;; (one line, comma-space separated). UUIDs don't contain commas, so
    ;; the parse is safe.
    (define (iterm-list-session-ids)
      (let* ((out (run-shell
                    (string-append
                      "osascript -e 'tell application \"iTerm\" to "
                      "id of every session of current tab of current window' "
                      "2>/dev/null")))
             (trimmed (string-trim out)))
        (if (string=? trimmed "")
          '()
          (let loop ((parts (string-split trimmed ",")) (acc '()))
            (cond
              ((null? parts) (reverse acc))
              (else
                (let ((s (string-trim (car parts))))
                  (loop (cdr parts)
                        (if (string=? s "") acc (cons s acc))))))))))

    ;; UUIDs are URL-safe — inline into AppleScript source without
    ;; escaping. Only the pre-validated UUID is interpolated; no name
    ;; interpolation, no shell quoting hazards.
    (define (iterm-select-session-by-id session-id)
      (run-shell
        (string-append
          "osascript -e 'tell application \"iTerm\" to "
          "tell first session of current tab of current window "
          "whose id is \"" session-id "\" to select' "
          "2>/dev/null")))

    ;; ─── Public pane operations ──────────────────────────────────
    ;;
    ;; Twelve 0-arg procedures that consumers drop straight into
    ;; `(key ... ACTION ...)` slots. Every pane op is a synthesized
    ;; keystroke routed through iTerm's GlobalKeyMap — the reliable
    ;; target for synthetic CGEvents (unlike NSMenu key equivalents).
    ;;
    ;; A key-triggered split goes through iTerm's own key handler, so
    ;; iTerm focuses the new pane natively — no UUID bookkeeping. iTerm
    ;; has no native "split before", so left/up split after (Cmd+D /
    ;; Cmd+Shift+D) then swap the new pane with its left/above
    ;; neighbour.
    ;;
    ;; Splits and moves depend on iTerm key bindings the
    ;; "Configure iTerm" action provisions (see iterm-binding-specs).
    ;; Focus uses iTerm's shipped Cmd+Opt+Arrow defaults — no setup.

    (define (focus-pane-left)  (send-keystroke '(cmd alt) "left"))
    (define (focus-pane-right) (send-keystroke '(cmd alt) "right"))
    (define (focus-pane-up)    (send-keystroke '(cmd alt) "up"))
    (define (focus-pane-down)  (send-keystroke '(cmd alt) "down"))

    (define (split-pane-right) (send-keystroke '(cmd) "d"))
    (define (split-pane-down)  (send-keystroke '(cmd shift) "d"))

    (define (split-pane-left)
      (send-keystroke '(cmd) "d")              ; split right; iTerm focuses new pane
      (send-keystroke '(cmd ctrl shift) "h"))  ; swap new pane leftward

    (define (split-pane-up)
      (send-keystroke '(cmd shift) "d")
      (send-keystroke '(cmd ctrl shift) "k"))

    (define (move-pane-left)  (send-keystroke '(cmd ctrl shift) "h"))
    (define (move-pane-right) (send-keystroke '(cmd ctrl shift) "l"))
    (define (move-pane-up)    (send-keystroke '(cmd ctrl shift) "k"))
    (define (move-pane-down)  (send-keystroke '(cmd ctrl shift) "j"))

    ;; The 14th op. iTerm's user-visible zoom toggle is the provisioned
    ;; Cmd+Shift+Return binding (see iterm-binding-specs: maximize active
    ;; pane). configure-entry writes it; the user's tree already proxies
    ;; "z Toggle Zoom" through the same keystroke.
    (define (toggle-pane-zoom)
      (send-keystroke '(cmd shift) "return"))

    ;; UUID of the focused iTerm session. AppleScript's `is running`
    ;; guard prevents probe-time Launch Services auto-launch — see
    ;; (focused-iterm-tty) for the same pattern.
    (define (focused-pane-id)
      (let* ((script
               (string-append
                 "if application \"iTerm2\" is running then "
                 "tell application \"iTerm2\" to "
                 "id of current session of current tab of current window"))
             (out (run-shell
                    (string-append "osascript -e '" script "' 2>/dev/null")))
             (trimmed (string-trim out)))
        (if (string=? trimmed "") #f trimmed)))

    ;; Foreground command of the focused iTerm pane. The host-level
    ;; detect-fg slot the façade reads to descend into a mux (tmux,
    ;; zellij) running inside iTerm. Composes the legacy primitives
    ;; rather than introducing new shell.
    (define (detect-fg-command)
      (cond ((focused-iterm-tty) => tty-foreground-command)
            (else #f)))

    ;; ─── iTerm key-binding provisioning ──────────────────────────
    ;;
    ;; The pane ops above, plus the overlay's copy-mode and zoom
    ;; keys, need eight entries in iTerm's GlobalKeyMap.
    ;; `configure-entry` surfaces a one-shot overlay action that adds
    ;; them; it stays hidden once iTerm is configured.
    ;;
    ;; Each spec is (plist-key action-code json-text human-desc).
    ;; Values are copied verbatim from what iTerm 3.6 writes when the
    ;; bindings are added by hand: the swap actions use distinct codes
    ;; (53–56) with empty Text; the splits, copy mode and maximize
    ;; share Action 25 ("Select Menu Item") and carry the menu title
    ;; in Text — including the doubled line iTerm emits.
    ;; The Text strings are pre-escaped for JSON (\\n → newline).

    (define iterm-split-text-v
      "Split Vertically with Current Profile\\nSplit Vertically with Current Profile")
    (define iterm-split-text-h
      "Split Horizontally with Current Profile\\nSplit Horizontally with Current Profile")
    (define iterm-copy-mode-text
      "Copy Mode\\nCopy Mode")
    (define iterm-maximize-text
      "Maximize Active Pane\\nMaximize Active Pane")

    (define iterm-binding-specs
      (list
        (list "0x48-0x160000-0x4"  53 ""                   "swap pane left")
        (list "0x4a-0x160000-0x26" 56 ""                   "swap pane down")
        (list "0x4b-0x160000-0x28" 55 ""                   "swap pane up")
        (list "0x4c-0x160000-0x25" 54 ""                   "swap pane right")
        (list "0x64-0x100000-0x2"  25 iterm-split-text-v   "split pane right")
        (list "0x44-0x120000-0x2"  25 iterm-split-text-h   "split pane down")
        (list "0x43-0x120000-0x8"  25 iterm-copy-mode-text "copy mode")
        (list "0xd-0x120000-0x24"  25 iterm-maximize-text  "maximize active pane")))

    ;; JSON dict for one binding spec — matches iTerm's stored shape.
    (define (iterm-binding-json spec)
      (string-append
        "{\"Action\":" (number->string (cadr spec))
        ",\"Apply Mode\":0,\"Escaping\":2"
        ",\"Text\":\"" (list-ref spec 2) "\""
        ",\"Version\":2}"))

    ;; One `plutil -replace` line writing a single binding into the
    ;; working snapshot ($SNAP). -json keeps Action/Version/Escaping
    ;; as real integers; the `defaults` CLI can only express strings.
    (define (iterm-replace-line spec)
      (string-append
        "plutil -replace 'GlobalKeyMap." (car spec) "' "
        "-json '" (iterm-binding-json spec) "' \"$SNAP\"\n"))

    ;; Shell snippet (zsh) resolving where iTerm reads its preferences
    ;; from. iTerm's "Load preferences from a custom folder" option
    ;; (Preferences → General → Settings) makes it load — and on quit
    ;; save — a plist under PrefsCustomFolder, ignoring the standard
    ;; cfprefsd domain on launch. When it is on, both probing and
    ;; provisioning must target that file: writing the standard domain
    ;; has no lasting effect, as iTerm overwrites it from the custom
    ;; folder on next launch.
    ;;
    ;; Sets TARGET to the custom-folder plist path, or leaves it empty
    ;; when iTerm uses the standard domain. LoadPrefsFromCustomFolder
    ;; and PrefsCustomFolder themselves live in the standard domain.
    (define iterm-resolve-target-sh
      (string-append
        "CUSTOM=$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null)\n"
        "CF=$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null)\n"
        "CF=\"${CF/#\\~/$HOME}\"\n"
        "TARGET=\"\"\n"
        "if [ \"$CUSTOM\" = \"1\" ] && [ -n \"$CF\" ]; then\n"
        "  TARGET=\"$CF/com.googlecode.iterm2.plist\"\n"
        "fi\n"))

    ;; The full provisioning script.
    ;;
    ;; iTerm is quit first — a running iTerm holds GlobalKeyMap in
    ;; memory and would overwrite the change on its next pref-save —
    ;; and relaunched at the end. A timestamped backup of the prefs
    ;; as they were is saved alongside the standard domain plist.
    ;;
    ;; The eight bindings are spliced into a working snapshot ($SNAP)
    ;; with plutil — `defaults` cannot write integer-typed values —
    ;; and committed to wherever iTerm will read on next launch (see
    ;; iterm-resolve-target-sh):
    ;;
    ;;  - Custom prefs folder: copy that folder's plist, edit it,
    ;;    copy it back. iTerm reads the file directly on launch, so
    ;;    no cfprefsd round-trip is involved.
    ;;  - Standard domain: export the cfprefsd domain, edit it,
    ;;    `defaults import` it back, then `killall cfprefsd`. The
    ;;    import's write to disk is asynchronous; killing cfprefsd
    ;;    forces a flush so the relaunched iTerm reads the committed
    ;;    file rather than racing it.
    (define iterm-provision-script
      (string-append
        iterm-resolve-target-sh
        "osascript -e 'tell application \"iTerm\" to quit' 2>/dev/null || true\n"
        "for i in $(seq 1 60); do pgrep -x iTerm2 >/dev/null 2>&1 || break; sleep 0.1; done\n"
        "SNAP=$(mktemp -t modaliser-iterm-provision)\n"
        "if [ -n \"$TARGET\" ] && [ -f \"$TARGET\" ]; then\n"
        "  cp \"$TARGET\" \"$SNAP\"\n"
        "else\n"
        "  defaults export com.googlecode.iterm2 \"$SNAP\" 2>/dev/null\n"
        "fi\n"
        "cp \"$SNAP\" \"$HOME/Library/Preferences/com.googlecode.iterm2.modaliser-backup-$(date +%Y%m%d-%H%M%S).plist\" 2>/dev/null || true\n"
        "plutil -insert GlobalKeyMap -json '{}' \"$SNAP\" 2>/dev/null || true\n"
        (apply string-append (map iterm-replace-line iterm-binding-specs))
        "if [ -n \"$TARGET\" ]; then\n"
        "  cp \"$SNAP\" \"$TARGET\"\n"
        "else\n"
        "  defaults import com.googlecode.iterm2 \"$SNAP\"\n"
        "  killall cfprefsd 2>/dev/null || true\n"
        "  sleep 0.3\n"
        "fi\n"
        "rm -f \"$SNAP\"\n"
        "open -a iTerm\n"))

    ;; Live check: #t when all eight bindings carry the expected
    ;; Action code. The swap codes (53–56) are unique enough to
    ;; identify ours; the Action-25 entries (splits, copy mode,
    ;; maximize) only confirm a menu binding exists on that key.
    ;;
    ;; Probes the same file iTerm loads from — see
    ;; iterm-resolve-target-sh. With a custom prefs folder, that
    ;; folder's plist (read directly); otherwise a `defaults export`
    ;; of the cfprefsd domain — never a raw read of the standard
    ;; on-disk plist, which lags cfprefsd and would read stale.
    ;;
    ;; ${1} is braced deliberately: run-shell executes via zsh, and a
    ;; bare $1:Action lets zsh read ":A" as its absolute-path history
    ;; modifier — rewriting the key to <cwd>/<key> so every probe fails.
    (define (iterm-probe-configured?)
      (let ((checks
              (apply string-append
                (map (lambda (spec)
                       (string-append "ck " (car spec) " "
                                      (number->string (cadr spec)) "\n"))
                     iterm-binding-specs))))
        (string=?
          (string-trim
            (run-shell
              (string-append
                iterm-resolve-target-sh
                "if [ -n \"$TARGET\" ]; then\n"
                "  P=\"$TARGET\"\n"
                "else\n"
                "  P=$(mktemp -t modaliser-iterm-probe)\n"
                "  defaults export com.googlecode.iterm2 \"$P\" 2>/dev/null\n"
                "fi\n"
                "ok=yes\n"
                "ck() { v=$(/usr/libexec/PlistBuddy -c "
                "\"Print :GlobalKeyMap:${1}:Action\" \"$P\" 2>/dev/null); "
                "[ \"$v\" = \"$2\" ] || ok=no; }\n"
                checks
                "[ -n \"$TARGET\" ] || rm -f \"$P\"\n"
                "echo $ok")))
          "yes")))

    ;; Cached configured? flag. The overlay's 'hidden thunk reads
    ;; iterm-configured? on every render, so the probe must be cheap
    ;; — hence the cache. 'unknown forces a one-time lazy probe.
    (define *iterm-configured* 'unknown)

    (define (iterm-configured?)
      (when (eq? *iterm-configured* 'unknown)
        (set! *iterm-configured* (iterm-probe-configured?)))
      *iterm-configured*)

    (define (iterm-refresh-configured!)
      (set! *iterm-configured* (iterm-probe-configured?))
      *iterm-configured*)

    ;; Rewrite each ' to the POSIX '\'' idiom so the string is safe to
    ;; interpolate inside a single-quoted /bin/zsh word. A single quote
    ;; can't be backslash-escaped *within* single quotes — it must close
    ;; the quote, emit an escaped literal ', then reopen. Without this an
    ;; apostrophe (the dialog message has "iTerm's") terminates
    ;; osascript's -e '...' argument mid-string.
    (define (shell-sq-escape s)
      (let loop ((cs (string->list s)) (acc '()))
        (if (null? cs)
          (list->string (reverse acc))
          (loop (cdr cs)
                (if (char=? (car cs) #\')
                  (cons #\' (cons #\' (cons #\\ (cons #\' acc))))
                  (cons (car cs) acc))))))

    (define iterm-configure-dialog-message
      (string-append
        "Modaliser drives iTerm pane splits, swaps and menu actions "
        "through eight key bindings that are not yet all set up in "
        "iTerm.\n\n"
        "Choosing Continue will:\n\n"
        "  - Quit iTerm (any unsaved work in iTerm is lost)\n"
        "  - Add these bindings to iTerm's preferences:\n"
        "       Ctrl+Shift+H/J/K/L - swap pane left/down/up/right\n"
        "       Cmd+D  - split pane right\n"
        "       Cmd+Shift+D - split pane down\n"
        "       Cmd+Shift+C - copy mode\n"
        "       Cmd+Shift+Return - maximize active pane\n"
        "  - Relaunch iTerm\n\n"
        "A timestamped backup of iTerm's preferences is saved first."))

    ;; Show the confirm dialog; #t if the user chose Continue. The
    ;; cancel button raises osascript error -128 → empty stdout, so
    ;; "not Continue" is treated as cancelled.
    (define (iterm-confirm-configure)
      (string-contains?
        (run-shell
          (string-append
            "osascript -e 'display dialog \""
            (shell-sq-escape iterm-configure-dialog-message)
            "\" with title \"Configure iTerm\" "
            "buttons {\"Cancel\", \"Continue\"} "
            "default button \"Cancel\" cancel button \"Cancel\" "
            "with icon caution' 2>/dev/null"))
        "Continue"))

    ;; Overlay action: confirm, provision, re-probe. Idempotent — if
    ;; iTerm is already configured (e.g. the key was pressed while the
    ;; entry was hidden) it just syncs the cache and returns.
    (define (iterm-configure!)
      (cond
        ((iterm-probe-configured?)
         (iterm-refresh-configured!))
        ((iterm-confirm-configure)
         (run-shell iterm-provision-script)
         (iterm-refresh-configured!))
        (else #f)))

    ;; A `(key …)` node for the iTerm tree, bound to Ctrl+Shift+I.
    ;; Its 'hidden property is the iterm-configured? thunk, so the
    ;; entry renders only while iTerm is unconfigured and vanishes —
    ;; without a Modaliser reload — on the next overlay open after
    ;; iterm-configure! re-probes.
    (define (configure-entry)
      (cons (cons 'hidden iterm-configured?)
            (key "C-I" "Configure iTerm" iterm-configure!)))

    ;; Build a single (key-range ...) node covering every labelled pane.
    ;; Display key is "<first>.." reflecting actually-bound count (so a
    ;; 3-pane window reads "1.." rather than the full label list). If
    ;; AppleScript returns fewer UUIDs than AX found scroll areas, those
    ;; panes are dropped from the range. Returns a 0- or 1-element list
    ;; so the caller's (append (iterm-pane-bindings …) …) keeps splicing
    ;; cleanly.
    (define (iterm-pane-bindings labelled-panes session-ids range-label)
      (let loop ((ps labelled-panes) (label->sid '()) (keys '()))
        (cond
          ((null? ps)
           (cond
             ((null? keys) '())
             (else
               (let* ((alist  label->sid)
                      (ks     (reverse keys))
                      (first  (car ks))
                      (display (string-append first ".."))) ; e.g. "1.."
                 (list
                   (key-range display range-label
                     ks
                     (lambda (k)
                       (let ((entry (assoc k alist)))
                         (when entry
                           (iterm-select-session-by-id (cdr entry)))))))))))
          (else
            (let* ((entry (car ps))
                   (label (car entry))
                   (pane  (cdr entry))
                   (idx   (cdr (assoc 'idx pane)))
                   (sid   (and (< idx (length session-ids))
                               (list-ref session-ids idx))))
              (loop (cdr ps)
                    (if sid (cons (cons label sid) label->sid) label->sid)
                    (if sid (cons label keys)                  keys)))))))

    ;; Rebuild and re-register the 'com.googlecode.iterm2 tree from
    ;; the current iTerm pane layout. Cheap when iTerm isn't running
    ;; (AX returns empty, no panes contribute to the range).
    ;;
    ;; Chip styling is no longer threaded through opts. Hint chips read
    ;; their resolved appearance from (current-chip-theme), driven by
    ;; the .chip rule in base.css + ~/.config/modaliser/theme.css. The
    ;; old 'hint-options keyword raises a migration error.
    (define (rebuild-tree! . opts)
      (let ((alist (apply props->alist opts)))
        ;; Guard runs before any AX / AppleScript work so a stale config
        ;; passing the legacy keyword fails fast instead of paying the
        ;; full discovery cost first.
        (when (assoc 'hint-options alist)
          (error
            "rebuild-tree!: 'hint-options removed — edit .chip in ~/.config/modaliser/theme.css instead"))
        (let* ((labels       (alist-ref alist 'pane-labels default-pane-labels))
               (range-label  (alist-ref alist 'pane-range-label "Focus Pane <n>"))
               (sticky-id    (alist-ref alist 'sticky-mode-id 'iterm-panes-focus))
               (raw-panes    (ax-find-elements-named
                               "com.googlecode.iterm2" "AXScrollArea" "AXStaticText"))
               (panes        (label-pairs labels raw-panes))
               (session-ids  (iterm-list-session-ids)))
        (apply screen 'com.googlecode.iterm2
          'on-enter (lambda ()
                      (hints-show
                        (ax-target-hints panes (current-chip-theme 'normal))))
          'on-leave (lambda () (hints-hide))
          (append
            (iterm-pane-bindings panes session-ids range-label)
            (list
              (key "c" "Copy Mode" (keystroke '(cmd shift) "c"))
              (key "z" "Toggle Zoom" (keystroke '(cmd shift) "return"))
              ;; hjkl: focus-move AND transition into the sticky focus
              ;; mode in a single press. First leader → h moves left and
              ;; lands the user in 'iterm-panes-focus, so subsequent hjkl
              ;; keys keep moving without another leader. The overlay
              ;; paints a ↻ marker on each (via 'sticky-target). Grouped
              ;; into a "Focus" panel so the cluster reads as one
              ;; semantic unit at the top of the overlay.
              (panel "Focus"
                (key "h" "Left"  focus-pane-left  'sticky-target sticky-id)
                (key "j" "Down"  focus-pane-down  'sticky-target sticky-id)
                (key "k" "Up"    focus-pane-up    'sticky-target sticky-id)
                (key "l" "Right" focus-pane-right 'sticky-target sticky-id))
              ;; Right/down split directly; left/up split-then-swap.
              ;; All four refocus the new pane by UUID — see
              ;; split-pane-* for the iTerm bindings the swap step
              ;; depends on.
              (group "x" "Split"
                (key "h" "Left"  split-pane-left)
                (key "j" "Down"  split-pane-down)
                (key "k" "Up"    split-pane-up)
                (key "l" "Right" split-pane-right))
              ;; Move Pane modal — m enters a sticky group whose hjkl
              ;; keys swap the focused pane with its neighbour in that
              ;; direction. Each press swaps and stays in the group
              ;; (per 'sticky #t); any other key exits (per
              ;; 'exit-on-unknown #t). Depends on the same iTerm
              ;; bindings as split-pane-left/up.
              (group "m" "Move Pane"
                'sticky #t
                'exit-on-unknown #t
                (key "h" "Left"  move-pane-left)
                (key "j" "Down"  move-pane-down)
                (key "k" "Up"    move-pane-up)
                (key "l" "Right" move-pane-right))))))))

    ;; Sticky focus-mode children. Pure hjkl focus moves, entered from
    ;; the transient tree via any of its hjkl keys (each carries a
    ;; 'sticky-target → here) or via (enter-mode! 'iterm-panes-focus).
    (define (focus-mode-tree)
      (list
        (key "h" "Left"  focus-pane-left)
        (key "j" "Down"  focus-pane-down)
        (key "k" "Up"    focus-pane-up)
        (key "l" "Right" focus-pane-right)))

    (define (focus-mode-register! . opts)
      (let* ((alist     (apply props->alist opts))
             (id        (alist-ref alist 'sticky-mode-id 'iterm-panes-focus))
             (disp-name (alist-ref alist 'display-name "Focus")))
        (apply register-tree! id
          'sticky #t
          'exit-on-unknown #t
          'display-name disp-name
          (focus-mode-tree))))

    ;; Variant string for the focused iTerm pane, used by the
    ;; (modaliser event-dispatch) dispatcher to select sub-tree variants
    ;; like 'com.googlecode.iterm2/nvim. Returns #f if no variant applies.
    ;;
    ;; Side-effect: refreshes the iTerm pane snapshot so chip rendering
    ;; and digit dispatch see the current pane layout. When 'rebuild? is
    ;; #t (default), also rebuilds the library's stock iTerm tree —
    ;; necessary if the library owns the tree (its key-range bakes UUIDs
    ;; at tree-build time). Pass 'rebuild? #f if your config inlines its
    ;; own (screen 'com.googlecode.iterm2 …) — the rebuild would
    ;; clobber the inline tree, and inline trees typically use
    ;; (iterm:pane-list-block …) which reads the snapshot directly at
    ;; render time.
    ;;
    ;; Accepts the same trailing opts as rebuild-tree! ('pane-labels,
    ;; 'pane-range-label, 'sticky-mode-id). They are forwarded to the
    ;; rebuild call so per-press registrations honour the user's
    ;; customisation rather than reverting to the library's neutral
    ;; defaults. register! captures opts in a closure for this reason;
    ;; users composing their own handler can pass opts at call site too.
    (define (context-suffix-handler bundle-id . opts)
      (cond
        ((equal? bundle-id "com.googlecode.iterm2")
         (let* ((alist     (apply props->alist opts))
                (rebuild?  (alist-ref alist 'rebuild? #t))
                (forwarded
                  (let loop ((kvs opts) (acc '()))
                    (cond
                      ((null? kvs) (reverse acc))
                      ((null? (cdr kvs))
                       (error "context-suffix-handler: odd keyword/value list"))
                      ((eq? (car kvs) 'rebuild?)
                       (loop (cddr kvs) acc))
                      (else
                       (loop (cddr kvs)
                             (cons (cadr kvs) (cons (car kvs) acc))))))))
           (if rebuild?
               (apply rebuild-tree! forwarded)
               (iterm-panes-refresh!))
           (let ((cmd (focused-terminal-foreground-command)))
             (cond
               ((not cmd) #f)
               ((string-contains? cmd "nvim") "/nvim")
               ((or (string-contains? cmd "zellij")
                    (string-contains? cmd "zj"))
                (if (focused-nvim-socket) "/zellij+nvim" "/zellij"))
               (else #f)))))
        (else #f)))

    ;; A standalone "pick a digit to focus a pane" mode. The façade's
    ;; (terminal:focus-pane-by-digit) thunk enters this tree. on-enter
    ;; snapshots the pane layout (so iterm-panes-current-targets is
    ;; populated for focus-by-digit's lookup) and paints chips; on-leave
    ;; hides them. The single hidden key-range dispatches by digit and
    ;; exits the mode automatically (non-sticky default).
    (define (pane-digit-register!)
      (register-tree! 'iterm-pane-digit
        'on-enter
        (lambda ()
          (iterm-panes-refresh!)
          (let* ((raw-panes (ax-find-elements-named
                              "com.googlecode.iterm2"
                              "AXScrollArea" "AXStaticText"))
                 (panes     (label-pairs default-pane-labels raw-panes)))
            (hints-show (ax-target-hints panes (current-chip-theme 'normal)))))
        'on-leave (lambda () (hints-hide))
        (pane-range)))

    ;; Façade slot. Pushes the digit-pick mode; the user's next digit
    ;; press focuses the corresponding pane and pops back.
    (define (focus-pane-by-digit)
      (enter-mode! 'iterm-pane-digit))

    ;; Build the <terminal-backend> record this module hands to
    ;; (modaliser terminal). Same procedures the iterm:focus-pane-*
    ;; etc. exports point at — registering doesn't duplicate
    ;; implementations, it just lets the façade dispatch to them when
    ;; iTerm is frontmost.
    (define (iterm-terminal-backend)
      (make-terminal-backend
        'iterm "iTerm2" 'host "com.googlecode.iterm2"
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        focus-pane-by-digit
        toggle-pane-zoom
        iterm-configured?))

    ;; One-stop convenience: register the dynamic iTerm tree, the sticky
    ;; focus mode, the digit-pick mode, the <terminal-backend> record
    ;; with the façade, and install the context-suffix handler.
    ;;
    ;; Options:
    ;;   'install-tree? BOOL (default #t)
    ;;     #f to skip the (rebuild-tree! …) call. Use when you've
    ;;     written your own (screen 'com.googlecode.iterm2 …) by
    ;;     hand and don't want this thunk to clobber it — the backend
    ;;     record is still registered with the façade so
    ;;     (terminal:focus-pane-*) / (terminal:split-pane-*) etc. work.
    ;;   'install-context-suffix? BOOL (default #t)
    ;;     #f if you compose your own context-suffix handler — yours
    ;;     can then call (context-suffix-handler bid …opts) to delegate
    ;;     the iTerm branch.
    (define (register! . opts)
      (let* ((alist (apply props->alist opts))
             (install-tree?    (alist-ref alist 'install-tree? #t))
             (install-suffix?  (alist-ref alist 'install-context-suffix? #t))
             (forwarded
               (let loop ((kvs opts) (acc '()))
                 (cond
                   ((null? kvs) (reverse acc))
                   ((null? (cdr kvs))
                    (error "register!: odd keyword/value list"))
                   ((memq (car kvs) '(install-tree? install-context-suffix?))
                    (loop (cddr kvs) acc))
                   (else
                    (loop (cddr kvs)
                          (cons (cadr kvs) (cons (car kvs) acc))))))))
        (when install-tree?
          (apply rebuild-tree! forwarded))
        (apply focus-mode-register! forwarded)
        (pane-digit-register!)
        (register-backend! (iterm-terminal-backend))
        (when install-suffix?
          (set-local-context-suffix!
            (lambda (bundle-id)
              (apply context-suffix-handler
                     bundle-id 'rebuild? install-tree? forwarded))))))

    ;; ─── Block-based pane selection ────────────────────────────────
    ;;
    ;; Companion to (modaliser blocks iterm-panes). Mirrors the
    ;; window-actions:list-block shape: wrap the block constructor,
    ;; bundle a hidden 1.. key-range so digits dispatch to the
    ;; freshly-snapshotted pane UUIDs every time the overlay renders.
    ;;
    ;; Usage from config.scm:
    ;;
    ;;   (screen 'com.googlecode.iterm2
    ;;     (key "c" "Copy Mode" …)
    ;;     …
    ;;     (panel "Panes"
    ;;       (iterm:pane-list-block 'chips? #t)))
    ;;
    ;; The 1.. range is marked 'hidden so the renderer doesn't surface
    ;; a redundant "1.. → Pane <n>" row — the pane list block already
    ;; shows the mapping.

    ;; Public passthrough so config-level code can dispatch by UUID
    ;; without reaching into library internals.
    (define (select-session-by-id session-id)
      (iterm-select-session-by-id session-id))

    ;; A pane digit can be pressed before the overlay has rendered — a
    ;; leader-then-digit press faster than the overlay delay — so the
    ;; on-render pane snapshot may not have run yet. If the digit isn't
    ;; in the current snapshot, refresh once on demand and look again.
    (define (focus-by-digit d)
      (let ((entry (or (assoc d (iterm-panes-current-targets))
                       (begin
                         (iterm-panes-refresh!)
                         (assoc d (iterm-panes-current-targets))))))
        (when entry
          (iterm-select-session-by-id (cdr entry)))))

    (define (pane-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Pane <n>"
              default-pane-labels
              (lambda (k) (focus-by-digit k)))))

    ;; cursor-targets-fn rides only on a LIVE block (one with an on-render-fn
    ;; that refreshes iterm-panes-current-targets every render — the 'chips?
    ;; path); a static no-chips block never refreshes its targets, so the
    ;; selection cursor must not attach to it. Same gate as window:list-block.
    (define (pane-list-block . opts)
      (let* ((base  (apply make-iterm-panes-block opts))
             (live? (and (assoc 'on-render-fn base) #t)))
        (append base
                (if live?
                  (list (cons 'cursor-targets-fn iterm-panes-current-targets))
                  '())
                (list (cons 'block-children (list (pane-range)))))))

    ;; ─── Block-based tab selection ─────────────────────────────────
    ;;
    ;; Companion to (modaliser blocks iterm-tabs), shaped exactly like
    ;; the pane block above: wrap the block constructor and bundle a
    ;; hidden 1.. key-range so digits switch to the freshly-snapshotted
    ;; tab by position every time the overlay renders. Unlike panes there
    ;; are no chips — iTerm tabs live in the tab bar, so the block only
    ;; contributes a row list.
    ;;
    ;; Usage from config.scm — a keyed sub-screen under the iTerm tree:
    ;;
    ;;   (open "t" "Tab"
    ;;     (key "r" "Rename" rename-iterm-tab!)
    ;;     (key "n" "New"    new-iterm-tab!)
    ;;     (key "d" "Delete" close-iterm-tab!)
    ;;     (panel "Tabs"
    ;;       (iterm:tab-list-block)))

    ;; Index is the tab's 1-based position rendered as a string by the
    ;; tab snapshot — numeric only, so inlining into AppleScript is safe.
    (define (iterm-select-tab-by-index index-str)
      (run-shell
        (string-append
          "osascript -e 'tell application \"iTerm\" to "
          "tell tab " index-str " of current window to select' "
          "2>/dev/null")))

    ;; Public passthrough — mirrors select-session-by-id.
    (define (select-tab-by-index index-str)
      (iterm-select-tab-by-index index-str))

    ;; Same on-demand refresh fallback as focus-by-digit: a tab digit can
    ;; be pressed before the overlay's on-render snapshot has run (a
    ;; leader-then-digit press faster than the overlay delay).
    (define (tab-select-by-digit d)
      (let ((entry (or (assoc d (iterm-tabs-current-targets))
                       (begin
                         (iterm-tabs-refresh!)
                         (assoc d (iterm-tabs-current-targets))))))
        (when entry
          (iterm-select-tab-by-index (cdr entry)))))

    ;; Hidden 1.. range: digits switch to the tab at that position. The
    ;; tab list block already shows the label→title mapping, so the
    ;; renderer suppresses this row ('hidden #t), as pane-range does.
    (define (tab-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Tab <n>"
              default-pane-labels
              (lambda (k) (tab-select-by-digit k)))))

    ;; The tabs block always carries an on-render-fn (it snapshots every render,
    ;; chips or not), so the live? gate is always satisfied here — applied for
    ;; uniformity with the pane/window wrappers, not because a static tab block
    ;; exists today.
    (define (tab-list-block . opts)
      (let* ((base  (apply make-iterm-tabs-block opts))
             (live? (and (assoc 'on-render-fn base) #t)))
        (append base
                (if live?
                  (list (cons 'cursor-targets-fn iterm-tabs-current-targets))
                  '())
                (list (cons 'block-children (list (tab-range)))))))))

