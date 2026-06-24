;; (modaliser launchers) — Application and file launcher selectors.
;;
;; Reusable selector factories for the two most common leader entries:
;;   • find-application — Spotlight-style app finder with MRU memory
;;     and primary/secondary actions (open, reveal in Finder, copy path,
;;     copy bundle ID).
;;   • find-file — file picker rooted at the user's home, with
;;     primary/secondary actions and an "Open in editor" action.
;;
;; Quick start (prefix-style import — recommended; the bare exports
;; are short and collide easily with peer libraries):
;;   (import (prefix (modaliser launchers) launcher:))
;;   (screen 'global
;;     (panel "Search"
;;       (key "a" "Find Application" (launcher:find-application))
;;       (key "f" "Find File"        (launcher:find-file)))
;;     …)
;;
;; Both factories accept keyword-style options with defaults that match
;; the bundled seed. Same shape as (modaliser window-actions): a single
;; factory returning a composable node, no side effects until placed
;; inside a screen panel.

(define-library (modaliser launchers)
  (export find-application
          find-file)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser app)
          (modaliser pasteboard)
          (modaliser shell))
  (begin

    ;; ─── Applications selector ────────────────────────────────────
    ;;
    ;; Returns an undecorated selector node. Bind it via the call site:
    ;;   (key "a" "Find Application" (launcher:find-application))
    ;;
    ;; Options:
    ;;   'prompt        — chooser prompt (default "Find app…")
    ;;   'remember      — MRU bucket name; #f disables MRU (default "apps")
    ;;   'extra-actions — list of (action …) nodes appended to the defaults

    (define (find-application . opts)
      (let* ((alist    (apply props->alist opts))
             (prompt   (alist-ref alist 'prompt "Find app…"))
             (remember (alist-ref alist 'remember "apps"))
             (extra    (alist-ref alist 'extra-actions '()))
             (defaults
               (list
                 (action "Open"
                   'description "Launch or focus"
                   'key 'primary
                   'run (lambda (c) (activate-app c)))
                 (action "Show in Finder"
                   'description "Reveal in Finder"
                   'key 'secondary
                   'run (lambda (c) (reveal-in-finder c)))
                 (action "Copy Path"
                   'description "Copy full path to clipboard"
                   'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
                 (action "Copy Bundle ID"
                   'description "Copy app bundle identifier"
                   'run (lambda (c) (set-clipboard! (cdr (assoc 'bundleId c)))))))
             (actions (append defaults extra)))
        (selector
          'prompt prompt
          'source find-installed-apps
          'on-select activate-app
          'remember remember
          'id-field "bundleId"
          'actions actions)))

    ;; ─── Files selector ───────────────────────────────────────────
    ;;
    ;; Returns an undecorated selector node. Bind it via the call site:
    ;;   (key "f" "Find File" (launcher:find-file))
    ;;
    ;; Options:
    ;;   'prompt        — chooser prompt (default "File…")
    ;;   'file-roots    — list of roots to search (default '("~"))
    ;;   'editor        — app name for the "Open in editor" action
    ;;                    (default "Zed")
    ;;   'extra-actions — list of (action …) nodes appended to the defaults

    (define (find-file . opts)
      (let* ((alist      (apply props->alist opts))
             (prompt     (alist-ref alist 'prompt "File…"))
             (file-roots (alist-ref alist 'file-roots (list "~")))
             (editor     (alist-ref alist 'editor "Zed"))
             (extra      (alist-ref alist 'extra-actions '()))
             (open-path
               (lambda (c)
                 (run-shell
                   (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\""))))
             (defaults
               (list
                 (action "Open"
                   'description "Open with default app"
                   'key 'primary
                   'run open-path)
                 (action "Show in Finder"
                   'description "Reveal in Finder"
                   'key 'secondary
                   'run (lambda (c) (reveal-in-finder c)))
                 (action "Copy Path"
                   'description "Copy full path to clipboard"
                   'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
                 (action (string-append "Open in " editor)
                   'description (string-append "Open file in " editor)
                   'run (lambda (c) (open-with editor (cdr (assoc 'path c)))))))
             (actions (append defaults extra)))
        (selector
          'prompt prompt
          'file-roots file-roots
          'on-select open-path
          'actions actions)))))
