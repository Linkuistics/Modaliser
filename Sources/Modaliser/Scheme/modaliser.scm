;; modaliser.scm — Root Scheme program
;;
;; This is loaded last by SchemeEngine (after all modules).
;; It sets up the application: activation policy, permissions,
;; status bar, starts keyboard capture, and loads user configuration.
;;
;; Module load order (handled by Swift):
;;   lib/util.scm → core/keymap.scm → core/state-machine.scm →
;;   core/event-dispatch.scm → lib/dsl.scm → modaliser.scm

;; ─── App setup ──────────────────────────────────────────────────

(set-activation-policy! 'accessory)
(request-accessibility!)
(request-screen-recording!)

;; ─── Status bar ─────────────────────────────────────────────────

(define (reload-config)
  (log "Config reload not yet implemented in Scheme"))

(create-status-item! ":icon"
  (list
    (list (cons 'title "Reload Config") (cons 'action reload-config) (cons 'key-equivalent "r"))
    'separator
    (list (cons 'title "Relaunch") (cons 'action relaunch!))
    (list (cons 'title "Quit Modaliser") (cons 'action quit!) (cons 'key-equivalent "q"))))

;; ─── Start keyboard capture ─────────────────────────────────────

(start-keyboard-capture!)

;; ─── Load user configuration ────────────────────────────────────

(define user-config-path
  (string-append (get-environment-variable "HOME")
                 "/.config/modaliser/config.scm"))

(log "Modaliser Scheme runtime initialized")
