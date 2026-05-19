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
        (modaliser dsl)
        (modaliser dom)
        (modaliser web-search)
        (modaliser theming))

;; ─── Plain .scm modules (Phase D will library-ize the remaining ones) ────────

(include "ui/css.scm")
(include "ui/overlay.scm")
(include "ui/chooser.scm")

;; chooser-push-results lives in the flat-included ui/chooser.scm. Wire it
;; into (modaliser web-search) now that both have loaded — the library
;; held a no-op placeholder until this point.
(set-chooser-push! chooser-push-results)

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

;; User-authored CSS lives in a real .css file so editors give syntax
;; highlighting and linting for free. Slurped into overlay-custom-css
;; below after the user config has loaded.
(define user-overlay-css-path
  (string-append user-config-dir "/overlay.css"))

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

;; Slurp ~/.config/modaliser/overlay.css if present. Runs after the
;; user config so a user that wants to compose CSS in Scheme can still
;; do so by writing to overlay-custom-css before this point — but the
;; canonical authoring surface is the .css file.
(when (file-exists? user-overlay-css-path)
  (set! overlay-custom-css (read-file-text user-overlay-css-path)))

;; Wire the (modaliser theming) probe to the overlay's CSS stack and
;; kick it off. The probe library can't see top-level overlay-* vars
;; from inside its define-library scope, so we hand it a closure that
;; resolves them at call time — same deferred-resolution pattern
;; (modaliser overlay-assets) uses for its file resolver. Must run
;; AFTER the overlay.css slurp so user overrides feed the probe.
(theming-set-css-source! overlay-full-css)
(run-chip-theme-probe!)

(log "Modaliser Scheme runtime initialized")
