;; Modaliser example — a per-app screen for Google Chrome.
;;
;; ⚠️ THIS FILE IS NEVER LOADED. Modaliser reads exactly one user file,
;; `~/.config/modaliser/config.scm`; everything in `examples/` is
;; reference material that arrives fresh with each installed build (via
;; the `sys/` mirror) and sits there inert. Nothing you change here has
;; any effect, and nothing here can go stale in your config.
;;
;; It exists because a fresh install seeds a Safari screen but not a
;; Chrome one — the seed can only carry one set of choices, and choices
;; are the one thing Modaliser's libraries deliberately do not make for
;; you (docs/adr/0021-decision-free-libraries.md).
;;
;; TO USE IT, one of:
;;
;;   • Copy the two marked ▶ blocks below into your own
;;     `~/.config/modaliser/config.scm` — the screen, and the one line
;;     for the `(configuration …)` call at its bottom.
;;   • Or copy this whole file over `config.scm` as a starting point: it
;;     is a complete, working configuration in its own right (that is
;;     also how the test suite proves it still composes).
;;
;; Then relaunch Modaliser. With Chrome focused, F17 lands here.
;;
;; ─── What this example is really showing ─────────────────────────
;;
;; That a per-app screen needs no library at all. There is no
;; `(modaliser apps chrome)` to import: the bindings are Chrome's own
;; menu shortcuts, and `send-keystroke` from `(modaliser input)` is the
;; whole mechanism. Adding ANY keyboard-driven app is this file with a
;; different bundle id and different shortcuts —
;;
;;   osascript -e 'id of app "Google Chrome"'   ; → com.google.Chrome
;;
;; A library earns its place only when an app needs machinery a
;; keystroke cannot express: AppleScript enumeration, an IPC socket,
;; live-list blocks, a terminal backend record. Compare
;; `examples/tmux.scm`, which is the other case.

(import (modaliser dsl)
        (modaliser configuration)
        (modaliser handoff)
        (modaliser keyboard)
        (modaliser input)
        (modaliser app))

;; ▶ 1/2 — the Chrome screen. Keys, labels and grouping are preference;
;; rebind, drop or regroup any of it. The scope symbol is Chrome's
;; bundle id, which is what makes F17 land here when Chrome is frontmost.
(define chrome-screen
  (screen 'com.google.Chrome

    (group "t" "Tabs"
      (key "n" "New Tab"           (λ () (send-keystroke '(cmd) "t")))
      (key "w" "Close Tab"         (λ () (send-keystroke '(cmd) "w")))
      (key "r" "Reopen Closed Tab" (λ () (send-keystroke '(cmd shift) "t"))))

    (group "b" "Browser"
      (key "l" "Focus Address Bar" (λ () (send-keystroke '(cmd) "l")))
      (key "f" "Find on Page"      (λ () (send-keystroke '(cmd) "f"))))))

;; ─── The rest is a minimal config, so this file stands alone ───────

(define global-screen
  (screen 'global
    (panel "Applications"
      (key "b" "Browser" (λ () (launch-app "Google Chrome"))))))

(modaliser:start!
  (configuration
    (leaders
      (leader 'global F18)
      (leader 'local  F17))
    (overlay-delay 0.3)
    global-screen

    ;; ▶ 2/2 — the screen itself, composed into the configuration value.
    chrome-screen))
