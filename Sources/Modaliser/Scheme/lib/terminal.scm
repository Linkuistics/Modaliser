;; lib/terminal.scm — Probe what's running in the focused terminal pane
;;
;; The kernel truth for "what is receiving keystrokes in the terminal" is
;; the foreground process group of the controlling tty. `ps -o tpgid` gives
;; that; the row whose pgid equals the tty's tpgid is the foreground process.
;; Full-screen TUIs (zellij, tmux, vim, less, htop, lazygit) all show up this
;; way, so a single probe answers "is X running in the focused pane" for any X.

;; Return the pty path of iTerm2's focused session (e.g. "/dev/ttys003"),
;; or #f if iTerm2 is not running or the query fails.
;; The `is running` guard prevents the naked `tell application "iTerm2"` from
;; auto-launching iTerm via Launch Services.
(define (focused-iterm-tty)
  (let* ((script
           (string-append
             "if application \"iTerm2\" is running then "
             "tell application \"iTerm2\" to "
             "tell current session of current window to get tty"))
         (out (run-shell
                (string-append "osascript -e '" script "' 2>/dev/null")))
         (trimmed (string-trim out)))
    (if (string=? trimmed "") #f trimmed)))

;; Given a pty path like "/dev/ttys003", return the command string of the
;; foreground process on that tty (the one currently receiving keystrokes),
;; or #f if none can be identified.
;;
;; `ps -t <name>` expects the short name without the /dev/ prefix on macOS.
;; We compare pgid to tpgid to find the foreground process group leader; the
;; awk reassembles the command column (it can contain spaces).
(define (tty-foreground-command tty)
  (let* ((slash (string-split tty "/"))
         (name  (if (null? slash) tty (list-ref slash (- (length slash) 1))))
         (cmd   (string-append
                  "ps -t " name " -o pgid=,tpgid=,command= | "
                  "awk '$1==$2 { for (i=3; i<=NF; i++) "
                  "printf \"%s%s\", $i, (i==NF?\"\":\" \"); exit }'"))
         (out   (run-shell cmd))
         (trimmed (string-trim out)))
    (if (string=? trimmed "") #f trimmed)))

;; Return the command string of the foreground process in the focused terminal
;; pane, or #f if we can't determine it. Currently iTerm2-only; extend by
;; adding more terminals to the `cond` below as they come into use.
(define (focused-terminal-foreground-command)
  (cond
    ((focused-iterm-tty) => tty-foreground-command)
    (else #f)))
