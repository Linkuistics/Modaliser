;; Dia (company.thebrowser.dia) — F17 local tree.
;;
;; Split out of config.scm into its own per-bundle-id file, included via
;; (include "app-trees/company.thebrowser.dia.scm"). Inherits config.scm's
;; imports (dsl, input, shell, util, …); no per-file import needed.

;; ─── Dia browser (company.thebrowser.dia) ───────────────────────
;;
;; Dia ships a real AppleScript dictionary: a `tab` class (title, id,
;; isFocused, URL) plus a `focus` command. The "Select Tab…" chooser
;; uses it to enumerate the front window's tabs and focus the picked
;; one by id.
;;
;; Front window only — matches ctrl-tab's own within-window scope. To
;; cover every window, swap `front window` for `every window` in
;; dia-tab-source and flatten; left out to keep it simple.
;;
;; No ctrl-tab binding: Dia's recent-tab switcher opens on ctrl+tab and
;; commits when control is *released*, but `send-keystroke` only sets
;; the control *flag* on the tab event — it never posts a discrete
;; control key-up (flagsChanged), so the switcher HUD opens and hangs
;; waiting for a release that never arrives. Reaching it needs real
;; modifier-down/up primitives in the app (KeystrokeEmitter, Swift).
;; The chooser is the config-only path that works.

;; Enumerate the front Dia window's tabs as a list of
;; ((text . <title>) (id . <uuid>)) alists for the chooser. The id and
;; title lists are pulled in bulk *inside* the tell block (per-tab
;; `tab i of w` access throws -1700 in Dia), then zipped with the `tab`
;; constant *outside* it — inside the tell, `tab` would bind to Dia's
;; tab class instead of the tab character. Each line is "<id>\t<title>".
(define (dia-tab-source)
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
(define (dia-focus-tab! item)
  (run-shell
   (string-append
    "osascript -e 'tell application \"Dia\" to "
    "focus (first tab of front window whose id is \"" (cdr (assoc 'id item)) "\")' "
    "2>/dev/null")))

;; ── Recent-tab MRU walk (Dia's ctrl-tab switcher, driven from a modal) ──
;;
;; Dia's recent-tab switcher opens on ctrl+tab and commits when control is
;; *released*. We hold control across the whole Walk (via
;; send-key-down) and release it on exit (send-key-up). The input library
;; tracks held modifiers, so a plain (send-keystroke '() "tab") posted while
;; control is held is automatically seen as ctrl+tab — no need to restate the
;; modifier on every tap. See the app repo spec for the mechanics:
;; docs/specs/2026-06-19-keystroke-modifier-release-and-down-up.md
;;
;; One ctrl+tab (control is held by the modal, applied automatically):
(define (dia-tab-step)      (send-keystroke "tab"))

;; One ctrl+shift+tab — walk backward (held ctrl + the explicit shift):
(define (dia-tab-step-back) (send-keystroke '(shift) "tab"))

(screen 'company.thebrowser.dia
    (key "n" "New Tab"  (λ () (send-keystroke '(cmd) "t")))
    (key "f" "Find Tab" (λ () (send-keystroke '(cmd shift) "a")))

    ;; Positional tab stepping, bound to Dia's own Tabs ▸ Next/Previous
    ;; menu shortcuts (Cmd+Shift+] / Cmd+Shift+[). Dia stacks tabs in a
    ;; *vertical* sidebar, so the hjkl mapping follows the sidebar's axis:
    ;; j (down) → next tab, k (up) → previous tab.
    ;;
    ;; A `walk` "act + latch": the j/k entry keys splice in here as
    ;; top-level Dia cells, and the first press steps a tab *and* crosses
    ;; into the registered 'dia-tab-walk mode, so further j/k keep stepping.
    ;; The mode is auto-tagged 'exit-on-unknown #t, so Esc or any unbound
    ;; key exits. This is *positional* stepping — distinct from the MRU
    ;; "Recent Tabs" walk on r below.
    (walk 'dia-tab-walk "Tabs"
      (key "j" "Next Tab" (λ () (send-keystroke '(cmd shift) "]")))
      (key "k" "Prev Tab" (λ () (send-keystroke '(cmd shift) "["))))

  ;; "Recent Tabs" Walk. Enter holds control and steps once, so the
  ;; HUD opens on the most-recent (next) tab; j/k step forward/back through
  ;; the MRU stack.
  ;;
  ;; Exit is commit-or-cancel, distinguished by the reason the modal passes
  ;; to on-leave:
  ;;   • Return → 'confirm → just release control → Dia commits the
  ;;     highlighted tab.
  ;;   • Escape / any unbound key → 'cancel → send Escape *to Dia* (which
  ;;     dismisses the HUD without switching) and then release control.
  ;; So Esc truly cancels — opening and pressing Esc is a no-op.
  ;;
  ;; on-enter/on-leave are gated on overlay visibility and therefore
  ;; balanced — a held control always gets its matching release. The leading
  ;; (send-key-up "ctrl") self-heals any control left held by an aborted walk.
  (group "r" "Recent Tabs"
    'exit-on-unknown #t
    'on-enter (λ () (send-key-up   "ctrl")   ; clear any stale hold
                    (send-key-down "ctrl")   ; hold control (auto-asserts)
                    (dia-tab-step))          ; open HUD on the next tab
    'on-leave (λ (reason)
                (unless (eq? reason 'confirm)
                  (send-keystroke "escape"))  ; cancel Dia's HUD
                (send-key-up "ctrl"))         ; release (commit if confirmed)
    (key "l" "Next" (λ () (dia-tab-step)) 'next 'self)
    (key "h" "Prev" (λ () (dia-tab-step-back)) 'next 'self)))
