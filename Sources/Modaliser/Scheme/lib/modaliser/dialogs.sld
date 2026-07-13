;; (modaliser dialogs) — slim async AppleScript dialog helpers.
;;
;; The shared home for Modaliser-raised confirm/info dialogs (ADR-0014): the
;; iTerm / Kitty / Alacritty backends' configure-entry confirmations today,
;; any future dialog site tomorrow. Two invariants:
;;
;;   - Fires only through `current-dialog-runner` (default the real
;;     `run-shell-async`) — never a synchronous `run-shell`. A leader press
;;     while the dialog is up must not stall the keyboard tap.
;;   - No capture handling. A dialog-raising command is an ordinary
;;     Terminal leaf (no `'next`); dispatch has already released modal
;;     capture before the action runs (ADR-0015, CONTEXT.md "Dialog
;;     command"). This library never calls `modal-exit` and does not
;;     import `(modaliser state-machine)`.
;;
;; Quick start:
;;
;;   (import (modaliser dialogs))
;;   (dialog-confirm "Quit and relaunch iTerm?"
;;     (lambda (continue?) (when continue? ...))
;;     'title "Configure iTerm" 'ok-label "Continue" 'icon "caution")
;;
;; `current-dialog-runner` is the single test seam: a
;; `(lambda (shell-command callback) ...)` matching `run-shell-async`'s own
;; shape exactly, so a test can capture the assembled shell command instead
;; of spawning osascript (feedback_no_live_env_mutation_in_tests).

(define-library (modaliser dialogs)
  (export dialog-confirm
          dialog-info
          current-dialog-runner
          sq-escape)
  (import (scheme base)
          (modaliser util)
          (modaliser shell))
  (begin

    ;; POSIX single-quote escaping: each ' becomes the '\'' idiom — close
    ;; the quote, emit an escaped literal ', reopen — so an arbitrary string
    ;; (here, the whole AppleScript source) is safe to interpolate inside a
    ;; single-quoted /bin/zsh word. Exported: the one canonical
    ;; implementation, so callers that need it for their own shell-quoting
    ;; (herdr.sld's branch-name interpolation) share this instead of keeping
    ;; a local copy.
    (define (sq-escape s)
      (escape-string s (list (cons #\' "'\\''"))))

    ;; AppleScript double-quoted-literal escaping: backslash and ". Applied
    ;; to any text embedded inside a `display dialog "..."` argument, before
    ;; the whole script is sq-escape'd for the shell.
    (define (as-escape s)
      (escape-string s (list (cons #\\ "\\\\") (cons #\" "\\\""))))

    ;; The seam (ADR-0014). Default: the real run-shell-async, whose
    ;; (command callback ['timeout seconds]) shape this parameter's value
    ;; must match — a test overrides it to capture the assembled command
    ;; instead of firing osascript.
    (define current-dialog-runner
      (make-parameter run-shell-async))

    ;; Fire SCRIPT (an AppleScript command string) through the seam,
    ;; wrapped as `osascript -e '<script>'`. CALLBACK receives
    ;; (exit-code stdout stderr), the same shape run-shell-async passes.
    (define (run-dialog script callback)
      ((current-dialog-runner)
       (string-append "osascript -e '" (sq-escape script) "' 2>/dev/null")
       callback))

    ;; Show a Cancel/affirmative-button confirm dialog; K receives #t iff
    ;; the affirmative button was chosen. `cancel button` makes a Cancel
    ;; click (or Escape) raise AppleScript error -128 — swallowed by
    ;; 2>/dev/null — so a decline and an osascript-level failure both read
    ;; as empty stdout => #f. Fail-safe: a broken dialog can only under-
    ;; report a confirm, never over-report one.
    ;;
    ;; Options: 'title STRING (dialog title bar; omitted = the invoking
    ;; process's name), 'ok-label STRING (default "OK"), 'icon STRING (an
    ;; AppleScript icon name/number, e.g. "caution"; omitted = none).
    (define (dialog-confirm message k . opts)
      (let* ((alist    (apply props->alist opts))
             (title    (alist-ref alist 'title #f))
             (ok-label (alist-ref alist 'ok-label "OK"))
             (icon     (alist-ref alist 'icon #f)))
        (run-dialog
          (string-append
            "button returned of (display dialog \"" (as-escape message) "\" "
            (if title (string-append "with title \"" (as-escape title) "\" ") "")
            "buttons {\"Cancel\", \"" (as-escape ok-label) "\"} "
            "default button \"Cancel\" cancel button \"Cancel\""
            (if icon (string-append " with icon " icon) "")
            ")")
          (lambda (exit-code stdout stderr)
            (k (string=? (string-trim stdout) ok-label))))))

    ;; Show a single-button info alert. OPT, if given, is a 0-arg procedure
    ;; called once the dialog is dismissed — there is only one button, so
    ;; no result to pass.
    (define (dialog-info message . opt)
      (run-dialog
        (string-append
          "display dialog \"" (as-escape message) "\" "
          "buttons {\"OK\"} default button \"OK\"")
        (lambda (exit-code stdout stderr)
          (when (and (pair? opt) (procedure? (car opt)))
            ((car opt))))))))
