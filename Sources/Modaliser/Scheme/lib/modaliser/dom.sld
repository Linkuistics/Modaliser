;; (modaliser dom) — S-expression to HTML generation.
;;
;; Hiccup-style DSL for building HTML strings from Scheme. All
;; procedures are pure — no side effects.
;;
;; Used internally by (modaliser chooser) and the overlay renderer.
;; Carved out of the old ui/dom.scm flat-include in Phase H so
;; (modaliser chooser) and (modaliser web-search) could be proper
;; libraries (a library body cannot reach free identifiers from a
;; flat-included file).

(define-library (modaliser dom)
  (export ;; Escaping + attributes
          html-escape render-attrs
          ;; Raw-HTML marker (used to thread pre-built strings through
          ;; element/render-children without double-escaping)
          make-raw-html raw-html? raw-html-content
          ;; Core element constructor + helpers
          element void-element? render-children
          ;; Convenience tag wrappers
          div span p a h1 h2 h3 ul ol li button
          input-element img br hr
          section header footer nav
          style-element script-element ensure-raw-html
          ;; Document wrapper + raw-string extractor
          html-document html->string)
  (import (scheme base))
  (begin

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
    ;;   '((class . "foo") (id . "bar")) → " class=\"foo\" id=\"bar\""
    ;;   '((disabled . #t)) → " disabled"
    ;;   '((hidden . #f)) → "" (false attributes omitted)
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

    ;; ─── Core Element Constructor ─────────────────────────────────

    (define void-elements
      '("area" "base" "br" "col" "embed" "hr" "img" "input"
        "link" "meta" "source" "track" "wbr"))

    (define (void-element? tag)
      (member tag void-elements))

    ;; Render a list of children. Strings are HTML-escaped as text nodes;
    ;; raw-html values are passed through verbatim; everything else is
    ;; dropped (defensive — a misuse rather than a normal path).
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

    ;; (element tag attrs . children) → raw-html
    ;; Wraps the rendered string in raw-html so nested element calls
    ;; don't get HTML-escaped when fed back as children.
    (define (element tag attrs . children)
      (let ((attr-str (render-attrs attrs)))
        (make-raw-html
          (if (void-element? tag)
            (string-append "<" tag attr-str ">")
            (string-append "<" tag attr-str ">"
                           (render-children children)
                           "</" tag ">")))))

    ;; ─── Convenience Element Functions ────────────────────────────

    (define (div attrs . children)     (apply element "div"     attrs children))
    (define (span attrs . children)    (apply element "span"    attrs children))
    (define (p attrs . children)       (apply element "p"       attrs children))
    (define (a attrs . children)       (apply element "a"       attrs children))
    (define (h1 attrs . children)      (apply element "h1"      attrs children))
    (define (h2 attrs . children)      (apply element "h2"      attrs children))
    (define (h3 attrs . children)      (apply element "h3"      attrs children))
    (define (ul attrs . children)      (apply element "ul"      attrs children))
    (define (ol attrs . children)      (apply element "ol"      attrs children))
    (define (li attrs . children)      (apply element "li"      attrs children))
    (define (button attrs . children)  (apply element "button"  attrs children))
    (define (input-element attrs)      (apply element "input"   attrs '()))
    (define (img attrs)                (apply element "img"     attrs '()))
    (define (br)                       (element "br" '()))
    (define (hr)                       (element "hr" '()))
    (define (section attrs . children) (apply element "section" attrs children))
    (define (header attrs . children)  (apply element "header"  attrs children))
    (define (footer attrs . children)  (apply element "footer"  attrs children))
    (define (nav attrs . children)     (apply element "nav"     attrs children))

    ;; style and script elements contain raw text (CSS/JS) that must
    ;; NOT be HTML-escaped. Wrap string children in raw-html so
    ;; render-children passes them through unmodified.
    (define (ensure-raw-html child)
      (if (string? child) (make-raw-html child) child))

    (define (style-element attrs . children)
      (apply element "style" attrs (map ensure-raw-html children)))

    (define (script-element attrs . children)
      (apply element "script" attrs (map ensure-raw-html children)))

    ;; ─── Document Wrapper ─────────────────────────────────────────

    (define (html-document head-content body-content)
      (string-append
        "<!DOCTYPE html><html>"
        "<head><meta charset=\"utf-8\">"
        (if head-content (raw-html-content head-content) "")
        "</head><body>"
        (if body-content (raw-html-content body-content) "")
        "</body></html>"))

    ;; ─── Utility ──────────────────────────────────────────────────

    ;; Convert a raw-html wrapper back to its string form (for use with
    ;; webview-set-html!). Passes plain strings through unchanged.
    (define (html->string h)
      (if (raw-html? h) (raw-html-content h) h))))
