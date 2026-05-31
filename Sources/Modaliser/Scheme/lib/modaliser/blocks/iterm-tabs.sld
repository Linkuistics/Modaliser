;; (modaliser blocks iterm-tabs) — block constructor for the iTerm tabs
;; list. Companion to (modaliser blocks iterm-panes), but for tabs rather
;; than panes — and crucially with NO chip painting: iTerm tabs already
;; live in the tab bar, so there is nothing to overlay on screen. The
;; block just renders a labelled row list (one row per tab, title shown,
;; current tab marked) and snapshots label→tab-index so the parent
;; group's digit key-range can switch tabs by position.
;;
;; (make-iterm-tabs-block) → block-spec alist
;;
;; The block exposes (iterm-tabs-current-targets) → ((label . index) ...)
;; where index is the 1-based tab position as a string. The parent group
;; builds a (key-range "1.." …) that selects the tab at that position.
;;
;; Tab discovery is pure AppleScript (no AX walk), so it works for a
;; single-pane window just as well as a split one.

(define-library (modaliser blocks iterm-tabs)
  (export make-iterm-tabs-block
          iterm-tabs-current-targets
          iterm-tabs-current-labels
          iterm-tabs-refresh!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (modaliser overlay-assets))
  (begin

    (define default-tab-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Per-render state — refreshed by on-render-fn every render. The
    ;; parent group's digit key-range reads from here on key press, so
    ;; whichever tab carried that label at render time is the one switched
    ;; to.
    (define current-tab-targets '())   ;; ((label . index-string) ...)
    (define current-tabs-data '())     ;; row alists: ((label title current) …)

    (define (iterm-tabs-current-targets) current-tab-targets)
    (define (iterm-tabs-current-labels) (map car current-tab-targets))

    ;; AppleScript emitting one line per tab of the focused window:
    ;;   <1-based index> TAB <0|1 is-current> TAB <tab title>
    ;;
    ;; Why tab-delimited and not comma-delimited like the panes code: pane
    ;; discovery splits `id of every session` on commas because UUIDs
    ;; never contain commas. Tab *titles* can ("Grove, staging"), so we
    ;; delimit fields with the tab character and the records with linefeed
    ;; — `title of <tab>` reflects the tab-bar label, including any
    ;; per-tab override set via "Edit Tab Title" (verified against iTerm
    ;; 3.6). The whole program is one -e argument with embedded newlines;
    ;; zsh single-quotes carry them through unchanged. The `is running`
    ;; guard prevents probe-time Launch Services auto-launch — same
    ;; pattern as apps/iterm.sld's focused-pane-id.
    ;;
    ;; `sep`/`lf` are bound to the AppleScript `tab`/`linefeed` constants
    ;; in the GLOBAL scope, before the `tell application "iTerm"` block.
    ;; Inside that block iTerm's dictionary shadows the bare word `tab`
    ;; with its own `tab` CLASS, so `& tab &` would concatenate the
    ;; literal text "tab" instead of a real tab character. Referencing the
    ;; pre-bound `sep` variable inside the tell sidesteps the collision.
    (define iterm-list-tabs-script
      (string-append
        "osascript -e '"
        "if application \"iTerm2\" is running then\n"
        "  set sep to tab\n"
        "  set lf to linefeed\n"
        "  tell application \"iTerm\"\n"
        "    set w to current window\n"
        "    set curID to id of current session of w\n"
        "    set out to \"\"\n"
        "    set i to 0\n"
        "    repeat with t in tabs of w\n"
        "      set i to i + 1\n"
        "      set mark to \"0\"\n"
        "      if (id of current session of t) is curID then set mark to \"1\"\n"
        "      set out to out & i & sep & mark & sep & (title of t) & lf\n"
        "    end repeat\n"
        "    return out\n"
        "  end tell\n"
        "end if' 2>/dev/null"))

    ;; Join `parts` with `sep`. Used to rebuild a title that itself
    ;; contained tab characters: after splitting a record on tab, the
    ;; title is everything from the third field on, re-joined.
    (define (join-with sep parts)
      (cond
        ((null? parts) "")
        ((null? (cdr parts)) (car parts))
        (else (string-append (car parts) sep (join-with sep (cdr parts))))))

    (define tab-char (string #\tab))
    (define lf-char  (string #\newline))

    ;; Run the discovery script, parse it into current-tab-targets and
    ;; current-tabs-data. Only the first 10 tabs get a digit label (the
    ;; default-tab-labels list); any beyond that still render as rows but
    ;; with a blank key and no digit dispatch. Returns the targets alist.
    (define (snapshot-iterm-tabs!)
      (let* ((out   (run-shell iterm-list-tabs-script))
             (lines (string-split out lf-char)))
        (let loop ((ls lines) (labels default-tab-labels)
                   (targets '()) (rows '()))
          (cond
            ((null? ls)
             (set! current-tab-targets (reverse targets))
             (set! current-tabs-data   (reverse rows))
             current-tab-targets)
            (else
             (let ((line (string-trim (car ls))))
               (cond
                 ((string=? line "")
                  (loop (cdr ls) labels targets rows))
                 (else
                  (let* ((fields (string-split line tab-char))
                         (idx    (if (pair? fields)
                                   (string-trim (car fields)) ""))
                         (mark   (if (and (pair? fields) (pair? (cdr fields)))
                                   (string-trim (cadr fields)) "0"))
                         (title  (if (and (pair? fields) (pair? (cdr fields)))
                                   (join-with tab-char (cddr fields)) ""))
                         (current? (string=? mark "1"))
                         (has-label (pair? labels))
                         (label  (if has-label (car labels) "")))
                    (loop (cdr ls)
                          (if has-label (cdr labels) labels)
                          (if has-label (cons (cons label idx) targets) targets)
                          (cons (list (cons 'label label)
                                      (cons 'title title)
                                      (cons 'current current?))
                                rows)))))))))))

    ;; Refresh the snapshot on demand. The digit key-range dispatch
    ;; (apps/iterm.sld) calls this when a tab key is pressed before the
    ;; overlay's on-render snapshot has had a chance to run — a
    ;; leader-then-digit press faster than the overlay delay.
    (define (iterm-tabs-refresh!)
      (snapshot-iterm-tabs!)
      current-tab-targets)

    ;; Constructor. See window-list.sld for the on-render-fn protocol: the
    ;; block-list renderer calls (fn) before serialising each block; any
    ;; pair/alist returned merges into the block JSON. We splice the
    ;; freshly-captured tabs-data so the rendered rows always match the
    ;; live tab layout. No on-leave-fn: unlike the panes block we paint
    ;; nothing, so there is nothing to tear down.
    (define (make-iterm-tabs-block . opts)
      (list (cons 'type 'iterm-tabs)
            (cons 'on-render-fn
              (lambda ()
                (snapshot-iterm-tabs!)
                (list (cons 'tabs current-tabs-data))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/iterm-tabs.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/iterm-tabs.js")))
