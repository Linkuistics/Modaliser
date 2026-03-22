;; ui/dom.scm — S-expression to HTML generation
;;
;; Hiccup-style DSL for building HTML strings from Scheme.
;; All functions are pure — no side effects.
;;
;; Core API:
;;   (element tag attrs . children) → HTML string
;;   (div attrs . children), (span attrs . children), etc. — convenience
;;   (html-escape str) → escaped string (& < > " ')
;;   (render-attrs alist) → attribute string
;;   (html-document head-content body-content) → full <!DOCTYPE html> document

;; ─── HTML Escaping ────────────────────────────────────────────

(define (html-escape str)
  (let loop ((chars (string->list str)) (result '()))
    (if (null? chars)
      (list->string (reverse result))
      (let ((c (car chars)))
        (loop (cdr chars)
              (cond
                ((char=? c #\&) (append (reverse (string->list "&amp;")) result))
                ((char=? c #\<) (append (reverse (string->list "&lt;")) result))
                ((char=? c #\>) (append (reverse (string->list "&gt;")) result))
                ((char=? c #\") (append (reverse (string->list "&quot;")) result))
                ((char=? c #\') (append (reverse (string->list "&#39;")) result))
                (else (cons c result))))))))

;; ─── Attribute Rendering ──────────────────────────────────────

;; Render an alist of attributes to an HTML attribute string.
;; '((class "foo") (id "bar")) → " class=\"foo\" id=\"bar\""
;; Boolean attributes: '((disabled #t)) → " disabled"
;; False/void attributes are omitted: '((hidden #f)) → ""
(define (render-attrs attrs)
  (if (or (null? attrs) (not attrs))
    ""
    (let loop ((pairs attrs) (result ""))
      (if (null? pairs)
        result
        (let* ((pair (car pairs))
               (key (symbol->string (car pair)))
               (val (cdr pair)))
          (cond
            ((eq? val #f)
             (loop (cdr pairs) result))
            ((eq? val #t)
             (loop (cdr pairs) (string-append result " " key)))
            (else
             (loop (cdr pairs)
                   (string-append result " " key "=\"" (html-escape val) "\"")))))))))

;; ─── Core Element Constructor ─────────────────────────────────

;; Void elements that must not have a closing tag
(define void-elements
  '("area" "base" "br" "col" "embed" "hr" "img" "input"
    "link" "meta" "source" "track" "wbr"))

(define (void-element? tag)
  (member tag void-elements))

;; (element tag attrs . children) → HTML string
;; tag: string (e.g. "div")
;; attrs: alist or '() for no attributes
;; children: strings (text nodes, auto-escaped) or nested element results
(define (element tag attrs . children)
  (let ((attr-str (render-attrs attrs)))
    (if (void-element? tag)
      (string-append "<" tag attr-str ">")
      (string-append "<" tag attr-str ">"
                     (render-children children)
                     "</" tag ">"))))

;; Render a list of children. Strings are HTML-escaped as text nodes.
;; Non-string values are assumed to be pre-rendered HTML strings from
;; nested element calls — but we mark them specially. For simplicity,
;; we use a convention: element returns strings, and we distinguish
;; "raw HTML" from "text" by using raw-html wrapper.
(define (render-children children)
  (let loop ((items children) (result ""))
    (if (null? items)
      result
      (let ((child (car items)))
        (loop (cdr items)
              (string-append result
                (cond
                  ((string? child) (html-escape child))
                  ((raw-html? child) (raw-html-content child))
                  (else ""))))))))

;; ─── Raw HTML Wrapper ─────────────────────────────────────────
;; Used to pass pre-rendered HTML through render-children without
;; double-escaping. element() returns raw-html wrapped strings.

(define raw-html-tag (list 'raw-html))

(define (make-raw-html str)
  (cons raw-html-tag str))

(define (raw-html? x)
  (and (pair? x) (eq? (car x) raw-html-tag)))

(define (raw-html-content x)
  (cdr x))

;; Override element to return raw-html wrapped result
(define (element tag attrs . children)
  (let ((attr-str (render-attrs attrs)))
    (make-raw-html
      (if (void-element? tag)
        (string-append "<" tag attr-str ">")
        (string-append "<" tag attr-str ">"
                       (render-children children)
                       "</" tag ">")))))

;; ─── Convenience Element Functions ────────────────────────────

(define (div attrs . children)
  (apply element "div" attrs children))

(define (span attrs . children)
  (apply element "span" attrs children))

(define (p attrs . children)
  (apply element "p" attrs children))

(define (a attrs . children)
  (apply element "a" attrs children))

(define (h1 attrs . children)
  (apply element "h1" attrs children))

(define (h2 attrs . children)
  (apply element "h2" attrs children))

(define (h3 attrs . children)
  (apply element "h3" attrs children))

(define (ul attrs . children)
  (apply element "ul" attrs children))

(define (ol attrs . children)
  (apply element "ol" attrs children))

(define (li attrs . children)
  (apply element "li" attrs children))

(define (button attrs . children)
  (apply element "button" attrs children))

(define (input-element attrs)
  (apply element "input" attrs '()))

(define (img attrs)
  (apply element "img" attrs '()))

(define (br)
  (element "br" '()))

(define (hr)
  (element "hr" '()))

;; style and script elements contain raw text (CSS/JS) that must NOT be
;; HTML-escaped. Wrap string children in raw-html automatically.
(define (style-element attrs . children)
  (apply element "style" attrs (map ensure-raw-html children)))

(define (script-element attrs . children)
  (apply element "script" attrs (map ensure-raw-html children)))

(define (ensure-raw-html child)
  (if (string? child) (make-raw-html child) child))

(define (section attrs . children)
  (apply element "section" attrs children))

(define (header attrs . children)
  (apply element "header" attrs children))

(define (footer attrs . children)
  (apply element "footer" attrs children))

(define (nav attrs . children)
  (apply element "nav" attrs children))

;; ─── Document Wrapper ─────────────────────────────────────────

;; (html-document head-content body-content) → full HTML document string
;; head-content and body-content should be raw-html values from element calls
(define (html-document head-content body-content)
  (string-append
    "<!DOCTYPE html><html>"
    "<head><meta charset=\"utf-8\">"
    (if head-content (raw-html-content head-content) "")
    "</head><body>"
    (if body-content (raw-html-content body-content) "")
    "</body></html>"))

;; ─── Utility ──────────────────────────────────────────────────

;; Convert a raw-html value to its string for use with webview-set-html!
(define (html->string h)
  (if (raw-html? h) (raw-html-content h) h))
