;; root.scm — Modaliser application entry point
;;
;; This is the only file loaded by Swift. It bootstraps the entire
;; application by importing the (modaliser …) libraries, then
;; including the .scm modules that haven't been library-ized yet.
;; The library exports cascade into the top-level environment for the
;; included files and the user's config.scm to see. Phases C/D will
;; continue carving the included files into libraries.

;; ─── Modaliser libraries ──────────────────────────────────────────

(import (modaliser util)
        (modaliser keymap)
        (modaliser state-machine)
        (modaliser event-dispatch)
        (modaliser dsl))

;; ─── Plain .scm modules (Phase D will library-ize the remaining ones) ────────

(include "ui/dom.scm")
(include "ui/css.scm")
(include "ui/overlay.scm")
(include "ui/chooser.scm")
(include "lib/web-search.scm")

;; ─── App setup ────────────────────────────────────────────────────

;; Block until every required permission is granted. If any is missing on
;; first run (or after a revoke), this presents the onboarding window and
;; either relaunches the app once the user grants them, or terminates if
;; the user closes the window. By the line below this call, all listed
;; permissions are guaranteed to be granted.
(ensure-permissions! '(accessibility screen-recording))

(set-activation-policy! 'accessory)

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
