;; core/keymap.scm — Keycode to character mapping
;;
;; This is provided as a Scheme data structure so it can be extended
;; or overridden by user configuration. The keycode->char primitive
;; in the keyboard library handles the actual mapping, but this file
;; provides the Scheme-accessible table for reference and extension.
;;
;; Note: keycode->char is a Swift primitive in (modaliser keyboard).
;; It uses the same US ANSI layout mapping. This file exists for
;; any Scheme-level key mapping needs.

;; Modifier flag helpers
(define (has-cmd? mods)
  (not (= (bitwise-and mods MOD-CMD) 0)))

(define (has-shift? mods)
  (not (= (bitwise-and mods MOD-SHIFT) 0)))

(define (has-alt? mods)
  (not (= (bitwise-and mods MOD-ALT) 0)))

(define (has-ctrl? mods)
  (not (= (bitwise-and mods MOD-CTRL) 0)))
