;; (modaliser util) — Shared utility functions used across other
;; (modaliser …) libraries. Pure Scheme except for the centralised
;; LispKit re-exports below, which Phase D will replace with portable
;; equivalents (SRFI 69 / (scheme hash-table); SRFI 13 string ops).

(define-library (modaliser util)
  (export alist-ref
          props->alist
          string-join
          read-file-text
          log
          ;; Phase D: replace with SRFI 69 or (scheme hash-table) names
          make-hashtable hashtable-set! hashtable-ref
          string-hash
          ;; Phase D: replace with SRFI 13 (string-contains / string-trim)
          string-split string-trim string-contains?)
  (import (scheme base)
          (scheme file)
          (scheme write)
          ;; Phase D: drop in favour of SRFI 69 / (scheme hash-table)
          (lispkit hashtable)
          ;; Phase D: drop in favour of SRFI 13 / (scheme char)
          (lispkit string))
  (begin

    (define (alist-ref alist key . default)
      (let ((pair (assoc key alist)))
        (if pair
          (cdr pair)
          (if (null? default) #f (car default)))))

    (define (props->alist . args)
      (let loop ((rest args) (result '()))
        (if (or (null? rest) (null? (cdr rest)))
          (reverse result)
          (loop (cdr (cdr rest))
                (cons (cons (car rest) (car (cdr rest))) result)))))

    (define (string-join strs sep)
      (if (null? strs)
        ""
        (let loop ((rest (cdr strs)) (result (car strs)))
          (if (null? rest)
            result
            (loop (cdr rest)
                  (string-append result sep (car rest)))))))

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

    (define (log . args)
      (for-each display args)
      (newline))))
