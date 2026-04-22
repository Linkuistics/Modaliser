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

;; ─── Neovim RPC discovery ─────────────────────────────────────────────
;;
;; Every running nvim binds a Unix socket (its msgpack-RPC server). macOS
;; lsof only emits the socket path when scoped to a specific pid — globally
;; it shows peer-pointer aliases — so we pgrep nvim and scan each process.
;;
;; Focus disambiguation (multiple nvim instances, or nvim nested inside a
;; multiplexer): each nvim exposes its own belief about terminal focus via
;; the user-maintained global g:modaliser_focused, updated by FocusGained /
;; FocusLost autocmds. Modern terminals (iTerm2, zellij, tmux) forward the
;; xterm focus-reporting escapes to their active pane, so exactly one nvim
;; across the system should report 1 at any given moment.

;; PATH prefix for subprocesses that need Homebrew-installed or /usr/sbin
;; tools. GUI-launched Modaliser inherits a minimal path_helper PATH that
;; excludes both /opt/homebrew/bin (Apple Silicon), /usr/local/bin (Intel)
;; — though the latter is sometimes present — and /usr/sbin (where lsof
;; lives). Prepending here is deterministic and doesn't depend on the
;; user's interactive shell config. Update when adding tools from other
;; locations.
(define modaliser-tool-path
  "/opt/homebrew/bin:/usr/local/bin:/usr/sbin")

;; Return a list of Unix-socket paths bound by running nvim processes.
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

;; True if the nvim at SOCK reports g:modaliser_focused == 1. The `get`
;; form treats a missing variable as 0, so unconfigured nvim instances
;; simply register as not-focused rather than producing a Vim error.
;;
;; Critical: redirect stdin from /dev/null. When stdin is a TTY, the nvim
;; client decides to attach a UI, emits its alt-screen init + teardown
;; escapes (including \E[?1004l which globally disables terminal focus
;; reporting), and writes the expression result to stderr instead of
;; stdout. That single leaked escape would break every subsequent focus
;; probe silently. Closing stdin flips isatty() to false and nvim runs as
;; a proper non-UI RPC client.
(define (nvim-server-focused? sock)
  (let ((out (run-shell
               (string-append
                 "export PATH=" modaliser-tool-path ":$PATH; "
                 "nvim --server " sock
                 " --remote-expr 'get(g:, \"modaliser_focused\", 0)'"
                 " </dev/null 2>/dev/null"))))
    (string=? (string-trim out) "1")))

;; Return the socket of the focused nvim (direct, or via a multiplexer), or
;; #f if no running nvim claims focus. O(n) RPC calls in the worst case,
;; but typical n is 1–2.
(define (focused-nvim-socket)
  (let loop ((socks (list-nvim-sockets)))
    (cond
      ((null? socks) #f)
      ((nvim-server-focused? (car socks)) (car socks))
      (else (loop (cdr socks))))))

;; Helpers for bindings to act on the focused nvim without refetching the
;; socket each time at the call site.
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
      #f)))
