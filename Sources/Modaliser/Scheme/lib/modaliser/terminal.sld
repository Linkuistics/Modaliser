;; (modaliser terminal) — Probe what's running in the focused terminal pane.
;;
;; The kernel truth for "what is receiving keystrokes in the terminal" is
;; the foreground process group of the controlling tty. `ps -o tpgid` gives
;; that; the row whose pgid equals the tty's tpgid is the foreground process.
;; Full-screen TUIs (zellij, tmux, vim, less, htop, lazygit) all show up this
;; way, so a single probe answers "is X running in the focused pane" for any X.

(define-library (modaliser terminal)
  (export focused-iterm-tty
          tty-foreground-command
          focused-terminal-foreground-command
          modaliser-tool-path
          list-nvim-sockets
          nvim-server-focused?
          focused-nvim-socket
          nvim-remote-send
          nvim-remote-expr)
  (import (scheme base)
          (modaliser shell)
          (modaliser util))
  (begin

    ;; Return the pty path of iTerm2's focused session (e.g. "/dev/ttys003"),
    ;; or #f if iTerm2 is not running or the query fails.
    ;; The `is running` guard prevents the naked `tell application "iTerm2"`
    ;; from auto-launching iTerm via Launch Services.
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

    ;; Given a pty path like "/dev/ttys003", return the command string of
    ;; the foreground process on that tty, or #f if none.
    ;; `ps -t <name>` expects the short name without /dev/.
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

    ;; Command string of the foreground process in the focused terminal pane,
    ;; or #f. Currently iTerm2-only.
    (define (focused-terminal-foreground-command)
      (cond
        ((focused-iterm-tty) => tty-foreground-command)
        (else #f)))

    ;; PATH prefix for subprocesses that need Homebrew/usr/sbin tools.
    ;; GUI-launched Modaliser inherits a minimal path_helper PATH.
    (define modaliser-tool-path
      "/opt/homebrew/bin:/usr/local/bin:/usr/sbin")

    ;; Unix-socket paths bound by running nvim processes.
    (define (list-nvim-sockets)
      (let ((out (run-shell
                   (string-append
                     "export PATH=" modaliser-tool-path ":$PATH; "
                     "for pid in $(pgrep -x nvim); do "
                     "  lsof -p $pid -a -U -Fn 2>/dev/null "
                     "  | awk '/^n\\// {print substr($0,2)}'; "
                     "done | sort -u"))))
        (let loop ((lines (string-split out "\n")) (acc '()))
          (cond
            ((null? lines) (reverse acc))
            (else
              (let ((s (string-trim (car lines))))
                (loop (cdr lines)
                      (if (string=? s "") acc (cons s acc)))))))))

    ;; True if the nvim at SOCK reports g:modaliser_focused == 1.
    (define (nvim-server-focused? sock)
      (let ((out (run-shell
                   (string-append
                     "export PATH=" modaliser-tool-path ":$PATH; "
                     "nvim --server " sock
                     " --remote-expr 'get(g:, \"modaliser_focused\", 0)'"
                     " </dev/null 2>/dev/null"))))
        (string=? (string-trim out) "1")))

    ;; Socket of the focused nvim, or #f.
    (define (focused-nvim-socket)
      (let loop ((socks (list-nvim-sockets)))
        (cond
          ((null? socks) #f)
          ((nvim-server-focused? (car socks)) (car socks))
          (else (loop (cdr socks))))))

    (define (nvim-remote-send keys)
      (let ((sock (focused-nvim-socket)))
        (when sock
          (run-shell
            (string-append "export PATH=" modaliser-tool-path ":$PATH; "
                           "nvim --server " sock
                           " --remote-send '" keys "'"
                           " </dev/null 2>/dev/null")))))

    (define (nvim-remote-expr expr)
      (let ((sock (focused-nvim-socket)))
        (if sock
          (string-trim
            (run-shell
              (string-append "export PATH=" modaliser-tool-path ":$PATH; "
                             "nvim --server " sock
                             " --remote-expr '" expr "'"
                             " </dev/null 2>/dev/null")))
          #f)))))
