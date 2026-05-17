;; (modaliser settings-menu) — Settings menu group for the global tree.
;;
;; Builds a leader-accessible group whose entries operate on the user's
;; config file itself: open it in an editor, or relaunch Modaliser to
;; pick up edits. Idiomatic placement is the "," key of the global tree.
;;
;; Quick start:
;;   (import (modaliser settings-menu))
;;   (define-tree 'global
;;     (settings-actions)
;;     …)
;;
;; Options (all keyword-style, all optional):
;;   'key            — leader key for the group (default ",").
;;   'label          — overlay label (default "Settings").
;;   'config-path    — absolute path to the config file
;;                     (default "$HOME/.config/modaliser/config.scm").
;;   'editor         — application name for the Edit binding (default
;;                     "Zed"). Falls back to the OS default opener if the
;;                     editor is unavailable, matching the shell snippet
;;                     in the seed.
;;   'extra-bindings — list of additional DSL nodes appended after Reload.
;;
;; Matches the shape of (modaliser window-actions) (window-actions):
;; a single factory returning a composable group node.

(define-library (modaliser settings-menu)
  (export settings-actions)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (modaliser lifecycle))
  (begin

    (define default-config-path
      "$HOME/.config/modaliser/config.scm")

    (define (settings-actions . opts)
      (let* ((alist       (apply props->alist opts))
             (group-key   (alist-ref alist 'key ","))
             (group-label (alist-ref alist 'label "Settings"))
             (config-path (alist-ref alist 'config-path default-config-path))
             (editor      (alist-ref alist 'editor "Zed"))
             (extra       (alist-ref alist 'extra-bindings '()))
             (open-cmd    (string-append
                            "/usr/bin/open -a " editor " \"" config-path "\""
                            " || /usr/bin/open \"" config-path "\"")))
        (apply group group-key group-label
          (append
            (list
              (key "e" "Edit"   (lambda () (run-shell open-cmd)))
              (key "r" "Reload" (lambda () (relaunch!))))
            extra))))))
