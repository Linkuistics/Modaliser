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

;; Read the entire contents of a text file as a string.
;; Uses read-line in a loop to avoid read-string blocking on large k values.
(define (read-file-text path)
  (if (file-exists? path)
    (let ((port (open-input-file path)))
      (let loop ((lines '()))
        (let ((line (read-line port)))
          (if (eof-object? line)
            (begin
              (close-input-port port)
              (string-join (reverse lines) "\n"))
            (loop (cons line lines))))))
    ""))

;; Join a list of strings with a separator.
(define (string-join strs sep)
  (if (null? strs)
    ""
    (let loop ((rest (cdr strs)) (result (car strs)))
      (if (null? rest)
        result
        (loop (cdr rest)
              (string-append result sep (car rest)))))))

;; Log a message via display (routes to NSLog via ContextDelegate)
(define (log . args)
  (for-each display args)
  (newline))
