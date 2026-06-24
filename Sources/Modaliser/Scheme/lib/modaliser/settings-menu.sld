;; (modaliser settings-menu) — Settings menu group for the global tree.
;;
;; Builds a leader-accessible group whose entries operate on the user's
;; config file itself: open it in an editor, or relaunch Modaliser to
;; pick up edits. Idiomatic placement is the "," key of the global tree.
;;
;; Quick start (prefix-style import — recommended):
;;   (import (prefix (modaliser settings-menu) settings:))
;;   (screen 'global
;;     (panel "General"
;;       (settings:actions))
;;     …)
;;
;; Options (all keyword-style, all optional):
;;   'key            — leader key for the group (default ",").
;;   'label          — overlay label (default "Settings").
;;   'config-dir     — absolute path to the config directory
;;                     (default "$HOME/.config/modaliser"). The Edit
;;                     binding opens the directory (not a single file)
;;                     so users land in a tree view and pick what to
;;                     edit — config.scm, theme.css, their own .sld
;;                     libraries.
;;   'editor         — application name for the Edit binding (default
;;                     "Zed"). Falls back to the OS default opener if
;;                     the editor is unavailable.
;;   'extra-bindings — list of additional DSL nodes appended after Reload.
;;
;; Matches the shape of (modaliser window-actions) (actions): a single
;; factory returning a composable group node.

(define-library (modaliser settings-menu)
  (export actions)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (modaliser lifecycle))
  (begin

    (define default-config-dir
      "$HOME/.config/modaliser")

    (define (actions . opts)
      (let* ((alist       (apply props->alist opts))
             (group-key   (alist-ref alist 'key ","))
             (group-label (alist-ref alist 'label "Settings"))
             (config-dir  (alist-ref alist 'config-dir default-config-dir))
             (editor      (alist-ref alist 'editor "Zed"))
             (extra       (alist-ref alist 'extra-bindings '()))
             ;; Open the *directory*, not a single file — Zed's project
             ;; view lets users see and pick across config.scm,
             ;; theme.css, and any user-authored .sld libraries side by
             ;; side. Falls back to the OS default opener (Finder) if
             ;; the editor isn't installed.
             (open-cmd    (string-append
                            "/usr/bin/open -a " editor " \"" config-dir "\""
                            " || /usr/bin/open \"" config-dir "\"")))
        (apply group group-key group-label
          (append
            (list
              (key "e" "Edit"   (lambda () (run-shell open-cmd)))
              (key "r" "Reload" (lambda () (relaunch!))))
            extra))))))
