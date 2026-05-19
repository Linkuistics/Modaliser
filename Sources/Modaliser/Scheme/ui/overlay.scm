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
;; User-supplied CSS slurped from ~/.config/modaliser/theme.css at boot.
;; Applies to both the overlay and the chooser/selector — see
;; (overlay-full-css) and the chooser's render path. Name is generic
;; because the surface is overlay+chooser+chip, not overlay-only.
(define user-theme-css "")

;; Renderer of the node the WebView's current DOM was rendered for. Used by
;; overlay-update-impl to detect when an incremental push-overlay-update
;; would target a DOM shape that no longer matches (e.g. navigating from a
;; list-renderer root into a 'blocks group) — in that case we fall back
;; to a full webview-set-html! so the new renderer's JS can find its
;; expected container. Symbol or #f.
(define overlay-current-renderer #f)

;; ─── CSS Theming ─────────────────────────────────────────
;;
;; user-theme-css is the user-CSS slot in the cascade — concatenated
;; LAST so user declarations override base.css and block-registered CSS.
;; The slot is populated by root.scm slurping
;; ~/.config/modaliser/theme.css at boot. There is no Scheme setter:
;; CSS authoring happens in a real .css file, not as a Scheme string.
;; Programmatic users can write a build step that emits theme.css
;; before launch.

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
;; an inline ↻ marker BEFORE the label so the markers align vertically
;; across rows (trailing position varies with label width). Same marker
;; is painted via overlay.js on dynamic updates — see push-overlay-update
;; and the JS side.
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
            (string-append "<span class=\"entry-sticky-marker\">\x21bb;</span>"
                           (html-escape display-label)))))
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
;; Backspace is contextual: it always navigates up a level when the path
;; is non-empty, and at the root of a sticky tree it pops the modal-stack
;; back to the caller (e.g. iTerm local nav pops back into the main
;; iTerm tree). Only suppress the hint when backspace is truly a no-op —
;; at the root of a transient tree, or at the root of a sticky tree with
;; no caller pushed on the stack.
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
;; Deep paths show two hints. Order is `⌫ back · ⎋ cancel` so cancel
;; sits rightmost — consistent with the chooser and root footer where
;; cancel/exit always anchors the right edge.
(define overlay-footer-html-deep
  (string-append overlay-sigil-back " back \xb7; "
                 overlay-sigil-escape " cancel"))

;; (back-available-for-path? path) → #t when backspace navigates somewhere
;; — mirrors modal-step-back's conditions exactly so the hint advertises
;; the actual binding behaviour. The path is the live modal navigation
;; path (always equals modal-current-path at render time), so we can
;; read the modal stack state directly.
(define (back-available-for-path? path)
  (cond
    ((not (null? path)) #t)
    ;; Use modal-stack-empty? rather than reading modal-stack directly:
    ;; LispKit captures a stale binding for top-level identifiers when
    ;; referenced from a .scm file loaded outside a define-library. The
    ;; accessor lives inside (modaliser state-machine), so it always
    ;; reads the live mutable cell.
    ((and (in-sticky-context?) (not (modal-stack-empty?))) #t)
    (else #f)))

(define (footer-html-for-path path)
  (if (back-available-for-path? path)
    overlay-footer-html-deep
    overlay-footer-html-root))

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
  (let* ((children (if current (flatten-categories (node-children current)) '()))
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
  (let* ((payload-json (block-list-payload-json current))
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

;; (block-list-payload-json current) → JSON string
;; Payload: {"type":"blocks","blocks":[<block-json>, ...]}
;;
;; Each block in the group's 'blocks list serializes itself. Blocks
;; that carry their own dispatch children declare them under
;; 'block-children; the (window:overlay …) constructor lifts those
;; into the group's 'children for the state machine. The which-key
;; block additionally partitions its own block-children into ordered
;; misc/category segments at render time.
(define (block-list-payload-json current)
  (let ((blocks (or (node-renderer-payload current 'blocks) '())))
    (string-append
      "{\"type\":\"blocks\",\"blocks\":["
      (string-join-comma (map block-json blocks))
      "]}")))

;; (block-json b) → JSON object string
;; Runs the block's optional 'on-render-fn FIRST so side-effects (e.g.
;; chip painting) happen before serialization; its return value — when
;; a pair/alist — is merged into the spec for serialization. LispKit
;; doesn't expose set-cdr!, so blocks that need to splice live data
;; into the payload return it from the thunk rather than mutating their
;; spec.  Then dispatch on 'type:
;;   'which-key — emit segments by partitioning the block's own children.
;;   other      — block-spec->json on (spec ∪ dynamic-data).
(define (block-json b)
  (let* ((type (let ((e (assoc 'type b))) (and e (cdr e))))
         (fn-entry (assoc 'on-render-fn b))
         (fn (and fn-entry (cdr fn-entry)))
         (dyn (if (procedure? fn)
                (let ((r (fn))) (if (pair? r) r '()))
                '())))
    (cond
      ((eq? type 'which-key)
       (which-key-payload-json
         (let ((e (assoc 'block-children b)))
           (if e (cdr e) '()))))
      (else
       (block-spec->json (append b dyn))))))

;; (which-key-payload-json children) → JSON object
;; Walks `children` once. For each entry:
;;   - category? → emit a {"kind":"category","label":…,"rows":[<row>,…]}
;;     where rows is the category's children.
;;   - else      → emit a {"kind":"misc","row":<row>} segment.
;; Hidden entries (cons (cons 'hidden #t) …) are skipped.
(define (which-key-payload-json children)
  ;; Partition `children` into ordered segments suitable for column-style
  ;; layout. Each (category …) is its own segment; consecutive non-
  ;; category entries coalesce into one misc segment in their declared
  ;; position. The auto-pack in (modaliser dsl) splits implicit runs
  ;; into a misc which-key-block and a category which-key-block already,
  ;; so a single block is typically homogeneous; mixing only happens
  ;; inside an explicit user-written (which-key-block …), and we honour
  ;; their authored order. Misc rows and category rows sort internally.
  ;; Column count is computed from total visible row count so the
  ;; aspect-ratio target reflects what actually fills the overlay.
  (let* ((segments (partition-which-key-segments children))
         (row-count (segments-row-count segments))
         (cols (overlay-column-count row-count)))
    (string-append "{\"type\":\"which-key\",\"cols\":" (number->string cols)
                   ",\"segments\":[" (string-join-comma (map render-segment segments)) "]}")))

;; Partition into segments, preserving declaration order. Consecutive
;; non-category entries flush into one ('misc <nodes>) segment; each
;; category becomes its own ('category <label> <inner>) segment.
(define (partition-which-key-segments children)
  (let loop ((xs children) (pending '()) (acc '()))
    (cond
      ((null? xs)
       (let ((acc (if (null? pending)
                    acc
                    (cons (list 'misc (reverse pending)) acc))))
         (reverse acc)))
      ((category? (car xs))
       (let* ((c     (car xs))
              (label (let ((e (assoc 'label c)))    (if e (cdr e) "")))
              (inner (let ((e (assoc 'children c))) (if e (cdr e) '())))
              (acc   (if (null? pending)
                       acc
                       (cons (list 'misc (reverse pending)) acc)))
              (acc   (cons (list 'category label inner) acc)))
         (loop (cdr xs) '() acc)))
      (else
       (loop (cdr xs) (cons (car xs) pending) acc)))))

;; Total visible rows across all segments. Categories add one row for the
;; heading. Used to drive aspect-ratio-aware column-count selection.
(define (segments-row-count segments)
  (let loop ((rest segments) (total 0))
    (cond
      ((null? rest) total)
      (else
       (let* ((seg (car rest))
              (kind (car seg))
              (rows (cond ((eq? kind 'misc)     (length (cadr seg)))
                          ((eq? kind 'category) (+ 1 (length (caddr seg))))
                          (else                 0))))
         (loop (cdr rest) (+ total rows)))))))

(define (render-segment seg)
  (cond
    ((eq? (car seg) 'misc)
     (let ((rows (filtered-rows (sort-children (cadr seg)))))
       (string-append "{\"kind\":\"misc\",\"rows\":["
                      (string-join-comma rows) "]}")))
    (else  ; 'category
     (let ((rows (filtered-rows (sort-children (caddr seg)))))
       (string-append "{\"kind\":\"category\",\"label\":\""
                      (js-escape-overlay (cadr seg))
                      "\",\"rows\":[" (string-join-comma rows) "]}")))))

;; (filtered-rows children) → list of JSON strings (each a row)
(define (filtered-rows children)
  (let loop ((xs children) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      (else
        (let ((row (entry->row-json (car xs))))
          (loop (cdr xs) (if row (cons row acc) acc)))))))

;; (entry->row-json c) → JSON string OR #f if skipped
;; Skips hidden entries and nested category nodes (categories inside
;; categories — dispatch flattens through them via find-child, so
;; emitting a bogus empty row here would be inconsistent with dispatch).
(define (entry->row-json c)
  (let* ((hidden-pair (assoc 'hidden c))
         (hidden? (and hidden-pair (cdr hidden-pair)))
         (k (node-key c))
         (lbl (node-label c))
         (is-grp (group? c))
         (sticky-target (and (command? c) (node-sticky-target c))))
    (cond
      ((category? c) #f)
      (hidden? #f)
      (else
       (string-append "{\"key\":\"" (js-escape-overlay k)
                      "\",\"label\":\"" (js-escape-overlay lbl)
                      "\",\"isGroup\":" (if is-grp "true" "false")
                      ",\"isSticky\":" (if sticky-target "true" "false")
                      "}")))))

;; (block-spec->json spec) → JSON object string
;; Skip pairs whose value is a procedure (e.g. 'on-render-fn) — those are
;; Scheme-side hooks, not data for the JS renderer.
(define (block-spec->json spec)
  (let loop ((rest spec) (acc '()))
    (cond
      ((null? rest)
       (string-append "{" (string-join-comma (reverse acc)) "}"))
      (else
        (let* ((entry (car rest))
               (k (car entry))
               (v (cdr entry)))
          (cond
            ;; Skip internal-only keys: procedures (on-render-fn) and
            ;; block-children (dispatch keys, lifted to the group by
            ;; (overlay …) — the JS side has no use for them).
            ((procedure? v) (loop (cdr rest) acc))
            ((eq? k 'block-children) (loop (cdr rest) acc))
            (else
              (loop (cdr rest)
                    (cons (string-append
                            "\"" (js-escape-overlay (symbol->string k))
                            "\":" (alist->json v))
                          acc)))))))))

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

;; Sort children alphabetically by key (insertion sort).
;;
;; Comparator is case-insensitive on the primary, with a stable tiebreak
;; that places lowercase before its uppercase variant — so the visible
;; order is "a A b B …" rather than ASCII's "A B … a b …" or a strict
;; lowercase-only ordering. Mixed-case configs read more naturally that
;; way; the user model is "letters in the alphabet, lowercase first".
(define (sort-key-lt? a b)
  ;; Categories and other entries without a binding key carry #f here;
  ;; coerce to "" so they sort before any letter rather than crashing.
  (let* ((a (or a ""))
         (b (or b ""))
         (la (string-downcase a))
         (lb (string-downcase b)))
    (cond
      ((string<? la lb) #t)
      ((string<? lb la) #f)
      ;; Same letter, different case: lowercase first. ASCII gives
      ;; uppercase a LOWER code point, so a > b under string<? means
      ;; a is the lowercase variant.
      (else (string>? a b)))))

(define (sort-children children)
  (define (insert item sorted)
    (cond
      ((null? sorted) (list item))
      ((sort-key-lt? (node-key item) (node-key (car sorted)))
       (cons item sorted))
      (else (cons (car sorted) (insert item (cdr sorted))))))
  (let loop ((rest children) (sorted '()))
    (if (null? rest)
      sorted
      (loop (cdr rest) (insert (car rest) sorted)))))

;; (overlay-full-css) → string
;; The concatenated CSS stack that ends up inside the overlay's <style>
;; block: base.css + library asset contributions + user theme.css.
;; Exposed so the (modaliser theming) chip-style probe can load the
;; exact same CSS into its hidden WebView — any divergence would make
;; computed chip values disagree with what a real chip in the overlay
;; would have. User theme.css sits LAST so its declarations win.
(define (overlay-full-css)
  (let ((extra-css (overlay-assets-concat 'css)))
    (string-append overlay-base-css
                   (if (string=? extra-css "") "" (string-append "\n" extra-css))
                   (if (string=? user-theme-css "") "" (string-append "\n" user-theme-css)))))

;; (render-overlay-html node root-segments path) → full HTML document string
;; Pure function. CSS load order: base.css + library extras + user css.
;; JS load order: overlay.js + library extras.
(define (render-overlay-html node root-segments path)
  (let* ((extra-js  (overlay-assets-concat 'js))
         (css (overlay-full-css))
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
        ;; Custom-renderer payload carries both the block body AND the
        ;; chrome (breadcrumb segments, sticky flag, footer HTML) so the
        ;; JS update can refresh the header/footer alongside the body.
        ;; Without this, navigating from the root list into a block-list
        ;; group leaves stale chrome from the previous depth — notably
        ;; the root footer with no backspace hint.
        (let* ((body (block-list-payload-json current))
               (segments-json (path-segments-json node path))
               (path-json     (path-keys-json path))
               (sticky?       (and (deepest-sticky-on-path node path) #t))
               (footer-html   (footer-html-for-path path))
               (chrome (string-append
                         ",\"rootSegments\":" segments-json
                         ",\"path\":"         path-json
                         ",\"sticky\":"       (if sticky? "true" "false")
                         ",\"footer\":\""     (js-escape-overlay footer-html) "\""))
               ;; body looks like `{"type":"blocks","blocks":[…]}`; splice
               ;; the chrome fields in just before the closing brace.
               (open  (substring body 0 (- (string-length body) 1)))
               (with-chrome (string-append open chrome "}")))
          (webview-eval overlay-webview-id
            (string-append "updateOverlay(" with-chrome ")"))))
      (else
        (push-overlay-update-default node current path)))))

(define (path-segments-json node path)
  (let* ((root-segs (modal-root-segments))
         (segs (append root-segs (path-labels node path))))
    (string-append "["
      (let loop ((xs segs) (out ""))
        (if (null? xs)
          out
          (loop (cdr xs)
                (string-append out
                               (if (string=? out "") "" ",")
                               "\"" (js-escape-overlay (car xs)) "\""))))
      "]")))

(define (path-keys-json path)
  (string-append "["
    (let loop ((xs path) (out ""))
      (if (null? xs)
        out
        (loop (cdr xs)
              (string-append out
                             (if (string=? out "") "" ",")
                             "\"" (js-escape-overlay (car xs)) "\""))))
    "]"))

;; Default list-renderer push (formerly the body of push-overlay-update).
;; Takes the root `node` (needed by path-labels / deepest-sticky-on-path),
;; the already-navigated `current` node, and `path`.
(define (push-overlay-update-default node current path)
  (let* ((children (if current (flatten-categories (node-children current)) '()))
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
                               #t))
                        (hidden-pair (assoc 'hidden item))
                        (hidden? (and hidden-pair (cdr hidden-pair))))
                   (cond
                     (hidden? (loop (cdr items) result))
                     (else
                       (loop (cdr items)
                             (string-append result
                               (if (string=? result "") "" ",")
                               "{\"key\":\"" (js-escape-overlay k)
                               "\",\"label\":\"" (js-escape-overlay lbl)
                               "\",\"isGroup\":" (if is-grp "true" "false")
                               ",\"isSticky\":" (if is-sticky-leaf "true" "false")
                               "}")))))))
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

;; (current-node-renderer node path) → symbol or #f
;; Renderer of the node addressed by `path` within `node`. Reused by show
;; and update impls to track DOM shape.
(define (current-node-renderer node path)
  (let ((current (if (null? path) node (navigate-to-path node path))))
    (and current (node-renderer current))))

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
  (set! overlay-current-renderer (current-node-renderer node path))
  (webview-set-html! overlay-webview-id
    (render-overlay-html node (modal-root-segments) path)))

;; (overlay-update-impl node path) — update content via JS (no page reload).
;; If the destination node uses a different renderer than the one the
;; WebView's DOM was built for, fall back to a full re-render — the JS
;; renderer registry can't reshape the DOM on its own (e.g. swapping
;; an .overlay-entries <ul> for an .overlay-custom-body <div>).
(define (overlay-update-impl node path)
  (when (overlay-open?)
    (let ((new-renderer (current-node-renderer node path)))
      (cond
        ((eq? new-renderer overlay-current-renderer)
         (push-overlay-update node path))
        (else
         (set! overlay-current-renderer new-renderer)
         (webview-set-html! overlay-webview-id
           (render-overlay-html node (modal-root-segments) path)))))))

;; (overlay-hide-impl) — close the panel
(define (overlay-hide-impl)
  (when (overlay-open?)
    (webview-close overlay-webview-id)
    (set-overlay-open! #f)
    (set! overlay-current-renderer #f)))

;; Install overlay implementations into the state-machine.
(set-show-overlay!   overlay-show-impl)
(set-update-overlay! overlay-update-impl)
(set-hide-overlay!   overlay-hide-impl)
