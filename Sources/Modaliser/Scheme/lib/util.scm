;; lib/util.scm — Shared utility functions
;;
;; Alist helpers, string operations, and other common utilities
;; used across the Modaliser Scheme codebase.

;; Look up a value by symbol key in an alist.
;; Returns the value (cdr of the pair) or default if not found.
(define (alist-ref alist key . default)
  (let ((pair (assoc key alist)))
    (if pair
      (cdr pair)
      (if (null? default) #f (car default)))))

;; Build an alist from alternating 'key value arguments.
;; (props->alist 'foo 1 'bar 2) → ((foo . 1) (bar . 2))
(define (props->alist . args)
  (let loop ((rest args) (result '()))
    (if (or (null? rest) (null? (cdr rest)))
      (reverse result)
      (loop (cddr rest)
            (cons (cons (car rest) (cadr rest)) result)))))

;; Log a message via NSLog (uses display which routes to NSLog via ContextDelegate)
(define (log . args)
  (for-each display args)
  (newline))
