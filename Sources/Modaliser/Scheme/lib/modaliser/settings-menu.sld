;; (modaliser settings-menu) — the one operation a Settings menu needs:
;; open the user's Modaliser config directory in an editor.
;;
;; This is the FACILITY half (ADR-0021). The Settings menu itself — which
;; key it hangs off, what the rows are called, whether Reload sits beside
;; Edit — is a DECISION, so it lives in the configuration:
;;
;;   (import (prefix (modaliser settings-menu) settings:)
;;           (modaliser lifecycle))            ; relaunch!
;;
;;   (group "," "Settings"
;;     (key "e" "Edit"   (λ () (settings:open-config-dir! 'editor "Zed")))
;;     (key "r" "Reload" relaunch!))
;;
;; Everything that used to be an option of a library-owned `actions`
;; constructor — the group key, its label, extra rows — is ordinary
;; Scheme above. What remains here is the part a user should not have to
;; get right: where Modaliser's config lives, and how to open a
;; directory in a named editor without stranding the user when that
;; editor is not installed.

(define-library (modaliser settings-menu)
  (export open-config-dir!)
  (import (scheme base)
          (modaliser util)
          (modaliser shell))
  (begin

    ;; Modaliser's config root (ADR-0019). A fact about Modaliser, not a
    ;; preference — hence a default rather than a required argument.
    (define default-config-dir
      "$HOME/.config/modaliser")

    (define (shell-quote s)
      (string-append "\"" s "\""))

    ;; (open-config-dir! [keyword value]…) — opens the config DIRECTORY,
    ;; not a single file, so the editor's project view shows config.scm,
    ;; theme.css and any user-authored .sld libraries side by side.
    ;;
    ;;   'config-dir  absolute path (default "$HOME/.config/modaliser")
    ;;   'editor      application name; omitted → the OS default handler
    ;;
    ;; With an editor named, an `|| open` fallback catches the case where
    ;; it is not installed, so the user still lands somewhere useful
    ;; rather than nowhere. No editor is named here on purpose: which
    ;; editor to open is preference, and this library holds none.
    (define (open-config-dir! . opts)
      (let* ((alist      (apply props->alist opts))
             (config-dir (alist-ref alist 'config-dir default-config-dir))
             (editor     (alist-ref alist 'editor #f))
             (dir        (shell-quote config-dir)))
        (run-shell
          (if editor
              (string-append "/usr/bin/open -a " (shell-quote editor) " " dir
                             " || /usr/bin/open " dir)
              (string-append "/usr/bin/open " dir)))))))
