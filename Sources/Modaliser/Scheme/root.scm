;; root.scm — Modaliser application entry point
;;
;; This is the only file loaded by Swift. It bootstraps the entire
;; application by including modules, then setting up the app lifecycle.
;;
;; (include) is an R7RS special form that splices file contents into
;; the current compilation scope — definitions are global.

;; ─── Load modules ─────────────────────────────────────────────────

(include "lib/util.scm")
(include "lib/terminal.scm")
(include "core/keymap.scm")
(include "ui/dom.scm")
(include "ui/css.scm")
(include "core/state-machine.scm")
(include "core/event-dispatch.scm")
(include "ui/overlay.scm")
(include "ui/chooser.scm")
(include "lib/dsl.scm")
(include "lib/web-search.scm")

;; ─── App setup ────────────────────────────────────────────────────

(set-activation-policy! 'accessory)
(request-accessibility!)
(request-screen-recording!)

;; ─── Config path ─────────────────────────────────────────────────

(define user-config-dir
  (string-append (get-environment-variable "HOME")
                 "/.config/modaliser"))

(define user-config-path
  (string-append user-config-dir "/config.scm"))

(define default-config-path
  (string-append *scheme-directory* "/default-config.scm"))

(define (open-settings!)
  (run-shell (string-append "/usr/bin/open \"" user-config-path "\"")))

;; Copy file by streaming characters; preserves contents exactly.
(define (copy-file! src dst)
  (let ((in (open-input-file src))
        (out (open-output-file dst)))
    (let loop ((c (read-char in)))
      (if (eof-object? c)
        (begin
          (close-input-port in)
          (close-output-port out))
        (begin
          (write-char c out)
          (loop (read-char in)))))))

;; Seed user config from the bundled default on first run.
(unless (file-exists? user-config-path)
  (run-shell (string-append "/bin/mkdir -p \"" user-config-dir "\""))
  (when (file-exists? default-config-path)
    (copy-file! default-config-path user-config-path)
    (log "Modaliser: seeded default config at " user-config-path)))

;; ─── Status bar ───────────────────────────────────────────────────

(create-status-item! ":icon"
  (list
    (list (cons 'title "Settings…") (cons 'action open-settings!) (cons 'key-equivalent ","))
    'separator
    (list (cons 'title "Relaunch") (cons 'action relaunch!) (cons 'key-equivalent "r"))
    'separator
    (list (cons 'title "Quit Modaliser") (cons 'action quit!) (cons 'key-equivalent "q"))))

;; ─── Start keyboard capture ───────────────────────────────────────

(start-keyboard-capture!)

(when (file-exists? user-config-path)
  (include "~/.config/modaliser/config.scm"))

(log "Modaliser Scheme runtime initialized")
