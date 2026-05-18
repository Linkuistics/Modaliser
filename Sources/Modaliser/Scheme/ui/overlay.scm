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

;; Library-registered assets (add-overlay-asset!, overlay-assets-concat)
;; live in (modaliser overlay-assets) so renderer libraries can register
;; CSS/JS at library-import time without depending on this side-effecting
;; top-level file being loaded.
(import (modaliser overlay-assets))

;; ─── Overlay State ────────────────────────────────────────────

(define overlay-webview-id "modaliser-overlay")
(define overlay-custom-css "")

;; ─── CSS Theming ─────────────────────────────────────────

;; (set-overlay-css! css-string) — store custom CSS to inject after base.css
;; and after any add-overlay-asset! 'css contributions. User-level override —
;; applied LAST so it wins.
(define (set-overlay-css! css)
  (set! overlay-custom-css css))

;; Wire the asset-file resolver so library-registered file assets
;; (add-overlay-asset-file!) get read from the right place. A library
;; begin block can't see *scheme-directory* (it's a top-level binding),
;; so the library pushes relative paths and we resolve them here.
(overlay-assets-set-resolver!
  (lambda (rel) (string-append *scheme-directory* "/" rel)))

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

;; Pixel estimates per entry, used to pick a column count that matches
;; the user's target aspect ratio (overlay-target-aspect-ratio in
;; (modaliser state-machine)). The monospaced font keeps these stable;
;; the exact values aren't critical — they only seed the integer search
;; below, and the user can re-tune via set-overlay-aspect-ratio!.
(define overlay-col-width-px 200)   ;; key + arrow + label + padding
(define overlay-row-height-px 22)   ;; font-size 14 × line-height ≈ 1.4 + pad

;; (overlay-column-count item-count) → integer ≥ 1
;;
;; Pick the column count N whose resulting overlay shape — N columns of
;; ceil(item-count / N) rows — comes closest to overlay-target-aspect-ratio.
;; Integer search over N ∈ [1, item-count]; cheap (≤ item-count
;; iterations, typically <20). Avoids importing (scheme inexact) — `/`
;; on integers yields exact rationals which `abs` and `<` handle.
(define (overlay-column-count item-count)
  (if (<= item-count 1)
    1
    (let loop ((n 1) (best 1) (best-diff #f))
      (if (> n item-count)
        best
        (let* ((rows  (quotient (+ item-count n -1) n))   ;; ceil(item-count/n)
               (w     (* n overlay-col-width-px))
               (h     (* rows overlay-row-height-px))
               (ratio (/ w h))
               (diff  (abs (- ratio (overlay-target-aspect-ratio)))))
          (if (or (not best-diff) (< diff best-diff))
            (loop (+ n 1) n diff)
            (loop (+ n 1) best best-diff)))))))

;; ─── Rendering (Pure Functions) ───────────────────────────────

;; Build a breadcrumb header from a list of segments.
;; header-class is the outer element's class — "overlay-header" for the
;; overlay, "chooser-header" for the chooser.
;; segments: non-empty list of strings, e.g. ("my-server" "Global" "w")
(define (render-header-breadcrumb header-class segments)
  (let ((sep (html->string (span '((class . "breadcrumb-sep")) "\xbb;"))))
    (header (list (cons 'class header-class))
      (span '((class . "breadcrumb"))
        (make-raw-html
          (let loop ((segs segments) (result ""))
            (if (null? segs)
              result
              (loop (cdr segs)
                    (string-append result
                      (if (string=? result "") "" sep)
                      (html-escape (car segs)))))))))))

;; Render an entry for a single child node. Cells whose binding carries
;; 'sticky-target (declarative "after this action, enter that mode") get
;; an inline ↻ marker after the label so users see at a glance that the
;; key keeps them inside the focus mode rather than returning to the
;; underlying app. Same marker is painted via overlay.js on dynamic
;; updates — see push-overlay-update and the JS side.
(define (render-entry child)
  (let* ((k (node-key child))
         (label (node-label child))
         (is-group (group? child))
         (sticky-target (and (command? child) (node-sticky-target child)))
         (display-key (if (equal? k " ") "\x2423;" k))
         (display-label (if is-group
                          (string-append label " \x2026;")
                          label))
         (label-class (if is-group "entry-label group-label" "entry-label")))
    (if sticky-target
      (li '((class . "overlay-entry"))
        (span '((class . "entry-key")) display-key)
        (span '((class . "entry-arrow")) "\x2192;")
        (span (list (cons 'class label-class))
          (make-raw-html
            (string-append (html-escape display-label)
              " <span class=\"entry-sticky-marker\">\x21bb;</span>"))))
      (li '((class . "overlay-entry"))
        (span '((class . "entry-key")) display-key)
        (span '((class . "entry-arrow")) "\x2192;")
        (span (list (cons 'class label-class)) display-label)))))

;; (path-labels root path) → list of strings
;; Walks `path` (list of key chars) from `root`, collecting the label of
;; each successive group. Used to render the breadcrumb path with human-
;; readable labels instead of key chars. Returns the labels collected up
;; to the first key the tree can't resolve.
(define (path-labels root path)
  (if (null? path)
    '()
    (let ((child (find-child root (car path))))
      (if child
        (cons (node-label child) (path-labels child (cdr path)))
        '()))))

;; Render the full overlay body: header + entry list.
;; root-segments: breadcrumb root (e.g. ("my-server" "Global"))
;; node: the registered root tree node (provides children navigation only)
;; path: navigation path from root, e.g. ("w" "m")
;;
;; When the current navigation point is in sticky context (the root or any
;; ancestor on the path is sticky), the .overlay div gets a "sticky" class
;; so users can theme the persistent mode indicator distinctly. Default
;; styling in base.css gives it an accented border using the host color
;; when set, otherwise a darker neutral.
;; Footer text — pinned at the bottom of every overlay so users can see
;; escape/back semantics without consulting docs. Distinct from the
;; entry list (smaller font, border-top in base.css).
;;
;; Sigils rather than words: ⎋ (U+238B) for escape, ⌫ (U+232B) for
;; backspace — matches the glyphs printed on most keyboards and stays
;; readable across the available footer width.
;;
;; Backspace is contextual: at the root of a tree it doesn't apply
;; (transient roots are a no-op for back; sticky roots only pop the
;; modal-stack in the uncommon enter-mode! caller case), so the hint is
;; omitted there to avoid advertising a binding that wouldn't do
;; anything useful from the user's perspective.
;; Sigil glyphs are wrapped in <span class="sigil"> so base.css can bump
;; their font-size + weight above the surrounding footer body — the raw
;; glyphs are too small at the footer's default size.
;; .sigil-escape nudges ⎋ up 2px — the glyph sits low in Menlo / SF Mono
;; relative to surrounding cap-height text, so without the nudge it
;; reads as slightly off-centre.
(define overlay-sigil-escape "<span class=\"sigil sigil-escape\">\x238b;</span>")
;; .sigil-back adds another size bump just for ⌫ — the U+232B glyph
;; carries less ink than ⎋ in monospace fonts, so without the boost it
;; reads visually smaller than its siblings.
(define overlay-sigil-back   "<span class=\"sigil sigil-back\">\x232b;</span>")

(define overlay-footer-html-root
  (string-append overlay-sigil-escape " cancel"))
(define overlay-footer-html-deep
  (string-append overlay-sigil-escape " cancel \xb7; "
                 overlay-sigil-back " back"))

(define (footer-html-for-path path)
  (if (null? path) overlay-footer-html-root overlay-footer-html-deep))

;; (max-key-chars children) → integer ≥ 2
;; The widest key string among `children` in characters, used to pin
;; every entry's key column at that width. Clamped to a minimum of 2
;; so single-char keys still get a bit of breathing room before the
;; arrow column. Monospaced font → character count = column width in ch.
(define (max-key-chars children)
  (let loop ((rest children) (best 2))
    (if (null? rest)
      best
      (let ((n (string-length (node-key (car rest)))))
        (loop (cdr rest) (if (> n best) n best))))))

(define (render-overlay-body root-segments node path)
  (let* ((current  (if (null? path) node (navigate-to-path node path)))
         (segments (append root-segments (path-labels node path)))
         (sticky?  (and (deepest-sticky-on-path node path) #t))
         (cls      (if sticky? "overlay sticky" "overlay"))
         (renderer (and current (node-renderer current))))
    (cond
      (renderer
        (render-overlay-custom cls segments current renderer path))
      (else
        (render-overlay-default cls segments current path)))))

;; Default list renderer body (formerly inline in render-overlay-body).
;; Sorted-children list with multi-column layout + breadcrumb + footer.
(define (render-overlay-default cls segments current path)
  (let* ((children (if current (node-children current) '()))
         (sorted   (sort-children children))
         (n-items  (length sorted))
         (n-cols   (overlay-column-count n-items))
         (key-ch   (max-key-chars sorted))
         (entries-attrs
           (list (cons 'class "overlay-entries")
                 (cons 'style
                   (string-append "--overlay-cols: "  (number->string n-cols)
                                  "; --entry-key-ch: " (number->string key-ch))))))
    (div (list (cons 'class cls))
      (render-header-breadcrumb "overlay-header" segments)
      (apply ul (cons entries-attrs (map render-entry sorted)))
      (div (list (cons 'class (if (null? path)
                                "overlay-footer overlay-footer-root"
                                "overlay-footer")))
        (make-raw-html (footer-html-for-path path))))))

;; (render-overlay-custom cls segments current renderer path) → div
;; Custom renderers receive a payload built from the group's metadata
;; (renderer-emitted) plus the standard breadcrumb header + footer chrome.
;; The body is a single <div data-renderer="TYPE"> carrying the JSON
;; payload as a data-payload attribute; JS reads it on load and calls
;; into the renderer registry. Initial-render payload mirrors what
;; push-overlay-update sends for incremental updates.
(define (render-overlay-custom cls segments current renderer path)
  (let* ((payload-json (custom-renderer-payload-json current renderer))
         ;; data-payload is single-quoted so the inner JSON's double
         ;; quotes don't need HTML entity-encoding. JS reads via
         ;; getAttribute('data-payload') + JSON.parse, which sees the
         ;; literal string either way; keeping it un-escaped makes
         ;; the rendered HTML easier to grep in tests.
         ;; Single quotes don't appear inside the JSON we emit
         ;; (js-escape-overlay covers \, ", newline). Replace any
         ;; that do creep in (e.g. apostrophe in a label) with the
         ;; HTML entity so they don't close the attribute early.
         (payload-attr-safe (string-replace-apos payload-json))
         (custom-body-html
           (string-append
             "<div class=\"overlay-custom-body\""
             " data-renderer=\"" (html-escape (symbol->string renderer)) "\""
             " data-payload='" payload-attr-safe "'></div>")))
    (div (list (cons 'class cls))
      (render-header-breadcrumb "overlay-header" segments)
      (make-raw-html custom-body-html)
      (div (list (cons 'class (if (null? path)
                                "overlay-footer overlay-footer-root"
                                "overlay-footer")))
        (make-raw-html (footer-html-for-path path))))))

;; (panel-bound-keys panels) → list of key strings
;; Walks every panel spec and returns the set of keys painted on
;; panels (grid cells, center, fill). Used to filter the entries
;; passed to custom renderers so panel keys don't appear twice
;; (once on the panel, once in the text entries strip).
(define (panel-bound-keys panels)
  (if (or (not panels) (null? panels))
    '()
    (let loop ((ps panels) (acc '()))
      (if (null? ps)
        acc
        (let* ((p (car ps))
               (ptype (let ((e (assoc 'type p))) (and e (cdr e)))))
          (cond
            ((eq? ptype 'grid)
             (let* ((cells-entry (assoc 'cells p))
                    (cells (and cells-entry (cdr cells-entry))))
               (loop (cdr ps)
                     (let cells-loop ((cs (or cells '())) (a acc))
                       (if (null? cs)
                         a
                         (let* ((c (car cs))
                                (ke (assoc 'key c))
                                (k (and ke (cdr ke))))
                           (cells-loop (cdr cs)
                                       (if k (cons k a) a))))))))
            ((or (eq? ptype 'center) (eq? ptype 'fill))
             (let* ((ke (assoc 'key p))
                    (k (and ke (cdr ke))))
               (loop (cdr ps) (if k (cons k acc) acc))))
            (else (loop (cdr ps) acc))))))))

;; (custom-renderer-payload-json current renderer) → JSON string
;; Default: {type: RENDERER, panels: (...), entries: (...)}.
;; The diagram renderer (Task 6) reads 'panels off the group; the
;; entries field carries any non-panel children as a list of
;; {key, label, isGroup} alists. Children whose key is bound to a
;; panel cell/center/fill are skipped so they aren't rendered twice.
(define (custom-renderer-payload-json current renderer)
  (let* ((panels  (node-renderer-payload current 'panels))
         (bound   (panel-bound-keys panels))
         (children (node-children current))
         (text-entries
           (let loop ((xs children) (acc '()))
             (if (null? xs)
               (reverse acc)
               (let* ((c (car xs))
                      (k (node-key c))
                      (lbl (node-label c))
                      (is-grp (group? c)))
                 (if (member k bound)
                   (loop (cdr xs) acc)
                   (loop (cdr xs)
                         (cons (string-append
                                 "{\"key\":\"" (js-escape-overlay k)
                                 "\",\"label\":\"" (js-escape-overlay lbl)
                                 "\",\"isGroup\":" (if is-grp "true" "false")
                                 "}")
                               acc))))))))
    (string-append "{\"type\":\"" (symbol->string renderer)
      "\",\"panels\":" (panels->json panels)
      ",\"entries\":[" (string-join-comma text-entries) "]}")))

;; (panels->json panels-list) → JSON array string
;; Each panel is itself an alist (panel-spec) — pass to alist->json
;; for a generic conversion. The diagram-panel library (Task 6) is
;; the only producer for now; the format is documented there.
(define (panels->json panels)
  (if (or (not panels) (null? panels))
    "[]"
    (string-append "["
      (string-join-comma (map alist->json panels))
      "]")))

;; Helper: comma-separated join.
(define (string-join-comma xs)
  (let loop ((rest xs) (acc ""))
    (if (null? rest)
      acc
      (loop (cdr rest)
            (if (string=? acc "")
              (car rest)
              (string-append acc "," (car rest)))))))

;; alist->json — generic conversion. Values may be strings, numbers,
;; symbols (rendered as strings), booleans, or nested alists/lists.
(define (alist->json a)
  (cond
    ((string? a) (string-append "\"" (js-escape-overlay a) "\""))
    ((number? a) (number->string a))
    ((symbol? a) (string-append "\"" (js-escape-overlay (symbol->string a)) "\""))
    ((boolean? a) (if a "true" "false"))
    ((null? a) "[]")
    ((pair? a)
     (cond
       ;; Heuristic: alist if every car is a symbol; otherwise list.
       ((every-pair-symbol-keyed? a)
        (string-append "{"
          (string-join-comma
            (map (lambda (entry)
                   (string-append "\"" (js-escape-overlay (symbol->string (car entry)))
                                  "\":" (alist->json (cdr entry))))
                 a))
          "}"))
       (else
         (string-append "["
           (string-join-comma (map alist->json a))
           "]"))))
    (else "null")))

(define (every-pair-symbol-keyed? lst)
  (let loop ((xs lst))
    (cond
      ((null? xs) #t)
      ((not (pair? (car xs))) #f)
      ((not (symbol? (car (car xs)))) #f)
      (else (loop (cdr xs))))))

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

;; (render-overlay-html node root-segments path) → full HTML document string
;; Pure function. CSS load order: base.css + library extras + user css.
;; JS load order: overlay.js + library extras.
(define (render-overlay-html node root-segments path)
  (let* ((extra-css (overlay-assets-concat 'css))
         (extra-js  (overlay-assets-concat 'js))
         (css (string-append overlay-base-css
                             (if (string=? extra-css "") "" (string-append "\n" extra-css))
                             (if (string=? overlay-custom-css "") "" (string-append "\n" overlay-custom-css))
                             "\n"
                             (host-header-css)))
         (js  (string-append overlay-js
                             (if (string=? extra-js "") "" (string-append "\n" extra-js)))))
    (html-document
      (make-raw-html
        (string-append
          (html->string (style-element '() css))
          (html->string (script-element '() js))))
      (render-overlay-body root-segments node path))))

;; Build JSON for overlay update and push to JS updateOverlay().
;; Sends {rootSegments: [...], path: [...], entries: [...]} so the JS
;; can render the breadcrumb identically to the initial Scheme render.
;;
;; Dispatches on (node-renderer current): a typed payload {type, …} is
;; emitted for custom renderers; otherwise the built-in list payload
;; (handled by overlayRenderers.list in overlay.js).
(define (push-overlay-update node path)
  (let* ((current (if (null? path) node (navigate-to-path node path)))
         (renderer (and current (node-renderer current))))
    (cond
      (renderer
        (let ((payload (custom-renderer-payload-json current renderer)))
          (webview-eval overlay-webview-id
            (string-append "updateOverlay(" payload ")"))))
      (else
        (push-overlay-update-default node current path)))))

;; Default list-renderer push (formerly the body of push-overlay-update).
;; Takes the root `node` (needed by path-labels / deepest-sticky-on-path),
;; the already-navigated `current` node, and `path`.
(define (push-overlay-update-default node current path)
  (let* ((children (if current (node-children current) '()))
         (sorted (sort-children children))
         ;; Helper: build a JSON string array from a list of strings.
         (string-list->json
           (lambda (lst)
             (string-append "["
               (let loop ((xs lst) (result ""))
                 (if (null? xs)
                   result
                   (loop (cdr xs)
                         (string-append result
                           (if (string=? result "") "" ",")
                           "\"" (js-escape-overlay (car xs)) "\""))))
               "]")))
         (segments-json (string-list->json (modal-root-segments)))
         (path-json     (string-list->json (path-labels node path)))
         (sticky?       (and (deepest-sticky-on-path node path) #t))
         (entries-json
           (string-append "["
             (let loop ((items sorted) (result ""))
               (if (null? items)
                 result
                 (let* ((item (car items))
                        (k (node-key item))
                        (lbl (node-label item))
                        (is-grp (group? item))
                        (is-sticky-leaf
                          (and (command? item)
                               (node-sticky-target item)
                               #t)))
                   (loop (cdr items)
                         (string-append result
                           (if (string=? result "") "" ",")
                           "{\"key\":\"" (js-escape-overlay k)
                           "\",\"label\":\"" (js-escape-overlay lbl)
                           "\",\"isGroup\":" (if is-grp "true" "false")
                           ",\"isSticky\":" (if is-sticky-leaf "true" "false")
                           "}")))))
             "]")))
    (webview-eval overlay-webview-id
      (string-append "updateOverlay({\"rootSegments\":" segments-json
        ",\"path\":" path-json
        ",\"sticky\":" (if sticky? "true" "false")
        ",\"footer\":\"" (js-escape-overlay (footer-html-for-path path)) "\""
        ",\"cols\":" (number->string (overlay-column-count (length sorted)))
        ",\"keyCh\":" (number->string (max-key-chars sorted))
        ",\"entries\":" entries-json "})"))))

;; Escape apostrophes in a string for safe embedding inside a
;; single-quoted HTML attribute. Used by render-overlay-custom so
;; a JSON payload containing a label like "it's" doesn't close the
;; data-payload attribute prematurely.
(define (string-replace-apos str)
  (let loop ((chars (string->list str)) (result '()))
    (if (null? chars)
      (list->string (reverse result))
      (let ((c (car chars)))
        (loop (cdr chars)
              (if (char=? c #\')
                (append '(#\; #\9 #\3 #\# #\&) result)
                (cons c result)))))))

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

;; (overlay-show-impl node path) — create panel if needed, render content
(define (overlay-show-impl node path)
  (unless (overlay-open?)
    (webview-create overlay-webview-id
      (list (cons 'width overlay-panel-width)
            (cons 'height overlay-panel-height)
            (cons 'activating #f)
            (cons 'floating #t)
            (cons 'transparent #t)
            (cons 'shadow #t)))
    (webview-on-message overlay-webview-id overlay-message-handler)
    (set-overlay-open! #t))
  (webview-set-html! overlay-webview-id
    (render-overlay-html node (modal-root-segments) path)))

;; (overlay-update-impl node path) — update content via JS (no page reload)
(define (overlay-update-impl node path)
  (when (overlay-open?)
    (push-overlay-update node path)))

;; (overlay-hide-impl) — close the panel
(define (overlay-hide-impl)
  (when (overlay-open?)
    (webview-close overlay-webview-id)
    (set-overlay-open! #f)))

;; Install overlay implementations into the state-machine.
(set-show-overlay!   overlay-show-impl)
(set-update-overlay! overlay-update-impl)
(set-hide-overlay!   overlay-hide-impl)
