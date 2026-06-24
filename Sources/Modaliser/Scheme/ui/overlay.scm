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
;; The selection-cursor state for embedded live lists (list-cursor-k6). The
;; renderer registers the owning list each render pass and reads back the
;; selected index; the footer advertises the nav keys while a cursor is active.
(import (modaliser list-cursor))

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
         ;; key-display-html wraps modifier glyphs in <span class="sigil-mod">,
         ;; so it's raw HTML — make-raw-html keeps the `span` builder from
         ;; escaping it. The list-renderer update path and the panel-grid row
         ;; renderer (both in overlay.js) render the same key-display-html output.
         (display-key (if (equal? k " ")
                        "\x2423;"
                        (make-raw-html (key-display-html k))))
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

;; ─── Shared footer-hint mechanism (footer-applicability-k21) ──────
;;
;; A footer advertises command hints; a hint that can't act in the CURRENT
;; context is greyed IN PLACE (never hidden) so the user still sees the key
;; exists. A hint is a (sigil-html label applicable?) triple: footer-hint-span
;; wraps it in <span class="footer-hint">, adding .footer-hint--disabled (which
;; base.css dims) when applicable? is #f. footer-hints-html joins a list of
;; such triples with the ` · ` middot separator both footers already use.
;; Generic by design — shared by the chooser footer (chooser-footer-html plus
;; its chooser.js mirror) and the overlay cursor-nav footer below.
(define (footer-hint-span sigil-html label applicable?)
  (string-append
    "<span class=\"footer-hint"
    (if applicable? "" " footer-hint--disabled")
    "\">" sigil-html " " label "</span>"))

(define (footer-hints-html hints)
  (let loop ((rest hints) (acc ""))
    (if (null? rest)
      acc
      (let* ((h (car rest))
             (span (footer-hint-span (car h) (cadr h) (caddr h)))
             (sep (if (string=? acc "") "" " \xb7; ")))
        (loop (cdr rest) (string-append acc sep span))))))

(define overlay-footer-html-root
  (string-append overlay-sigil-escape " cancel"))
;; Deep paths show two hints. Order is `⌫ back · ⎋ cancel` so cancel
;; sits rightmost — consistent with the chooser and root footer where
;; cancel/exit always anchors the right edge.
(define overlay-footer-html-deep
  (string-append overlay-sigil-back " back \xb7; "
                 overlay-sigil-escape " cancel"))

;; Selection-cursor nav hints, prepended to the footer while an embedded list
;; owns the cursor (list-cursor-k6). ↑↓/⏎ reuse the .sigil-arrows / .sigil-return
;; glyph styling already in base.css; "1–9 jump" advertises the immediate digit
;; selectors that stay live alongside the cursor. Routed through the shared
;; footer-hint mechanism so all three grey out together when the active live
;; list is empty (applicable? = the list has > 0 rows) — there is then nothing
;; to move to, select, or jump to (footer-applicability-k21).
(define (overlay-footer-cursor-html applicable?)
  (footer-hints-html
    (list (list "<span class=\"sigil sigil-arrows\">\x2191;\x2193;</span>" "move" applicable?)
          (list "<span class=\"sigil sigil-return\">\x23ce;</span>" "select" applicable?)
          (list "1\x2013;9" "jump" applicable?))))

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
  (let ((base (if (back-available-for-path? path)
                overlay-footer-html-deep
                overlay-footer-html-root)))
    ;; When a list cursor is active (set during the just-finished render pass —
    ;; renderer-body-json runs before the footer is built), lead with the nav
    ;; hints so the user sees ↑↓/⏎ alongside the cancel/back sigils. The nav
    ;; hints grey out when the active list is empty (list-cursor-has-selection?
    ;; is #f) — the cursor can be active over a zero-row list (block-json offers
    ;; the targets accessor regardless of row count).
    (if (list-cursor-active?)
      (string-append (overlay-footer-cursor-html (list-cursor-has-selection?))
                     " \xb7; " base)
      base)))

;; ─── Key display ──────────────────────────────────────────────
;;
;; The modal encodes Ctrl as a "C-" prefix, Alt as "M-", Shift on a
;; non-letter as "S-", and Shift on a letter by upcasing it (see
;; modal-key-handler). For display we turn the prefixes back into
;; macOS modifier glyphs: ⌃ ⌥ ⇧. A shifted *letter* keeps its
;; uppercase form and gets NO ⇧ glyph — the capital already carries
;; the shift, and ⌃⇧I beside a capital I reads as doubled. The ⇧
;; glyph appears only for the "S-" (non-letter) case. Two views of
;; the same parse — key-display-text for column-width counting, and
;; key-display-html with the sigils wrapped in <span class="sigil-mod">.

;; (parse-key k) → (list ctrl? alt? shift? base-string) or #f.
;; shift? is true only for an "S-" prefix (non-letter shift); a
;; shifted letter arrives already uppercased with no prefix. #f when
;; k is not a single (optionally prefixed) keystroke — e.g. a "1.."
;; range label — so it renders verbatim.
(define (parse-key k)
  (let loop ((s k) (ctrl #f) (alt #f) (shift #f))
    (cond
      ((and (>= (string-length s) 2) (string=? (substring s 0 2) "C-"))
       (loop (substring s 2 (string-length s)) #t alt shift))
      ((and (>= (string-length s) 2) (string=? (substring s 0 2) "M-"))
       (loop (substring s 2 (string-length s)) ctrl #t shift))
      ((and (>= (string-length s) 2) (string=? (substring s 0 2) "S-"))
       (loop (substring s 2 (string-length s)) ctrl alt #t))
      ((= (string-length s) 1)
       (list ctrl alt shift s))
      (else #f))))

;; Plain-glyph display form, e.g. "C-I" → "⌃I", "S-1" → "⇧1". Its
;; string-length is the visible column width (one code point/glyph).
(define (key-display-text k)
  (let ((p (parse-key k)))
    (if p
      (string-append
        (if (list-ref p 0) "⌃" "")
        (if (list-ref p 1) "⌥" "")
        (if (list-ref p 2) "⇧" "")
        (list-ref p 3))
      k)))

;; HTML display form — modifier glyphs wrapped for CSS styling.
(define (key-display-html k)
  (let ((p (parse-key k))
        (sig (lambda (g) (string-append "<span class=\"sigil-mod\">" g "</span>"))))
    (if p
      (string-append
        (if (list-ref p 0) (sig "⌃") "")
        (if (list-ref p 1) (sig "⌥") "")
        (if (list-ref p 2) (sig "⇧") "")
        (list-ref p 3))
      k)))

;; (max-key-chars children) → integer ≥ 2
;; The widest key column among `children`, measured in visible glyphs
;; (key-display-text, so "⌃⇧I" counts 3 not "C-I"'s raw 3 — and
;; "⇧H" counts 2 not "H"'s 1). Clamped to a minimum of 2 so
;; single-char keys still get breathing room before the arrow column.
(define (max-key-chars children)
  (let loop ((rest children) (best 2))
    (if (null? rest)
      best
      (let ((n (string-length (key-display-text (node-key (car rest))))))
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
  ;; A plain key-list screen embeds no live list, so it never re-offers the
  ;; cursor (only the custom-renderer path brackets a render pass). Clear it
  ;; here so navigating from a list screen into a plain one leaves cursor keys
  ;; inert and drops the footer nav hints.
  (list-cursor-clear!)
  (let* ((children (if current (flatten-categories (node-children current)) '()))
         (sorted   (sort-children children))
         (key-ch   (max-key-chars sorted))
         ;; overlay.js promotes data-key-ch to the --entry-key-ch custom
         ;; property on initial render, mirroring the update path. The column
         ;; count is CSS-intrinsic now (.overlay-entries is an auto-fit grid),
         ;; so no data-cols is emitted.
         (entries-attrs
           (list (cons 'class "overlay-entries")
                 (cons 'data-key-ch (number->string key-ch)))))
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
  (let* ((payload-json (renderer-body-json renderer current))
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

;; (block-json b) → JSON object string
;; Runs the block's optional 'on-render-fn FIRST so side-effects (e.g.
;; chip painting) happen before serialization; its return value — when
;; a pair/alist — is merged into the spec for serialization. LispKit
;; doesn't expose set-cdr!, so blocks that need to splice live data
;; into the payload return it from the thunk rather than mutating their
;; spec.  Then block-spec->json on (spec ∪ dynamic-data).
;; A live-list block carries a 'cursor-targets-fn (a thunk → ((label . target)
;; …)); it offers that accessor to the cursor here as it serializes, so the
;; first list in the screen claims the cursor (renderer-body-json brackets the
;; pass). When this block is the one that owns the cursor, its current selected
;; index rides into the payload as "selected", which the JS renderer marks with
;; .is-focused. The accessor itself is a procedure, so block-spec->json skips it.
;; block-json now serves only the live-list blocks embedded in panels
;; (window-list / iterm-panes / iterm-tabs / window-diagram) via panel->json —
;; the which-key block-list path was removed in the flag-day deletion.
(define (block-json b)
  (let* ((fn-entry (assoc 'on-render-fn b))
         (fn (and fn-entry (cdr fn-entry)))
         (dyn (if (procedure? fn)
                (let ((r (fn))) (if (pair? r) r '()))
                '()))
         (tf-entry (assoc 'cursor-targets-fn b))
         (tf (and tf-entry (cdr tf-entry))))
    (when tf (list-cursor-offer! tf))
    (let ((dyn* (if (and tf (eq? tf (list-cursor-active-targets-fn)))
                  (cons (cons 'selected (list-cursor-index)) dyn)
                  dyn)))
      (block-spec->json (append b dyn*)))))

;; (renderer-body-json renderer current) → JSON object string
;; The body payload for a custom-renderer group. 'panel-grid is the sole
;; renderer — it serializes the presentation metadata the layout DSL lowered
;; onto the screen/open group (ADR-0011). (The legacy 'blocks block-list path
;; was removed in the flag-day deletion; any other marker is a misuse and
;; errors loudly.) Both render-overlay-custom (initial paint) and
;; push-overlay-update (incremental) route through here so the two paths can
;; never diverge.
;; Bracket the body serialization with a list-cursor render pass: each embedded
;; list block offers its targets accessor as it serializes (block-json), the
;; first offer wins (first declared list owns the cursor), and a pass with no
;; offer clears the cursor — so a screen with no live list leaves its keys
;; inert. Both initial paint and incremental push route through here, so the
;; cursor registration can never diverge between the two.
(define (renderer-body-json renderer current)
  (list-cursor-begin-pass!)
  (let ((body (cond
                ((eq? renderer 'panel-grid) (panel-grid-payload-json current))
                (else (error "overlay: unknown renderer marker" renderer)))))
    (list-cursor-end-pass!)
    body))

;; ─── Panel-grid renderer (layout DSL; ADR-0011 / ADR-0012) ───────
;;
;; A `screen` (or a drilled-into `open`) lowered from the layout DSL is a
;; group carrying 'renderer 'panel-grid + an optional authored 'cols / 'layout
;; and a 'loose region. Its DIRECT children are the dispatch children (loose
;; atoms / folded opens, lifted block keys, and the panel categories); the
;; categories render as grid cells, while the loose region rides the 'loose
;; marker (bare-loose-rows-k23). This serializes exactly the alist shape the
;; lowering (dsl.sld lower-panel-grid-body / make-panel-node) emits — the
;; renderer owns the JSON, the DSL owns the alist; the contract was co-designed.
;;
;; Shape: {"type":"panel-grid"[,"cols":N][,"layout":S],
;;         "loose":[<row>|<block>,…],"panels":[<panel>,…]}
;;   <panel>  = {"label":S,"span":S[,"bare":true],"rows":[<row>,…][,"list":<block>]}
;;   <row>    = the shared entry-row shape (entry->row-json): key (ready
;;              key-display-html), label, isGroup, isSticky. A folded top-level
;;              open is a drill row (isGroup true → accent + arrow).
;;   <block>  = a live list / diagram, serialized through the SAME block-json
;;              path panels use for window-list / iterm-panes / iterm-tabs /
;;              window-diagram (so on-render-fn fires + live rows merge in).
;;   "loose"  = the bare, header-less region the JS draws ABOVE the grid: loose
;;              rows and loose bare blocks, declaration order preserved so they
;;              interleave as authored. Empty array → the JS draws no .panel-loose.
;;   "panels" = the masonry grid of real panel cards. Empty array → no .panel-grid.
;;   "layout" = 'masonry (omitted — the CSS default) | 'grid (deterministic);
;;              overlay.js reflects it onto .panel-grid as data-layout.
(define (panel-grid-payload-json current)
  (let* ((cols       (node-renderer-payload current 'cols))
         (layout     (node-renderer-payload current 'layout))
         ;; Screen/open-wide row-ordering default each panel inherits unless it
         ;; sets its own 'order; #f → the panel's ultimate 'keys default
         ;; (manual-panel-order-k24).
         (order      (node-renderer-payload current 'order))
         (loose      (or (node-renderer-payload current 'loose) '()))
         ;; Serialize the loose region FIRST so a loose live-list claims the
         ;; selection cursor ahead of any panel list (first offer wins — see
         ;; block-json / list-cursor-offer!).
         (loose-json (loose-region-json loose))
         (panels     (panels-json (node-children current) order)))
    (string-append
      "{\"type\":\"panel-grid\""
      (if cols (string-append ",\"cols\":" (number->string cols)) "")
      (if layout (string-append ",\"layout\":\"" (symbol->string layout) "\"") "")
      ",\"loose\":["  (string-join-comma loose-json) "]"
      ",\"panels\":[" (string-join-comma panels) "]}")))

;; (loose-region-json loose) → list of JSON strings, declaration order.
;; Each item the lowering placed in the loose region is either a loose node —
;; serialized to the shared entry-row shape (entry->row-json), so a folded
;; top-level open becomes a drill row — or a loose block-spec (a diagram /
;; live-list), serialized through the SAME block-json path the panels use (so
;; on-render-fn fires, live rows merge, and the selection cursor is offered).
;; The JS tells the two apart by shape: a block carries "type", a row "key".
;; Hidden / nested-category nodes drop out (entry->row-json returns #f).
(define (loose-region-json loose)
  (let loop ((rest loose) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((loose-block? (car rest))
       (loop (cdr rest) (cons (block-json (car rest)) acc)))
      (else
       (let ((row (entry->row-json (car rest))))
         (loop (cdr rest) (if row (cons row acc) acc)))))))

;; A loose-region item is a live-list / diagram block-spec (carries 'type)
;; rather than a node-form (carries 'kind). Mirrors dsl.sld's block-spec?
;; (which is library-private, so we re-test the shape here).
(define (loose-block? x)
  (and (pair? x) (assoc 'type x) #t))

;; (panels-json children screen-order) → list of panel JSON strings.
;; The screen/open group's children are loose nodes, lifted block-children, and
;; the real panels (categories). Only the categories render as grid cells —
;; loose nodes and lifted keys belong to the loose region / dispatch, so they
;; are skipped here. SCREEN-ORDER is the grid-wide row-ordering default a panel
;; inherits when it carries no explicit 'order (manual-panel-order-k24).
(define (panels-json children screen-order)
  (let loop ((rest children) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((category? (car rest))
       (loop (cdr rest) (cons (panel->json (car rest) screen-order) acc)))
      (else (loop (cdr rest) acc)))))

;; (panel->json category screen-order) → panel JSON object string
;; Rows come from the category's dispatch children (hidden + nested-category
;; entries filtered exactly as the list path does — this also drops the lifted,
;; 'hidden digit range of an embedded list, which the list section renders
;; instead). 'span is always present (make-panel-node defaults it); 'list is
;; present only when the panel embeds a live list.
;;
;; Row order resolves panel-explicit 'order > SCREEN-ORDER (the grid-wide
;; default) > 'keys (manual-panel-order-k24). 'keys key-sorts the rows (the
;; historic behaviour); 'declared preserves declaration order — node-children is
;; already in authored order, so it's the verbatim, unsorted list. Dispatch is
;; order-independent (find-child), so this is presentation only.
(define (panel->json category screen-order)
  (let* ((label      (node-label category))
         (span       (or (node-renderer-payload category 'span) 'narrow))
         (order      (or (node-renderer-payload category 'order) screen-order 'keys))
         (children   (node-children category))
         (rows       (filtered-rows (if (eq? order 'declared)
                                      children
                                      (sort-children children))))
         (list-block (node-renderer-payload category 'list))
         (bare?      (panel-bare? list-block)))
    (string-append
      "{\"label\":\""  (js-escape-overlay label)
      "\",\"span\":\"" (js-escape-overlay (symbol->string span)) "\""
      (if bare? ",\"bare\":true" "")
      ",\"rows\":["  (string-join-comma rows) "]"
      (if list-block
        (string-append ",\"list\":" (block-json list-block))
        "")
      "}")))

;; (panel-bare? list-block) → boolean (diagram-bare-panel-k22)
;; A panel whose embedded block is a window-diagram hosts it BARE: the
;; renderer drops the card chrome (fill / border / shadow) and the list inset
;; so the diagram's transparent empty cells reveal --overlay-body-bg — window-
;; size proportions become legible (white filled cell vs tinted empty cell) and
;; there's no white card edge to read as misaligned against the start-aligned
;; grid. Keyed on the block 'type so configs need no opt-in; scope is the
;; window-diagram host only (other live-list panels keep their white cards).
(define (panel-bare? list-block)
  (and list-block
       (let ((t (assoc 'type list-block)))
         (and t (eq? (cdr t) 'window-diagram)))))

;; (filtered-rows children) → list of JSON strings (each a row)
(define (filtered-rows children)
  (let loop ((xs children) (acc '()))
    (cond
      ((null? xs) (reverse acc))
      (else
        (let ((row (entry->row-json (car xs))))
          (loop (cdr xs) (if row (cons row acc) acc)))))))

;; (node-hidden? node) → boolean
;; Resolve a node's 'hidden property. The value may be a literal
;; (#t / #f) or a thunk evaluated here at render time — the latter
;; lets a binding's visibility track runtime state (e.g. a cached
;; "is this app configured?" flag) without rebuilding the tree.
(define (node-hidden? node)
  (let ((p (assoc 'hidden node)))
    (and p
         (let ((v (cdr p)))
           (if (procedure? v) (v) v))
         #t)))

;; (entry->row-json c) → JSON string OR #f if skipped
;; Skips hidden entries and nested category nodes (categories inside
;; categories — dispatch flattens through them via find-child, so
;; emitting a bogus empty row here would be inconsistent with dispatch).
(define (entry->row-json c)
  (let* ((hidden? (node-hidden? c))
         (k (node-key c))
         (lbl (node-label c))
         (is-grp (group? c))
         (sticky-target (and (command? c) (node-sticky-target c))))
    (cond
      ((category? c) #f)
      (hidden? #f)
      (else
       (string-append "{\"key\":\"" (js-escape-overlay (key-display-html k))
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
            ;; block-children (dispatch keys, lifted onto the panel by the
            ;; `panel` form — the JS side has no use for them).
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
        ;; Custom-renderer payload carries both the renderer body (block
        ;; list or panel grid, per renderer-body-json) AND the chrome
        ;; (breadcrumb segments, sticky flag, footer HTML) so the JS update
        ;; can refresh the header/footer alongside the body. Without this,
        ;; navigating from the root list into a custom-renderer group leaves
        ;; stale chrome from the previous depth — notably the root footer
        ;; with no backspace hint.
        (let* ((body (renderer-body-json renderer current))
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
  ;; Incremental counterpart to render-overlay-default's clear: a plain key-list
  ;; push has no list to own the cursor, so retire it (and its footer hints).
  (list-cursor-clear!)
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
                        (hidden? (node-hidden? item)))
                   (cond
                     (hidden? (loop (cdr items) result))
                     (else
                       (loop (cdr items)
                             (string-append result
                               (if (string=? result "") "" ",")
                               "{\"key\":\"" (js-escape-overlay (key-display-html k))
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
            (cons 'shadow #t)
            ;; Root for bundle-relative assets served via the modaliser-asset
            ;; scheme handler — lets @font-face load the bundled IBM Plex
            ;; woff2 with no network. Resolves under both dev and the
            ;; installed .app (it is *scheme-directory*, the dir holding
            ;; base.css and fonts/).
            (cons 'asset-root *scheme-directory*)))
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
    (set! overlay-current-renderer #f)
    ;; Modal closed — retire any active list cursor so the next session starts
    ;; with no stale selection.
    (list-cursor-clear!)))

;; Install overlay implementations into the state-machine.
(set-show-overlay!   overlay-show-impl)
(set-update-overlay! overlay-update-impl)
(set-hide-overlay!   overlay-hide-impl)
