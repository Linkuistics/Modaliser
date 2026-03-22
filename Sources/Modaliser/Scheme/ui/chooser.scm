;; ui/chooser.scm — Search/select UI using WebView
;;
;; An activating panel with a search input, filtered result list,
;; and optional action panel. Used by selector nodes in the command tree.
;;
;; Depends on: ui/dom.scm, ui/css.scm, (modaliser webview), (modaliser fuzzy)
;;
;; API:
;;   (open-chooser selector-node)    — open chooser with source data
;;   (close-chooser)                 — close chooser and clean up
;;   (render-chooser-html prompt visible-items query selected-index
;;     actions-visible? actions)     — pure: returns HTML document string
;;   (highlight-matches text indices) — pure: returns raw-html with match spans

;; ─── Chooser State ──────────────────────────────────────────

(define chooser-webview-id "modaliser-chooser")
(define chooser-open? #f)
(define chooser-items '())           ;; raw items from source (list of alists)
(define chooser-item-texts '())      ;; display texts extracted from items
(define chooser-filtered '())        ;; filtered results: ((index display-text (matched-indices...)) ...)
(define chooser-selected-index 0)    ;; index into chooser-filtered
(define chooser-query "")
(define chooser-actions-visible? #f)
(define chooser-selector-node #f)    ;; the selector alist
(define chooser-action-index 0)      ;; index into actions list when panel is visible

;; ─── Panel Configuration ────────────────────────────────────

(define chooser-panel-width 500)
(define chooser-panel-height 420)

;; ─── Highlight Matches ──────────────────────────────────────

;; (highlight-matches text indices) → raw-html
;; Wraps characters at given indices in <span class="match">.
;; Characters not at matched indices are HTML-escaped.
(define (highlight-matches text indices)
  (let* ((chars (string->list text))
         (len (length chars)))
    (make-raw-html
      (let loop ((i 0) (rest chars) (result ""))
        (if (null? rest)
          result
          (let* ((c (car rest))
                 (escaped (html-escape (string c)))
                 (is-match (member i indices)))
            (loop (+ i 1) (cdr rest)
                  (string-append result
                    (if is-match
                      (string-append "<span class=\"match\">" escaped "</span>")
                      escaped)))))))))

;; ─── Rendering (Pure Functions) ─────────────────────────────

;; Render a single result row.
;; item: (index search-text (matched-indices...))
;; source-item: the original alist from chooser-items
;; row-index: position in visible list (for selection highlighting)
;; selected: currently selected row-index
(define (render-chooser-row item source-item row-index selected)
  (let* ((search-text (cadr item))
         (indices (caddr item))
         (display-text (item-display-text source-item))
         (sub-text (alist-ref source-item 'path #f))
         (kind (alist-ref source-item 'kind #f))
         (is-dir (and kind (equal? kind "directory")))
         (is-selected (= row-index selected))
         (row-class (if is-selected "chooser-row selected" "chooser-row"))
)
    ;; Show display-text as title with path underneath when available
    (if sub-text
      (li (list (cons 'class row-class))
        (div '((class . "chooser-row-content"))
          (span (list (cons 'class (if is-dir "chooser-row-text chooser-dir" "chooser-row-text")))
            (if is-dir
              (highlight-matches display-text indices)
              display-text))
          (div '((class . "chooser-row-subtext"))
            (if is-dir
              sub-text
              (highlight-matches search-text indices)))))
      (li (list (cons 'class row-class))
        (span '((class . "chooser-row-text"))
          (highlight-matches search-text indices))))))

;; Render the action panel.
;; actions: list of action alists ((name . "Open") (description . "...") ...)
;; action-index: currently selected action
(define (render-action-panel actions action-index)
  (div '((class . "chooser-actions"))
    (div '((class . "chooser-actions-title")) "Actions")
    (apply ul (cons '((class . "chooser-action-list"))
                    (let loop ((acts actions) (i 0) (result '()))
                      (if (null? acts)
                        (reverse result)
                        (let* ((act (car acts))
                               (name (alist-ref act 'name ""))
                               (desc (alist-ref act 'description ""))
                               (act-key (alist-ref act 'key #f))
                               (key-label (cond
                                            ((eq? act-key 'primary) "\x21b5;")
                                            ((eq? act-key 'secondary) "\x2318;\x21b5;")
                                            (else "")))
                               (is-selected (= i action-index))
                               (item-class (if is-selected
                                             "chooser-action-item selected"
                                             "chooser-action-item")))
                          (loop (cdr acts) (+ i 1)
                                (cons
                                  (li (list (cons 'class item-class))
                                    (span '((class . "chooser-action-key")) key-label)
                                    (span '((class . "chooser-action-label")) name)
                                    (span '((class . "chooser-action-desc")) desc))
                                  result)))))))))

;; (render-chooser-html prompt visible-items query selected-index
;;   actions-visible? actions) → HTML document string
;;
;; prompt: string (e.g. "Find app…")
;; visible-items: list of (index display-text (matched-indices...))
;; query: current search string
;; selected-index: integer index into visible-items
;; actions-visible?: boolean
;; actions: list of action alists
(define chooser-max-visible-rows 50)

(define (render-chooser-html prompt visible-items query selected-index
                             actions-visible? actions)
  (let* ((css (if (string=? overlay-custom-css "")
                overlay-base-css
                (string-append overlay-base-css "\n" overlay-custom-css)))
         (item-count (length visible-items))
         (footer-text (string-append (number->string item-count)
                        (if (= item-count 1) " item" " items")))
         (body
           (div '((class . "chooser"))
             ;; Search input area
             (div '((class . "chooser-search"))
               (div '((class . "chooser-prompt")) prompt)
               (input-element (list (cons 'type "text")
                                    (cons 'class "chooser-input")
                                    (cons 'id "chooser-input")
                                    (cons 'value query)
                                    (cons 'autocomplete "off")
                                    (cons 'autofocus #t))))
             ;; Result list (capped to avoid slow rendering)
             (apply ul (cons '((class . "chooser-results"))
                             (let loop ((items visible-items) (i 0) (rows '()))
                               (if (or (null? items) (>= i chooser-max-visible-rows))
                                 (reverse rows)
                                 (let* ((item (car items))
                                        (orig-index (car item))
                                        (source-item (list-ref chooser-items orig-index)))
                                   (loop (cdr items) (+ i 1)
                                         (cons (render-chooser-row item source-item i selected-index)
                                               rows)))))))
             ;; Footer
             (div '((class . "chooser-footer")) footer-text)
             ;; Action panel (conditional)
             (if actions-visible?
               (render-action-panel actions chooser-action-index)
               (make-raw-html "")))))
    (html-document
      (make-raw-html
        (string-append
          (html->string (style-element '() css))
          (html->string (script-element '() chooser-js))))
      body)))

;; ─── JavaScript ─────────────────────────────────────────────

;; Returns the JavaScript string for the chooser.
;; Handles: input events, keyboard navigation, and postMessage to Scheme.
;; Load from chooser.js file located alongside other Scheme files.
(define chooser-js
  (read-file-text (string-append *scheme-directory* "/ui/chooser.js")))

;; ─── Item Text Extraction ───────────────────────────────────

;; Extract search text from a source item (alist).
;; For directories, uses just the name (so "development" matches "Development"
;; with a high score). For files, uses the full path (for disambiguation).
(define (item-search-text item)
  (let ((kind (assoc 'kind item))
        (path (assoc 'path item))
        (text (assoc 'text item)))
    (cond
      ;; Directories: match against name for better scoring
      ((and kind (equal? (cdr kind) "directory") text) (cdr text))
      ;; Files with path: match against full path
      (path (cdr path))
      (text (cdr text))
      (else ""))))

;; Extract display text from a source item.
(define (item-display-text item)
  (let ((entry (assoc 'text item)))
    (if entry (cdr entry) "")))

;; Extract search texts from all items (used for fuzzy matching).
(define (extract-item-texts items)
  (map item-search-text items))

;; Build visible items list from fuzzy-filter results.
;; fuzzy-results: ((original-index score (matched-indices...)) ...)
;; item-texts: list of search text strings (for lookup)
(define (build-visible-items fuzzy-results item-texts-list)
  (map (lambda (result)
         (let* ((orig-index (car result))
                (indices (caddr result))
                (text (list-ref item-texts-list orig-index)))
           (list orig-index text indices)))
       fuzzy-results))

;; ─── Chooser Lifecycle ──────────────────────────────────────

;; (open-chooser selector-node) — open the chooser for a selector.
;; Calls the source function, renders initial results, sets up message handler.
(define (open-chooser selector-node)
  (let* ((source-fn (alist-ref selector-node 'source #f))
         (file-roots (alist-ref selector-node 'file-roots #f))
         (prompt (alist-ref selector-node 'prompt "Select..."))
         (actions (alist-ref selector-node 'actions '()))
         (items (cond
                  (source-fn (source-fn))
                  (file-roots (index-files file-roots))
                  (else '())))
         (texts (extract-item-texts items))
         ;; Initial: no filter, show all items
         (initial-visible (build-visible-items
                            (fuzzy-filter "" texts)
                            texts)))
    ;; Set chooser state
    (set! chooser-open? #t)
    (set! chooser-items items)
    (set! chooser-item-texts texts)
    (set! chooser-filtered initial-visible)
    (set! chooser-selected-index 0)
    (set! chooser-query "")
    (set! chooser-actions-visible? #f)
    (set! chooser-selector-node selector-node)
    (set! chooser-action-index 0)

    ;; Cache items in Swift for background search
    (chooser-cache-items! items)

    ;; Create activating WebView
    (webview-create chooser-webview-id
      (list (cons 'width chooser-panel-width)
            (cons 'height chooser-panel-height)
            (cons 'activating #t)
            (cons 'floating #t)
            (cons 'transparent #t)
            (cons 'shadow #t)))

    ;; Register message handler
    (webview-on-message chooser-webview-id chooser-message-handler)

    ;; Load page skeleton (search input + empty results + JS).
    ;; JS DOMContentLoaded sends "ready" → triggers async search to populate results.
    (chooser-load-skeleton)))

;; (close-chooser) — close the chooser and reset state.
(define (close-chooser)
  (when chooser-open?
    (webview-close chooser-webview-id)
    (set! chooser-open? #f)
    (set! chooser-items '())
    (set! chooser-item-texts '())
    (set! chooser-filtered '())
    (set! chooser-selected-index 0)
    (set! chooser-query "")
    (set! chooser-actions-visible? #f)
    (set! chooser-selector-node #f)
    (set! chooser-action-index 0)))

;; Render just the results rows as an HTML string (no document wrapper).
(define (render-results-inner-html visible-items selected-index)
  (let loop ((items visible-items) (i 0) (parts '()))
    (if (or (null? items) (>= i chooser-max-visible-rows))
      (apply string-append (reverse parts))
      (let* ((item (car items))
             (orig-index (car item))
             (source-item (list-ref chooser-items orig-index))
             (row-html (html->string (render-chooser-row item source-item i selected-index))))
        (loop (cdr items) (+ i 1) (cons row-html parts))))))

;; Escape a string for embedding in a JavaScript string literal.
(define (js-escape str)
  (let loop ((chars (string->list str)) (result '()))
    (if (null? chars)
      (list->string (reverse result))
      (let ((c (car chars)))
        (loop (cdr chars)
              (cond
                ((char=? c #\\) (append '(#\\ #\\) result))
                ((char=? c #\') (append '(#\' #\\) result))
                ((char=? c #\newline) (append '(#\n #\\) result))
                ((char=? c #\return) (append '(#\r #\\) result))
                (else (cons c result))))))))

;; Push updated results to the chooser WebView via JS DOM update.
;; Only updates the results list and footer — the input field stays intact.
(define (chooser-update-results)
  (when chooser-open?
    (let* ((results-html (render-results-inner-html chooser-filtered chooser-selected-index))
           (item-count (length chooser-filtered))
           (footer-text (string-append (number->string item-count)
                          (if (= item-count 1) " item" " items")))
           (js (string-append
                 "document.querySelector('.chooser-results').innerHTML = '"
                 (js-escape results-html) "';"
                 "document.querySelector('.chooser-footer').textContent = '"
                 (js-escape footer-text) "';")))
      (webview-eval chooser-webview-id js))))

;; Load page skeleton — search input + empty results + JS.
;; JS DOMContentLoaded sends "ready" which triggers async search.
(define (chooser-load-skeleton)
  (when chooser-open?
    (let* ((prompt (alist-ref chooser-selector-node 'prompt "Select..."))
           (css (if (string=? overlay-custom-css "")
                  overlay-base-css
                  (string-append overlay-base-css "\n" overlay-custom-css)))
           (html (html-document
                   (make-raw-html
                     (string-append
                       (html->string (style-element '() css))
                       (html->string (script-element '() chooser-js))))
                   (div '((class . "chooser"))
                     (div '((class . "chooser-search"))
                       (div '((class . "chooser-prompt")) prompt)
                       (input-element (list (cons 'type "text")
                                            (cons 'class "chooser-input")
                                            (cons 'id "chooser-input")
                                            (cons 'value "")
                                            (cons 'autocomplete "off")
                                            (cons 'autofocus #t))))
                     (ul '((class . "chooser-results")))
                     (div '((class . "chooser-footer")) "")))))
      (webview-set-html! chooser-webview-id html))))

;; Full HTML replacement — used for action panel toggle.
(define (chooser-update-html)
  (when chooser-open?
    (let* ((prompt (alist-ref chooser-selector-node 'prompt "Select..."))
           (actions (alist-ref chooser-selector-node 'actions '())))
      (webview-set-html! chooser-webview-id
        (render-chooser-html prompt chooser-filtered chooser-query
                             chooser-selected-index chooser-actions-visible?
                             actions)))))

;; ─── Message Handler ────────────────────────────────────────

;; Handle messages from the chooser JavaScript.
;; msg: alist from JS postMessage (e.g. ((type . "search") (query . "saf")))
(define (chooser-message-handler msg)
  (let ((msg-type (alist-ref msg 'type "")))
    (cond
      ((equal? msg-type "ready")
       ;; Page loaded — populate initial results
       (chooser-async-search! "" chooser-webview-id))
      ((equal? msg-type "search")
       (chooser-handle-search (alist-ref msg 'query "")))
      ((equal? msg-type "select")
       (chooser-handle-select (alist-ref msg 'originalIndex #f)))
      ((equal? msg-type "secondary-action")
       (chooser-handle-secondary-action (alist-ref msg 'originalIndex #f)))
      ((equal? msg-type "cancel")
       (close-chooser))
      ((equal? msg-type "toggle-actions")
       (chooser-handle-toggle-actions)))))

;; ─── Message Handlers ───────────────────────────────────────

(define (chooser-handle-search query)
  (set! chooser-query query)
  (set! chooser-selected-index 0)
  ;; Run fuzzy match on background thread, push results as JSON to JS.
  ;; JS updateResults() renders the DOM directly — no Scheme rendering needed.
  (chooser-async-search! query chooser-webview-id))

;; Navigation is handled entirely in JS (setSelectedIndex) — no Scheme call needed.

(define (chooser-handle-select raw-index)
  (let ((orig-index (and raw-index (exact (truncate raw-index)))))
    (when (and orig-index (>= orig-index 0) (< orig-index (length chooser-items)))
      (let* ((item (list-ref chooser-items orig-index))
           (on-select (alist-ref chooser-selector-node 'on-select #f))
           (actions (alist-ref chooser-selector-node 'actions '()))
           (primary-action (find-action-by-key actions 'primary)))
      (close-chooser)
      (cond
        ((and chooser-actions-visible? primary-action)
         (let ((run-fn (alist-ref primary-action 'run #f)))
           (when run-fn (run-fn item))))
        (on-select (on-select item)))))))

(define (chooser-handle-toggle-actions)
  (set! chooser-actions-visible? (not chooser-actions-visible?))
  (set! chooser-action-index 0)
  ;; Actions panel toggle needs full HTML update (structural change)
  (chooser-update-html))

(define (chooser-handle-secondary-action raw-index)
  (let ((orig-index (and raw-index (exact (truncate raw-index)))))
    (when (and orig-index (>= orig-index 0) (< orig-index (length chooser-items)))
      (let* ((item (list-ref chooser-items orig-index))
             (actions (alist-ref chooser-selector-node 'actions '()))
             (secondary (find-action-by-key actions 'secondary)))
        (when secondary
          (let ((run-fn (alist-ref secondary 'run #f)))
            (close-chooser)
            (when run-fn (run-fn item))))))))

;; ─── Action Helpers ─────────────────────────────────────────

;; Find an action by its 'key field value (e.g. 'primary, 'secondary).
(define (find-action-by-key actions key-val)
  (let loop ((acts actions))
    (if (null? acts)
      #f
      (let ((act (car acts)))
        (if (eq? (alist-ref act 'key #f) key-val)
          act
          (loop (cdr acts)))))))

;; ─── File Indexing ──────────────────────────────────────────
;; index-files is a Swift native function in (modaliser app).
;; It uses FileManager.enumerator on concurrent threads for fast scanning.
