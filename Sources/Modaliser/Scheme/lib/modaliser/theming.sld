;; (modaliser theming) — Chip-style resolution via a hidden probe WebView.
;;
;; Chip painters (window-list, iterm panes) need concrete pixel/colour
;; values to forward to (modaliser hints). The authoring surface for
;; those values is CSS — the .chip / .chip.faded rules in base.css, plus
;; whatever the user puts in ~/.config/modaliser/theme.css. To resolve
;; those rules to concrete values without reimplementing a CSS engine in
;; Scheme, we spawn a hidden 1×1 offscreen WKWebView at boot, load the
;; full overlay CSS stack into it, and have a tiny inline <script> read
;; getComputedStyle on two probe <div>s and post the resolved alist back
;; via webview-on-message.
;;
;; Probe lifecycle:
;;   1. root.scm calls (theming-set-css-source! thunk) once at boot,
;;      passing a thunk that returns the same CSS string the overlay
;;      uses (base + asset extras + user-theme-css).
;;   2. root.scm then calls (run-chip-theme-probe!). The library creates
;;      a non-activating, transparent, offscreen panel, installs a
;;      message handler, and posts the HTML. WKWebView runs the script,
;;      which posts a {type:"chip-theme", normal:…, faded:…} message.
;;   3. The handler updates the two theme cells and closes the panel.
;;
;; Public API: (current-chip-theme) / (current-chip-theme 'normal|'faded)
;; returns an alist. Before the probe completes, callers see seed
;; defaults that match the .chip / .chip.faded declarations in base.css,
;; so the first chip paint never shows "uninitialised" values. After,
;; callers see the resolved values.
;;
;; No refresh API. Edit theme.css and relaunch — same reload story as
;; every other Modaliser config change. The probe library can't see
;; top-level overlay-base-css / user-theme-css from inside its
;; define-library body (LispKit scope rule, see
;; feedback_lispkit_library_scope.md), so root.scm wires the CSS stack
;; producer in via theming-set-css-source! — same deferred-resolution
;; pattern (modaliser overlay-assets) uses for its file resolver.

(define-library (modaliser theming)
  (export current-chip-theme
          theming-set-css-source!
          run-chip-theme-probe!
          ;; Exposed so tests can verify the probe-result coercion
          ;; without spinning up a real WKWebView.
          coerce-chip-alist)
  (import (scheme base)
          (modaliser util)
          (modaliser webview))
  (begin

    (define probe-panel-id "modaliser-chip-probe")

    ;; CSS-stack producer. Root.scm injects a thunk returning the live
    ;; concatenated CSS string at boot time, after the user config has
    ;; loaded and theme.css has been slurped.
    (define css-stack-producer (lambda () ""))
    (define (theming-set-css-source! thunk)
      (set! css-stack-producer thunk))

    ;; Seed defaults — mirror the .chip / .chip.faded declarations in
    ;; base.css so callers before the async probe completes still get
    ;; sensible values. Colours are hex (HintsLibrary.swift's parser
    ;; handles "#rrggbb"); numbers are bare ints/floats.
    ;;
    ;; "white" → #ffffff, "dodgerblue" → #1e90ff, "black" → #000000 to
    ;; match what the probe will eventually resolve from base.css.
    (define chip-theme-normal
      (list (cons 'color "#ffffff")
            (cons 'background "#1e90ff")
            (cons 'font-size 56)
            (cons 'padding 16)
            (cons 'corner-radius 8)
            (cons 'border-width 1)
            (cons 'border-color "#000000")
            (cons 'offset-x-frac 0.02)
            (cons 'offset-y-frac 0.02)))

    (define chip-theme-faded
      (list (cons 'color "#ffffff")
            (cons 'background "#6f8baa")
            (cons 'font-size 56)
            (cons 'padding 16)
            (cons 'corner-radius 8)
            (cons 'border-width 1)
            (cons 'border-color "#000000")
            (cons 'offset-x-frac 0.02)
            (cons 'offset-y-frac 0.02)))

    ;; (current-chip-theme [variant]) — variant is 'normal (default) or 'faded.
    (define (current-chip-theme . args)
      (let ((variant (if (null? args) 'normal (car args))))
        (cond
          ((eq? variant 'normal) chip-theme-normal)
          ((eq? variant 'faded)  chip-theme-faded)
          (else (error
                  "current-chip-theme: variant must be 'normal or 'faded"
                  variant)))))

    ;; The probe HTML. Two <div class="chip"> elements are added to the
    ;; body so getComputedStyle reports their resolved styles. The
    ;; <script> walks them, converts colours to #rrggbb (so
    ;; HintsLibrary.swift's existing CSS-colour parser handles the
    ;; values unchanged), strips "px" from length values, reads the
    ;; --chip-offset-{x,y}-frac custom properties from :root, then
    ;; posts a single message back to Scheme.
    (define probe-script
      (string-append
        ;; "rgb(...)" / "rgba(...)" → "#rrggbb" or "#rrggbbaa".
        ;; getComputedStyle always returns the rgb/rgba form for
        ;; <color> properties even when the source CSS uses a named
        ;; colour or #hex.
        "function _hex(s){"
        "var m=s.match(/rgba?\\(([\\d.]+)[,\\s]+([\\d.]+)[,\\s]+([\\d.]+)(?:[,\\s/]+([\\d.]+))?\\)/);"
        "if(!m)return s;"
        "var pad=function(x){x=x.toString(16);return x.length<2?'0'+x:x;};"
        "var r=pad(parseInt(m[1]));"
        "var g=pad(parseInt(m[2]));"
        "var b=pad(parseInt(m[3]));"
        "if(m[4]!==undefined){"
        "var a=pad(Math.round(parseFloat(m[4])*255));"
        "if(a==='ff')return '#'+r+g+b;"
        "return '#'+r+g+b+a;"
        "}"
        "return '#'+r+g+b;"
        "}"
        ;; "56px" → 56 (a Number).
        "function _px(s){return parseFloat(s);}"
        "function _probe(el){"
        "var cs=getComputedStyle(el);"
        "return {"
        "color:_hex(cs.color),"
        "background:_hex(cs.backgroundColor),"
        "'font-size':_px(cs.fontSize),"
        "padding:_px(cs.paddingTop),"
        "'corner-radius':_px(cs.borderTopLeftRadius),"
        "'border-width':_px(cs.borderTopWidth),"
        "'border-color':_hex(cs.borderTopColor)"
        "};"
        "}"
        ;; getPropertyValue returns the literal token (e.g. "0.02"),
        ;; which parseFloat handles.
        "var root=getComputedStyle(document.documentElement);"
        "var offx=parseFloat(root.getPropertyValue('--chip-offset-x-frac'));"
        "var offy=parseFloat(root.getPropertyValue('--chip-offset-y-frac'));"
        "var normal=_probe(document.getElementById('probe-normal'));"
        "var faded=_probe(document.getElementById('probe-faded'));"
        "normal['offset-x-frac']=offx;"
        "normal['offset-y-frac']=offy;"
        "faded['offset-x-frac']=offx;"
        "faded['offset-y-frac']=offy;"
        "window.webkit.messageHandlers.modaliser.postMessage({"
        "type:'chip-theme',normal:normal,faded:faded"
        "});"))

    ;; Build the full probe HTML. The CSS stack matches the overlay's
    ;; render order exactly — any divergence means computed values
    ;; drift from what a real chip in the overlay would have.
    (define (probe-html)
      (string-append
        "<!DOCTYPE html><html><head><style>"
        (css-stack-producer)
        "</style></head><body>"
        ;; A glyph in the chip so font metrics resolve sensibly.
        ;; Probes are visually hidden (panel itself is offscreen).
        "<div class=\"chip\" id=\"probe-normal\">M</div>"
        "<div class=\"chip faded\" id=\"probe-faded\">M</div>"
        "<script>" probe-script "</script>"
        "</body></html>"))

    ;; Keys whose values MUST round-trip as Scheme exact integers so
    ;; HintsLibrary.swift's SchemeAlistLookup.lookupFixnum (which only
    ;; matches .fixnum, not .flonum) accepts them. JS parseFloat returns
    ;; a Number; WKScriptMessage bridges those to NSNumber, which Swift
    ;; may decode as .fixnum (integer-valued) or .flonum (any other
    ;; value, e.g. when the user writes `font-size: 56.5px`). Coerce to
    ;; .fixnum at probe-receive time so the bridging quirk and the
    ;; user-CSS edge cases both resolve to the painter-required type in
    ;; one place. offset-{x,y}-frac stay as-is — they're multipliers
    ;; consumed by Scheme arithmetic, never by lookupFixnum.
    (define integer-chip-keys
      '(font-size padding corner-radius border-width))

    (define (coerce-chip-alist alist)
      (let loop ((rest alist) (acc '()))
        (cond
          ((null? rest) (reverse acc))
          (else
           (let* ((entry (car rest))
                  (k (car entry))
                  (v (cdr entry))
                  (coerced
                    (if (and (number? v) (memq k integer-chip-keys))
                      (cons k (exact (round v)))
                      entry)))
             (loop (cdr rest) (cons coerced acc)))))))

    ;; Message handler. Gate on type so spurious messages (e.g. the
    ;; {type:"cancel"} the WebViewManager dispatches on outside-clicks
    ;; for non-activating panels) don't poison the cache.
    (define (handle-probe-message msg)
      (let ((type (alist-ref msg 'type "")))
        (when (equal? type "chip-theme")
          (let ((normal (alist-ref msg 'normal '()))
                (faded  (alist-ref msg 'faded '())))
            ;; LispKit excludes set-cdr! (per
            ;; feedback_lispkit_no_mutable_pairs) — assign fresh alists
            ;; with set! rather than mutating in place.
            (when (pair? normal)
              (set! chip-theme-normal (coerce-chip-alist normal)))
            (when (pair? faded)
              (set! chip-theme-faded  (coerce-chip-alist faded)))
            (webview-close probe-panel-id)))))

    ;; Spawn the probe. Panel is 100×100 (just big enough that WKWebView
    ;; reliably runs the load pipeline) and positioned far offscreen.
    ;; Transparent + non-floating + non-shadowing so even on the
    ;; off-chance it composites at the screen edge there's nothing
    ;; visible. activating: #f so it doesn't steal focus from whatever
    ;; the user is doing while Modaliser is starting up.
    (define (run-chip-theme-probe!)
      (webview-create probe-panel-id
        (list (cons 'width 100) (cons 'height 100)
              (cons 'x -10000) (cons 'y -10000)
              (cons 'activating #f)
              (cons 'floating #t)
              (cons 'transparent #t)
              (cons 'shadow #f)))
      (webview-on-message probe-panel-id handle-probe-message)
      (webview-set-html! probe-panel-id (probe-html)))))
