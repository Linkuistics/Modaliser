;; (modaliser keymap) — Predicates over modifier bitmasks.
;;
;; The MOD-CMD/MOD-SHIFT/MOD-ALT/MOD-CTRL constants themselves live in
;; the native (modaliser keyboard) library (CGEventFlags raw values).
;; This library exists for pure-Scheme code that needs to inspect a
;; modifier mask without depending on host code.

(define-library (modaliser keymap)
  (export has-cmd? has-shift? has-alt? has-ctrl?)
  (import (scheme base)
          (scheme bitwise)
          (modaliser keyboard))
  (begin
    (define (has-cmd? mods)
      (not (= (bitwise-and mods MOD-CMD) 0)))
    (define (has-shift? mods)
      (not (= (bitwise-and mods MOD-SHIFT) 0)))
    (define (has-alt? mods)
      (not (= (bitwise-and mods MOD-ALT) 0)))
    (define (has-ctrl? mods)
      (not (= (bitwise-and mods MOD-CTRL) 0)))))
