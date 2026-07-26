;; (modaliser apps iterm) — the iTerm host: the backend record (with the
;; 'canvas-frame host capability) and the digit-jump mode tree, composed
;; through one pure `wiring` fragment (ADR-0018), plus the pane/tab ops
;; and list blocks a screen binds.
;;
;; Quick start (prefix-style import — recommended; bare exports like
;; `wiring`, `pane-list-block`, etc. collide with peer libraries):
;;   (import (prefix (modaliser apps iterm) iterm:))
;;   (configuration (iterm:wiring) iterm-screen …)
;;
;; That is the WIRING half only. The iTerm SCREEN — which of the ops
;; below are surfaced, on which keys, under which labels — is
;; configuration, not facility (ADR-0021): it lives in the user's
;; config.scm as a (screen 'com.googlecode.iterm2 …), and
;; default-config.scm ships the stock composition to read and edit.
;;
;; Chip appearance (font size, colour, border, etc.) lives in the .chip
;; CSS rule in base.css / ~/.config/modaliser/theme.css — see
;; (modaliser theming). Pass overrides by editing CSS, not by threading
;; option alists through the library.
;;
;; Pane selection is the pane-list block: chips + a row list + digits
;; dispatching by session UUID, re-snapshotted on every overlay open —
;; no per-press tree rebuild.
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
  (export ;; ── The wiring fragment (ADR-0018 / ADR-0021) ──────────────
          ;;
          ;; Everything iTerm's integration needs and nothing a user
          ;; would want to choose: the backend record (whose
          ;; 'canvas-frame capability feeds inner tools' chip geometry,
          ;; and whose match-key is what makes a screen under
          ;; 'com.googlecode.iterm2 terminal-like) and the
          ;; machinery-named digit-jump tree the record fires at.
          ;;
          ;;   (configuration (iterm:wiring) my-iterm-screen …)
          ;;
          ;; The iTerm SCREEN is configuration, not facility (ADR-0021),
          ;; so it lives in the user's own config.scm; the seeded
          ;; default-config.scm carries the stock composition to read and
          ;; edit. Two scope symbols crossing the boundary are machinery,
          ;; not preference: 'com.googlecode.iterm2 (the backend's
          ;; match-key — a screen authored under any other scope is not
          ;; terminal-like) and 'iterm-pane-digit (the record's
          ;; focus-pane-by-digit slot names it by key).
          wiring
          ;; ── Ops: the verbs a screen binds (ADR-0021) ───────────────
          ;;
          ;; One name per thing iTerm can do, all 0-arg thunks that land
          ;; straight in a `(key K L op)` slot. This is the stable layer:
          ;; every one of them is a synthesized keystroke whose
          ;; correctness is fixed by iTerm's own key map (the shipped
          ;; Cmd+Alt+Arrow focus defaults, or a binding `configure!`
          ;; provisions), not by anybody's preference.
          focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
          split-pane-left  split-pane-right  split-pane-up    split-pane-down
          move-pane-left   move-pane-right   move-pane-up     move-pane-down
          toggle-pane-zoom copy-mode
          rename-tab! new-tab! close-tab!
          ;; The tab list is a vertical strip, so "previous"/"next" is the
          ;; direction-free naming; which of h/j/k/l reaches each is the
          ;; screen's call.
          tab-focus-prev tab-focus-next tab-move-prev tab-move-next
          ;; ── Provisioning ───────────────────────────────────────────
          ;;
          ;; `configure!` writes the eight iTerm key bindings the split,
          ;; move, copy-mode and zoom ops ride on; `configured?` is the
          ;; cached probe saying whether they are already there. Both are
          ;; facilities — what iTerm needs is iTerm's business. Surfacing
          ;; the action, and retiring the row once the probe passes, is
          ;; the configuration's:
          ;;
          ;;   (key "C-I" "Configure iTerm" iterm:configure!
          ;;        'hidden iterm:configured?)
          configure! configured?
          ;; ── Blocks and the ops behind them ─────────────────────────
          default-pane-labels
          pane-list-block
          select-session-by-id
          tab-list-block
          select-tab-by-index
          ;; Tab-scoped session count source for pane-UUID resolution:
          ;; `sessions of current tab of current window`, NOT an all-tabs AX
          ;; scroll-area count.
          iterm-list-session-ids
          ;; Test seam (ADR-0014): a parameterized indirection point a test
          ;; can override so no test quits/reconfigures a real iTerm
          ;; (feedback_no_live_env_mutation_in_tests) — mirrors
          ;; current-dialog-runner / current-herdr-send-runner.
          current-iterm-provision-runner)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (modaliser dialogs)
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
          ;; The contribution constructors for `fragment` below. Prefixed:
          ;; the bare names (tree, backend, context, …) collide with too
          ;; much of this module's own vocabulary.
          (prefix (modaliser configuration) config:)
          (modaliser blocks iterm-panes)
          (modaliser blocks iterm-tabs))
  (begin

    (define default-pane-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

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
    ;; pane), which `configure!` writes.
    (define (toggle-pane-zoom)
      (send-keystroke '(cmd shift) "return"))

    ;; iTerm's own copy mode, on the provisioned Cmd+Shift+C binding (see
    ;; iterm-binding-specs). Not a pane op — it rides the same
    ;; provisioning, so it lives beside them.
    (define (copy-mode)
      (send-keystroke '(cmd shift) "c"))

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

    ;; ─── Tab operations ──────────────────────────────────────────
    ;;
    ;; Moved in from the seeded iTerm app-tree (library-fragments-k11):
    ;; the stock tree below binds them, and they are exported as
    ;; composition blocks for user-built trees.

    ;; Tab rename — clicks iTerm's Window > Tab > Edit Tab Title menu via
    ;; System Events. iTerm opens its inline tab-bar editor; the user
    ;; types the new title and presses Enter inside iTerm.
    ;;
    ;; iTerm's `tab` class advertises a writable `title` property but
    ;; rejects writes at runtime (AppleEvent -10000). `name of session`
    ;; *is* writable and surfaces in the tab bar, but shell title escapes
    ;; (\e]0;…\a from precmd hooks) clobber it on the next prompt — and
    ;; it's not the per-tab override the menu sets. The menu click is the
    ;; only path to the real override.
    (define (rename-tab!)
      (run-shell
       (string-append
        "osascript -e 'tell application \"System Events\" to tell process \"iTerm2\" "
        "to click menu item \"Edit Tab Title\" of menu \"Tab\" "
        "of menu item \"Tab\" of menu \"Window\" of menu bar 1' "
        "2>/dev/null")))

    ;; New tab inheriting the current session's profile, so it matches
    ;; whatever you're in now rather than the default profile. The profile
    ;; is read and used entirely inside AppleScript — nothing crosses into
    ;; the shell, so there is nothing to escape. (Inside `tell current
    ;; window`, `current session` already resolves to that window; adding
    ;; `of current window` there would double-resolve and error.)
    (define (new-tab!)
      (run-shell
       (string-append
        "osascript -e 'tell application \"iTerm\" to tell current window "
        "to create tab with profile (profile name of current session)' "
        "2>/dev/null")))

    ;; Close the focused tab. iTerm raises its own "a job is running"
    ;; confirmation when the tab has a live process, so no extra guard.
    (define (close-tab!)
      (run-shell
       (string-append
        "osascript -e 'tell application \"iTerm\" to "
        "close (current tab of current window)' "
        "2>/dev/null")))

    ;; ─── The 'canvas-frame host capability ───────────────────────
    ;;
    ;; The host-specific glue an inner tool's chip geometry needs
    ;; (docs/specs/configuration-value.md "Host capabilities, consumed
    ;; generically"; CONTEXT.md "Grid frame"): given an inner tool's
    ;; canvas cell totals, the calibrated pixel frame that canvas maps
    ;; onto — measured top-left character cell (the grid origin and true
    ;; cell size) composed with the raw AXScrollArea frame through the
    ;; host-neutral calibrated-grid-frame. #f when iTerm is unreachable;
    ;; the consumer (herdr's chip painting) skips painting then. Rides
    ;; the backend record below and is consumed through the terminal
    ;; façade's (host-capability 'canvas-frame) — no inner tool names
    ;; iTerm.
    ;;
    ;; Replace-mode caveat: the probe takes the FIRST AXScrollArea. When
    ;; the inner tool owns the sole one (herdr in replace mode) the frame
    ;; is right; among several splits it may be the wrong one — chips can
    ;; land on the wrong pixels, ops are unaffected (documented v1
    ;; limitation, docs/reference/terminal-detection.md).
    (define (canvas-frame-probe total-w total-h)
      (calibrated-grid-frame
        (ax-first-visible-char-bounds "com.googlecode.iterm2")
        (let ((areas (ax-find-elements-named
                       "com.googlecode.iterm2" "AXScrollArea" "AXStaticText")))
          (and (pair? areas) (car areas)))
        total-w total-h))

    ;; ─── iTerm key-binding provisioning ──────────────────────────
    ;;
    ;; The pane ops above, plus the copy-mode and zoom ops, need eight
    ;; entries in iTerm's GlobalKeyMap. `configure!` adds them and
    ;; `configured?` reports whether they are already there; a
    ;; configuration binds the first and gates the row on the second.
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

    ;; Cached configured? flag. A configuration that gates its setup row
    ;; on `configured?` has the overlay reading it on every render, so
    ;; the probe must be cheap — hence the cache. 'unknown forces a
    ;; one-time lazy probe.
    (define *iterm-configured* 'unknown)

    (define (configured?)
      (when (eq? *iterm-configured* 'unknown)
        (set! *iterm-configured* (iterm-probe-configured?)))
      *iterm-configured*)

    (define (iterm-refresh-configured!)
      (set! *iterm-configured* (iterm-probe-configured?))
      *iterm-configured*)

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

    ;; The seam (ADR-0014). Default: the real run-shell-async, whose
    ;; (command callback) shape this parameter's value must match — a test
    ;; overrides it to capture the assembled script instead of quitting and
    ;; reconfiguring a real iTerm.
    (define current-iterm-provision-runner
      (make-parameter run-shell-async))

    ;; The provisioning action a configuration binds: confirm (async,
    ;; ADR-0014 — the dialog fires through the slim (modaliser dialogs)
    ;; library so the Scheme thread stays free while it's up), provision
    ;; (also async — the quit-then-poll-pgrep loop below is a
    ;; multi-second blocking window if run synchronously;
    ;; iterm-refresh-configured! moves into the callback so it only runs
    ;; once provisioning has actually finished), re-probe. Idempotent — if
    ;; iTerm is already configured (e.g. the key was pressed while the
    ;; row was hidden) it just syncs the cache and returns, no dialog.
    ;;
    ;; Pairing it with `configured?` as a 'hidden gate is what makes the
    ;; row retire itself — without a Modaliser reload, since the gate is
    ;; re-read on the next overlay open after this re-probes:
    ;;
    ;;   (key "C-I" "Configure iTerm" iterm:configure!
    ;;        'hidden iterm:configured?)
    (define (configure!)
      (if (iterm-probe-configured?)
        (iterm-refresh-configured!)
        (dialog-confirm iterm-configure-dialog-message
          (lambda (continue?)
            (when continue?
              ((current-iterm-provision-runner) iterm-provision-script
                (lambda (exit-code stdout stderr)
                  (iterm-refresh-configured!)))))
          'title "Configure iTerm" 'ok-label "Continue" 'icon "caution")))

    ;; A standalone "pick a digit to focus a pane" mode. The façade's
    ;; (terminal:focus-pane-by-digit) resolver names this tree as the
    ;; procedure-valued 'next target on a config's digit-jump binding.
    ;; on-enter
    ;; snapshots the pane layout (so iterm-panes-current-targets is
    ;; populated for focus-by-digit's lookup) and paints chips; on-leave
    ;; hides them. The single hidden key-range dispatches by digit and
    ;; exits the mode automatically (Terminal — no 'next — by default).
    (define (pane-digit-tree)
      (tree-root 'iterm-pane-digit
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

    ;; Build the <terminal-backend> record this module hands to
    ;; (modaliser terminal). Same procedures the iterm:focus-pane-*
    ;; etc. exports point at — registering doesn't duplicate
    ;; implementations, it just lets the façade dispatch to them when
    ;; iTerm is frontmost. The trailing capabilities alist is the host
    ;; glue inner tools consume generically through the façade
    ;; (library-fragments-k11) — today the canvas-frame probe behind
    ;; herdr's chip geometry.
    (define (iterm-terminal-backend)
      (make-terminal-backend
        ;; tool-name #f: iTerm2 is entirely AppleScript-driven — no CLI
        ;; tool binary to resolve.
        'iterm "iTerm2" 'host "com.googlecode.iterm2" #f
        detect-fg-command
        focused-pane-id
        focus-pane-left  focus-pane-right  focus-pane-up    focus-pane-down
        split-pane-left  split-pane-right  split-pane-up    split-pane-down
        move-pane-left   move-pane-right   move-pane-up     move-pane-down
        'iterm-pane-digit
        toggle-pane-zoom
        configured?
        (list (cons 'canvas-frame canvas-frame-probe))))

    ;; ─── Tab operations, continued ─────────────────────────────────
    ;;
    ;; The tab strip is vertical, so the direction-free naming: a screen
    ;; decides which of h/j/k/l reaches "previous" and which "next".
    (define (tab-focus-prev) (send-keystroke '(cmd shift) "["))      ; ⌘⇧[
    (define (tab-focus-next) (send-keystroke '(cmd shift) "]"))      ; ⌘⇧]
    (define (tab-move-prev)  (send-keystroke '(alt shift cmd) "["))  ; ⌥⇧⌘[
    (define (tab-move-next)  (send-keystroke '(alt shift cmd) "]"))  ; ⌥⇧⌘]

    ;; ─── The wiring fragment (ADR-0018 / ADR-0021) ─────────────────
    ;;
    ;; `wiring` returns a pure Fragment carrying iTerm's INTEGRATION and
    ;; nothing else —
    ;;
    ;;   (configuration (iterm:wiring) my-iterm-screen …)
    ;;
    ;; — the backend record (whose match-key is what makes a screen under
    ;; 'com.googlecode.iterm2 terminal-like, and whose 'canvas-frame
    ;; capability feeds inner tools' chip geometry) and the digit-jump
    ;; mode tree the record's focus-pane-by-digit slot names at fire
    ;; time. No key, no label: the screen is the configuration's, built
    ;; from the ops and blocks exported above.
    ;;
    ;; Each call builds fresh tree objects, so compose ONE call's value;
    ;; two calls' contributions under the same scope are a genuine merge
    ;; conflict, not a diamond.
    (define (wiring)
      (list
        (config:backend 'iterm (iterm-terminal-backend))
        (config:tree 'iterm-pane-digit (pane-digit-tree))))

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

    ;; Row index of the focused split among the snapshotted pane targets —
    ;; matched by the focused session's UUID (focused-pane-id). A thunk, so
    ;; list-cursor consults it only when the pane list first claims the cursor
    ;; (overlay open): the AppleScript probe runs once per open, not per
    ;; re-render. The on-render snapshot has already refreshed
    ;; iterm-panes-current-targets by the time block-json offers the cursor, so
    ;; the targets read here are current. #f when iTerm reports no focused
    ;; session or it isn't among the labelled panes (→ cursor seeds row 0).
    ;; See list-cursor-initial-focus-k25.
    (define (pane-focused-index)
      (let ((fid (focused-pane-id)))
        (and fid
             (let loop ((ts (iterm-panes-current-targets)) (i 0))
               (cond
                 ((null? ts) #f)
                 ((string=? (cdr (car ts)) fid) i)
                 (else (loop (cdr ts) (+ i 1))))))))

    ;; cursor-targets-fn rides only on a LIVE block (one with an on-render-fn
    ;; that refreshes iterm-panes-current-targets every render — the 'chips?
    ;; path); a static no-chips block never refreshes its targets, so the
    ;; selection cursor must not attach to it. Same gate as window:list-block.
    ;; A live block also carries cursor-initial-index-fn so the cursor opens on
    ;; the focused split (list-cursor-initial-focus-k25).
    (define (pane-list-block . opts)
      (let* ((base  (apply make-iterm-panes-block opts))
             (live? (and (assoc 'on-render-fn base) #t)))
        (append base
                (if live?
                  (list (cons 'cursor-targets-fn iterm-panes-current-targets)
                        (cons 'cursor-initial-index-fn pane-focused-index))
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
                  (list (cons 'cursor-targets-fn iterm-tabs-current-targets)
                        ;; Open the cursor on the current tab (the snapshot's
                        ;; 'current row); list-cursor-initial-focus-k25.
                        (cons 'cursor-initial-index-fn iterm-tabs-focused-index))
                  '())
                (list (cons 'block-children (list (tab-range)))))))))

