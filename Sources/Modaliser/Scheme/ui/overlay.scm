;; ui/overlay.scm — Which-key overlay using WebView
;;
;; Manages a non-activating floating panel that shows available
;; keybindings at the current position in the command tree.
;;
;; Depends on: ui/dom.scm, ui/css.scm, (modaliser webview)
;;
;; API:
;;   (show-overlay node path)   — create WebView if needed, render and display
;;   (update-overlay node path) — re-render content in existing WebView
;;   (hide-overlay)             — close WebView
;;   (render-overlay-html node path) — pure: returns HTML document string

;; ─── Overlay State ────────────────────────────────────────────

(define overlay-webview-id "modaliser-overlay")
(define overlay-open? #f)
(define overlay-custom-css "")

;; ─── CSS Theming ─────────────────────────────────────────

;; (set-overlay-css! css-string) — store custom CSS to inject after base.css.
;; Users call this in their config to override theme variables or add rules.
(define (set-overlay-css! css)
  (set! overlay-custom-css css))

;; ─── CSS Loading ──────────────────────────────────────────────

;; Load base.css once and cache it.
;; *scheme-directory* is set by SchemeEngine at init time.
(define overlay-base-css
  (read-file-text (string-append *scheme-directory* "/base.css")))

;; ─── JS Loading ─────────────────────────────────────────────────

;; Load overlay.js for incremental DOM updates (Display PostScript pattern).
(define overlay-js
  (read-file-text (string-append *scheme-directory* "/ui/overlay.js")))

;; ─── Overlay Panel Configuration ──────────────────────────────

(define overlay-panel-width 340)
(define overlay-panel-height 400)

;; ─── Rendering (Pure Functions) ───────────────────────────────

;; Build the breadcrumb header string from a navigation path.
;; path: list of key strings, e.g. '("w" "m")
;; root-label: label of the root tree node
(define (render-breadcrumb root-label path)
  (if (null? path)
    (header '((class . "overlay-header"))
      (span '((class . "breadcrumb")) root-label))
    (let* ((segments (cons root-label path))
           (sep (html->string (span '((class . "breadcrumb-sep")) ">"))))
      (header '((class . "overlay-header"))
        (make-raw-html
          (let loop ((segs segments) (result ""))
            (if (null? segs)
              result
              (loop (cdr segs)
                    (string-append result
                      (if (string=? result "") "" sep)
                      (html-escape (car segs)))))))))))

;; Render an entry for a single child node.
(define (render-entry child)
  (let* ((k (node-key child))
         (label (node-label child))
         (is-group (group? child))
         (display-key (if (equal? k " ") "\x2423;" k))
         (display-label (if is-group
                          (string-append label " \x2026;")
                          label))
         (label-class (if is-group "entry-label group-label" "entry-label")))
    (li '((class . "overlay-entry"))
      (span '((class . "entry-key")) display-key)
      (span '((class . "entry-arrow")) "\x2192;")
      (span (list (cons 'class label-class)) display-label))))

;; Render the full overlay body: header + entry list
(define (render-overlay-body node path)
  (let* ((root-label (node-label node))
         (current (if (null? path)
                    node
                    (navigate-to-path node path)))
         (children (if current (node-children current) '()))
         ;; Sort children by key
         (sorted (sort-children children)))
    (div '((class . "overlay"))
      (render-breadcrumb root-label path)
      (apply ul (cons '((class . "overlay-entries"))
                      (map render-entry sorted))))))

;; Sort children alphabetically by key (insertion sort)
(define (sort-children children)
  (define (insert item sorted)
    (cond
      ((null? sorted) (list item))
      ((string<? (node-key item) (node-key (car sorted)))
       (cons item sorted))
      (else (cons (car sorted) (insert item (cdr sorted))))))
  (let loop ((rest children) (sorted '()))
    (if (null? rest)
      sorted
      (loop (cdr rest) (insert (car rest) sorted)))))

;; (render-overlay-html node path) → full HTML document string
;; Pure function. node is the root tree node, path is the navigation path.
;; Includes overlay.js for incremental updates.
(define (render-overlay-html node path)
  (let ((css (if (string=? overlay-custom-css "")
               overlay-base-css
               (string-append overlay-base-css "\n" overlay-custom-css))))
    (html-document
      (make-raw-html
        (string-append
          (html->string (style-element '() css))
          (html->string (script-element '() overlay-js))))
      (render-overlay-body node path))))

;; Build JSON string for overlay data and push to JS updateOverlay().
;; Much faster than full HTML replacement for group navigation.
(define (push-overlay-update node path)
  (let* ((root-label (node-label node))
         (current (if (null? path)
                    node
                    (navigate-to-path node path)))
         (children (if current (node-children current) '()))
         (sorted (sort-children children))
         ;; Build path JSON array
         (path-json (string-append "["
                      (let loop ((segs path) (result ""))
                        (if (null? segs)
                          result
                          (loop (cdr segs)
                                (string-append result
                                  (if (string=? result "") "" ",")
                                  "\"" (js-escape-overlay (car segs)) "\""))))
                      "]"))
         ;; Build entries JSON array
         (entries-json (string-append "["
                         (let loop ((items sorted) (result ""))
                           (if (null? items)
                             result
                             (let* ((item (car items))
                                    (k (node-key item))
                                    (lbl (node-label item))
                                    (is-grp (group? item)))
                               (loop (cdr items)
                                     (string-append result
                                       (if (string=? result "") "" ",")
                                       "{\"key\":\"" (js-escape-overlay k)
                                       "\",\"label\":\"" (js-escape-overlay lbl)
                                       "\",\"isGroup\":" (if is-grp "true" "false")
                                       "}")))))
                         "]")))
    (webview-eval overlay-webview-id
      (string-append "updateOverlay({\"label\":\""
        (js-escape-overlay root-label) "\",\"path\":" path-json
        ",\"entries\":" entries-json "})"))))

;; Escape string for embedding in JSON/JS string literal.
(define (js-escape-overlay str)
  (let loop ((chars (string->list str)) (result '()))
    (if (null? chars)
      (list->string (reverse result))
      (let ((c (car chars)))
        (loop (cdr chars)
              (cond
                ((char=? c #\\) (append '(#\\ #\\) result))
                ((char=? c #\") (append '(#\" #\\) result))
                ((char=? c #\newline) (append '(#\n #\\) result))
                (else (cons c result))))))))

;; ─── Overlay Lifecycle (Side-Effecting) ───────────────────────

;; Handle messages posted from the overlay panel. Currently the only
;; message is {type: "cancel"} sent by WebViewManager when the user clicks
;; outside the panel — exit the modal so the overlay hides.
(define (overlay-message-handler msg)
  (when (equal? (alist-ref msg 'type "") "cancel")
    (modal-exit)))

;; (show-overlay node path) — create panel if needed, render content
(define (show-overlay node path)
  (unless overlay-open?
    (webview-create overlay-webview-id
      (list (cons 'width overlay-panel-width)
            (cons 'height overlay-panel-height)
            (cons 'activating #f)
            (cons 'floating #t)
            (cons 'transparent #t)
            (cons 'shadow #t)))
    (webview-on-message overlay-webview-id overlay-message-handler)
    (set! overlay-open? #t))
  (webview-set-html! overlay-webview-id
    (render-overlay-html node path)))

;; (update-overlay node path) — update content via JS (no page reload)
(define (update-overlay node path)
  (when overlay-open?
    (push-overlay-update node path)))

;; (hide-overlay) — close the panel
(define (hide-overlay)
  (when overlay-open?
    (webview-close overlay-webview-id)
    (set! overlay-open? #f)))
