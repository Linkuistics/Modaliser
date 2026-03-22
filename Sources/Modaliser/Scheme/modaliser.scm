;; modaliser.scm — Root Scheme program
;;
;; This is the entry point loaded by Swift's SchemeEngine.
;; It sets up the application: activation policy, permissions,
;; status bar, loads modules, starts keyboard capture, and
;; loads user configuration.

;; ─── Load modules ───────────────────────────────────────────────

(load "lib/util.scm")
(load "core/keymap.scm")
(load "core/state-machine.scm")
(load "core/event-dispatch.scm")
(load "lib/dsl.scm")

;; ─── App setup ──────────────────────────────────────────────────

(set-activation-policy! 'accessory)
(request-accessibility!)
(request-screen-recording!)

;; ─── Status bar ─────────────────────────────────────────────────

(define (reload-config)
  (log "Config reload not yet implemented in Scheme"))

(create-status-item! "⌨"
  (list
    (list '(title . "Reload Config") '(action . reload-config) '(key-equivalent . "r"))
    'separator
    (list '(title . "Relaunch") '(action . relaunch!))
    (list '(title . "Quit Modaliser") '(action . quit!) '(key-equivalent . "q"))))

;; ─── Start keyboard capture ─────────────────────────────────────

(start-keyboard-capture!)

;; ─── Load user configuration ────────────────────────────────────

(define (load-user-config)
  (let ((config-path (string-append
                       (get-environment-variable "HOME")
                       "/.config/modaliser/config.scm")))
    (when (file-exists? config-path)
      (load config-path)
      (log "Loaded user config: " config-path))))

(load-user-config)

(log "Modaliser Scheme runtime initialized")
