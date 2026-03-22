;; lib/util.scm — Shared utility functions

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
  (define (loop rest result)
    (if (or (null? rest) (null? (cdr rest)))
      (reverse result)
      (loop (cdr (cdr rest))
            (cons (cons (car rest) (car (cdr rest))) result))))
  (loop args '()))

;; Log a message via display (routes to NSLog via ContextDelegate)
(define (log . args)
  (for-each display args)
  (newline))
