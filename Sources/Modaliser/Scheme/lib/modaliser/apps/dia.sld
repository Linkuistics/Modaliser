;; (modaliser apps dia) — Dia browser (company.thebrowser.dia) utilities.
;;
;; Dia ships a real AppleScript dictionary: a `tab` class (title, id,
;; isFocused, URL) plus a `focus` command. tab-source / focus-tab! use it
;; to enumerate the front window's tabs and focus one by id — ready-made
;; for a "Select Tab…" selector row if you want chooser-based tab
;; switching. tab-step / tab-step-back drive Dia's recent-tab (MRU)
;; switcher; see the ctrl-hold/release protocol below — the caller owns
;; the hold.
;;
;; Utilities layer only (ADR-0019): the per-app SCREEN — keys, labels,
;; walks — is preference and is authored in user config; this library
;; carries the machinery so it stays current across upgrades.
;;
;; Recommended import is prefix-style (bare exports collide with peers):
;;   (import (prefix (modaliser apps dia) dia:))
;;   (dia:tab-source)   (dia:focus-tab! item)
;;   (dia:tab-step)     (dia:tab-step-back)

(define-library (modaliser apps dia)
  (export tab-source
          focus-tab!
          tab-step
          tab-step-back)
  (import (scheme base)
          (modaliser shell)
          (modaliser util)
          (modaliser input))
  (begin

    ;; Enumerate the front Dia window's tabs as a list of
    ;; ((text . <title>) (id . <uuid>)) alists for the chooser. The id and
    ;; title lists are pulled in bulk *inside* the tell block (per-tab
    ;; `tab i of w` access throws -1700 in Dia), then zipped with the `tab`
    ;; constant *outside* it — inside the tell, `tab` would bind to Dia's
    ;; tab class instead of the tab character. Each line is "<id>\t<title>".
    ;;
    ;; Front window only — matches ctrl-tab's own within-window scope. To
    ;; cover every window, swap `front window` for `every window` and
    ;; flatten; left out to keep it simple.
    (define (tab-source)
      (let ((raw (run-shell
                  (string-append
                   "osascript"
                   " -e 'tell application \"Dia\"'"
                   " -e 'if (count of windows) is 0 then return \"\"'"
                   " -e 'set theTitles to title of every tab of front window'"
                   " -e 'set theIds to id of every tab of front window'"
                   " -e 'end tell'"
                   " -e 'set out to \"\"'"
                   " -e 'repeat with i from 1 to (count of theTitles)'"
                   " -e 'set out to out & (item i of theIds) & tab & (item i of theTitles) & linefeed'"
                   " -e 'end repeat'"
                   " -e 'return out'"
                   " 2>/dev/null"))))
        (let loop ((lines (string-split (string-trim raw) "\n"))
                   (acc '()))
          (if (null? lines)
              (reverse acc)
              (let* ((line  (string-trim (car lines)))
                     (parts (and (> (string-length line) 0)
                                 (string-split line "\t"))))
                (loop (cdr lines)
                      (if (and parts (pair? parts) (pair? (cdr parts)))
                          ;; 'text is the chooser's display + fuzzy-match field
                          ;; (ui/chooser.scm), NOT 'name as the how-to claims.
                          (cons (list (cons 'text (string-join (cdr parts) "\t"))
                                      (cons 'id   (car parts)))
                                acc)
                          acc)))))))

    ;; Focus the chosen tab by id. The id is a UUID (hex + hyphens), so it
    ;; drops into the AppleScript string with no escaping — which is why
    ;; the chooser dispatches on id rather than the free-form title.
    (define (focus-tab! item)
      (run-shell
       (string-append
        "osascript -e 'tell application \"Dia\" to "
        "focus (first tab of front window whose id is \"" (cdr (assoc 'id item)) "\")' "
        "2>/dev/null")))

    ;; ── Recent-tab MRU stepping (Dia's ctrl-tab switcher) ──
    ;;
    ;; Dia's recent-tab switcher opens on ctrl+tab and commits when control
    ;; is *released*. send-keystroke brackets its modifiers (press → key →
    ;; release), so a one-shot (send-keystroke '(ctrl) "tab") opens the HUD
    ;; and immediately commits — right for "flip to the previous tab", no
    ;; use for walking, since every step would close the HUD again. To walk,
    ;; the caller holds control across the whole walk with
    ;; (send-key-down "ctrl") and releases it with (send-key-up "ctrl"):
    ;; release commits the highlighted tab; send Dia an Escape first to
    ;; cancel instead. The input library tracks held modifiers, so a plain
    ;; (send-keystroke "tab") posted while control is held is automatically
    ;; seen as ctrl+tab — no need to restate the modifier on every tap.
    ;; Mechanics: docs/reference/libraries.md, "(modaliser input)".

    ;; One ctrl+tab (control held by the caller, applied automatically):
    (define (tab-step)      (send-keystroke "tab"))

    ;; One ctrl+shift+tab — walk backward (held ctrl + the explicit shift):
    (define (tab-step-back) (send-keystroke '(shift) "tab"))))
