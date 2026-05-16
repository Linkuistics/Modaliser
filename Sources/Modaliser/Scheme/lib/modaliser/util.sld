;; (modaliser util) — Shared utility functions used across other
;; (modaliser …) libraries. Pure Scheme except for the centralised
;; SRFI 69 hashtable re-exports below. After Phase D this library
;; imports only (scheme …) and (srfi …); no host-specific libraries.

(define-library (modaliser util)
  (export alist-ref
          props->alist
          string-join
          read-file-text
          log
          ;; SRFI 69 hashtable surface (re-exported for callers that
          ;; import (modaliser util) and don't want to depend on
          ;; (srfi 69) by name).
          make-hash-table hash-table-set! hash-table-ref/default
          string-hash
          ;; Local string helpers (no SRFI 13 in LispKit's bundle,
          ;; so we implement these on (scheme base) directly).
          string-split string-trim string-contains?)
  (import (scheme base)
          (scheme file)
          (scheme write)
          (scheme char)
          (srfi 69))
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
      (newline))

    ;; ─── Local string ops ───────────────────────────────────────
    ;; Implemented on (scheme base) only; no SRFI 13 needed.

    (define (string-index-of haystack needle start)
      ;; Returns the index of the first match of needle in haystack at
      ;; or after start, or #f if not found. Naive O(n*m) scan — fine
      ;; for the short strings we split on (paths, command output).
      (let ((hlen (string-length haystack))
            (nlen (string-length needle)))
        (if (zero? nlen)
          start
          (let outer ((i start))
            (cond
              ((> (+ i nlen) hlen) #f)
              ((let inner ((j 0))
                 (cond
                   ((= j nlen) #t)
                   ((char=? (string-ref haystack (+ i j))
                            (string-ref needle j))
                    (inner (+ j 1)))
                   (else #f)))
               i)
              (else (outer (+ i 1))))))))

    (define (string-contains? haystack needle)
      (if (string-index-of haystack needle 0) #t #f))

    (define (string-split str sep)
      ;; Split str on every occurrence of the literal string sep.
      ;; Matches the input/output shape the existing callers rely on:
      ;;   (string-split "a/b/c" "/") => ("a" "b" "c")
      ;;   (string-split "abc" "/")   => ("abc")
      ;;   (string-split "" "/")      => ("")
      (let ((slen (string-length str))
            (seplen (string-length sep)))
        (if (zero? seplen)
          (list str)
          (let loop ((start 0) (acc '()))
            (let ((hit (string-index-of str sep start)))
              (if hit
                (loop (+ hit seplen)
                      (cons (substring str start hit) acc))
                (reverse (cons (substring str start slen) acc))))))))

    (define (string-trim str)
      ;; Strip leading/trailing whitespace (per char-whitespace?).
      (let ((len (string-length str)))
        (let scan-left ((i 0))
          (cond
            ((= i len) "")
            ((char-whitespace? (string-ref str i)) (scan-left (+ i 1)))
            (else
              (let scan-right ((j (- len 1)))
                (if (char-whitespace? (string-ref str j))
                  (scan-right (- j 1))
                  (substring str i (+ j 1))))))))) ))
