;; (modaliser json) — a small, portable JSON reader and writer.
;;
;; Why this exists. Socket-API muxes (herdr) speak compact single-line,
;; nested JSON. The multiline awk parsers the tmux/zellij/wezterm backends
;; use do NOT transfer to compact single-line output, and the tree had no
;; general JSON reader — each backend rolled its own ad-hoc extractor.
;; This library is the shared, testable answer, in both directions:
;; `herdr` output → Scheme data, and Scheme data → a herdr request line
;; (ADR-0020's socket transport builds `{"id","method","params"}` with
;; json-write rather than by string-appending, so escaping is decided in
;; exactly one place).
;;
;; Portability. Depends on (scheme base) + (scheme char) — no hashtable
;; library, no host JSON primitive — plus (modaliser instrument)'s two counters,
;; which are inert until the host enables them. So it belongs in the
;; portable lib/modaliser tree and keeps check-portable-surface.sh green.
;;
;; Representation (chosen so objects and arrays are distinguishable at a
;; glance, and so extraction is plain assoc / vector-ref):
;;
;;   JSON object  → alist  ((string-key . value) …)   empty → '()
;;   JSON array   → vector  #(value …)                empty → #()
;;   JSON string  → string
;;   JSON number  → number
;;   true / false → #t / #f
;;   null         → the symbol  null
;;
;; Objects (proper lists of pairs) and arrays (vectors) never collide, so
;; `json-ref` walks objects while `vector-ref` / `vector-length` walk
;; arrays. Scalars are self-evident.
;;
;; Caveat (documented, not a bug): a key whose value is JSON `false`
;; reads back as #f, indistinguishable from "key absent" via json-ref.
;; Callers that must tell those apart should check membership first; the
;; herdr backend only extracts strings / arrays / numbers, so it is
;; unaffected.

(define-library (modaliser json)
  (export json-parse json-ref json-write)
  (import (scheme base)
          (scheme char)
          ;; The scan counters (measure-hot-scan-k2) — inert unless the host
          ;; enables them. Both scanners below already hold their own length,
          ;; so the probe never measures one for itself.
          (only (modaliser instrument) instrument-sample!))
  (begin

    ;; Look up string KEY in a parsed JSON object (an alist). Returns the
    ;; value, or #f when OBJ is not an object or lacks the key. A vector
    ;; (array) or scalar OBJ yields #f rather than an error, so chained
    ;; lookups down a path that doesn't exist degrade to #f.
    (define (json-ref obj key)
      (and (list? obj)
           (let ((p (assoc key obj)))
             (and (pair? p) (cdr p)))))

    ;; Parse JSON text into the representation above. Raises on malformed
    ;; input; callers shelling out to a CLI wrap this in `guard` so a
    ;; stray non-JSON line degrades to #f rather than breaking a leader
    ;; press. The internal procedures form a letrec* so their mutual
    ;; references resolve.
    ;;
    ;; ─── Why the source is a vector, not a string ────────────────────
    ;;
    ;; The reader scans by index, and indexing a *string* here is a cliff,
    ;; not a constant factor. LispKit stores Scheme strings as
    ;; `NSMutableString` (`Expr.swift:43`) and `asString()` is `res as String`
    ;; — a whole-string bridge and allocation. `string-ref` bridges and then
    ;; walks a UTF-16 breadcrumb index; `string-length` bridges too. So
    ;; `(when (< k (string-length s)) … (string-ref s k) …)` copies the entire
    ;; payload TWICE PER CHARACTER: ~2n² bytes for one scan.
    ;;
    ;; Measured (`measure-hot-scan-k2`, installed release build): herdr's
    ;; `pane.process_info` reply — 97 360 characters, because one foreground
    ;; process carried a 47 KB command line — parsed in **26 205 ms**, twice
    ;; per leader press, on the thread that owns the CGEvent tap. That is
    ;; ADR-0014's stalled-tap hazard arriving from inside portable Scheme.
    ;;
    ;; So `json-parse` bridges **once**, up front, with `string->vector`, and
    ;; every scanner below reads `chars` with O(1) `vector-ref` against a
    ;; `vector-length` taken once. Literal lifts use `vector->string`, which
    ;; is O(result) over the same vector, so the source string is never
    ;; indexed again after that first conversion. Grepping this procedure for
    ;; `string-ref` should find exactly one site — `parse-lit` comparing
    ;; against its own 4- or 5-character constant ("true" / "false" / "null"),
    ;; where n is a literal 5 and the cliff has nowhere to grow.
    ;;
    ;; Indices are interchangeable: `string->vector` walks `asString().utf16`
    ;; and `string-length` counts the same UTF-16 units, so every offset here
    ;; means what it always meant.
    ;;
    ;; Both conversions are plain `(scheme base)` (LispKit's `VectorLibrary`,
    ;; re-exported by R7RS base), so this costs no host import and
    ;; `check-portable-surface.sh` is unaffected. The alternative — a native
    ;; seam — stays the fallback nobody needed: see ADR-0023.
    ;;
    ;; ─── Why the cursor is passed, not mutated ───────────────────────
    ;;
    ;; Every scanner below takes the index to read from and answers a
    ;; `(value . next-index)` pair. The obvious alternative — one `set!`
    ;; cursor with `peek` / `advance!` helpers, which is what this reader
    ;; used to be — is shorter to read and measurably slower, because in
    ;; an interpreter the cost is *operations per character* and that
    ;; shape spends several more of them on every one:
    ;;
    ;;   - a `set!`-captured variable is boxed, so each `i` read is an
    ;;     indirection and each `advance!` a write through it (measured at
    ;;     2.35 µs vs 1.87 µs for a plain call);
    ;;   - `peek` and `advance!` are closure calls, paid per character;
    ;;   - a loop variable costs neither.
    ;;
    ;; `parse-string` gains the most and is the hot path — most characters
    ;; in a real payload sit inside string literals. Scanning ahead to the
    ;; closing quote and lifting the whole literal out with one native
    ;; `vector->string` replaces a per-character `cons` plus a final `reverse`
    ;; and `list->string`. Only a literal that actually carries a backslash
    ;; falls back to consing (`parse-escaped-string`).
    ;;
    ;; Measured on `(modaliser wms paneru)`'s 1689-byte payload, release
    ;; build: **6.9 ms → 3.9 ms**, producing an `equal?` tree. That matters
    ;; because paneru's parse runs at come-to-rest, on the main thread,
    ;; between one keypress and the next — see
    ;; `docs/specs/paneru-window-management.md` decision 4.
    ;;
    ;; What did NOT help, so nobody re-tries it: a native substring search
    ;; to find the closing quote. LispKit has one, but it lives in a host
    ;; library this tree may not import, and the SRFI that re-exports the
    ;; name backs it with a Scheme KMP loop — slower than the inline scan.
    (define (json-parse str)
      ;; The one bridge. Everything below reads CHARS, never STR.
      (let* ((chars (string->vector str))
             (n     (vector-length chars)))

        (define (skip-ws k)
          (if (and (< k n) (char-whitespace? (vector-ref chars k)))
              (skip-ws (+ k 1))
              k))

        ;; K must hold CH; answers the index after it. Called at grammar
        ;; points only, never per character, so the call is not on the hot
        ;; path — and each one is a validation the reader would otherwise
        ;; silently skip (`{"a" 1}` must not read as `{"a": 1}`).
        (define (expect k ch)
          (if (and (< k n) (char=? (vector-ref chars k) ch))
              (+ k 1)
              (error "json-parse: unexpected character"
                     (if (< k n) (vector-ref chars k) 'end-of-input)
                     'expected ch)))

        (define (parse-value k)
          (let ((k (skip-ws k)))
            ;; Empty and whitespace-only input lands here. It must raise the
            ;; guardable kind — see parse-number's note, which owns the
            ;; reasoning for every malformed-input path.
            (if (>= k n)
                (error "json-parse: expected a value" 'end-of-input)
                (let ((c (vector-ref chars k)))
                  (cond
                    ((char=? c #\{) (parse-object (+ k 1)))
                    ((char=? c #\[) (parse-array (+ k 1)))
                    ((char=? c #\") (parse-string (+ k 1)))
                    ((char=? c #\t) (parse-lit k "true" #t))
                    ((char=? c #\f) (parse-lit k "false" #f))
                    ((char=? c #\n) (parse-lit k "null" 'null))
                    (else (parse-number k)))))))

        (define (parse-lit k word val)
          (let ((len (string-length word)))
            (let loop ((j 0))
              (cond
                ((= j len) (cons val (+ k len)))
                ((and (< (+ k j) n)
                      (char=? (vector-ref chars (+ k j)) (string-ref word j)))
                 (loop (+ j 1)))
                (else (error "json-parse: unexpected character"
                             (if (< (+ k j) n) (vector-ref chars (+ k j)) 'end-of-input)
                             'expected (string-ref word j)))))))

        ;; { key : value , … } → alist, keys reversed back into source order.
        ;; K is the index just past the `{`.
        (define (parse-object k)
          (let ((k (skip-ws k)))
            (if (and (< k n) (char=? (vector-ref chars k) #\}))
                (cons '() (+ k 1))
                (let loop ((k k) (acc '()))
                  (let* ((kv  (parse-string (expect (skip-ws k) #\")))
                         (vv  (parse-value (expect (skip-ws (cdr kv)) #\:)))
                         (e   (skip-ws (cdr vv)))
                         (acc (cons (cons (car kv) (car vv)) acc)))
                    (cond
                      ((>= e n) (error "json-parse: malformed object" 'end-of-input))
                      ((char=? (vector-ref chars e) #\,) (loop (+ e 1) acc))
                      ((char=? (vector-ref chars e) #\}) (cons (reverse acc) (+ e 1)))
                      (else (error "json-parse: malformed object"
                                   (vector-ref chars e)))))))))

        ;; [ value , … ] → vector, in source order. K is just past the `[`.
        (define (parse-array k)
          (let ((k (skip-ws k)))
            (if (and (< k n) (char=? (vector-ref chars k) #\]))
                (cons #() (+ k 1))
                (let loop ((k k) (acc '()))
                  (let* ((vv  (parse-value k))
                         (e   (skip-ws (cdr vv)))
                         (acc (cons (car vv) acc)))
                    (cond
                      ((>= e n) (error "json-parse: malformed array" 'end-of-input))
                      ((char=? (vector-ref chars e) #\,) (loop (+ e 1) acc))
                      ((char=? (vector-ref chars e) #\])
                       (cons (list->vector (reverse acc)) (+ e 1)))
                      (else (error "json-parse: malformed array"
                                   (vector-ref chars e)))))))))

        ;; K is the index just past the opening quote. The scan touches each
        ;; character once and conses nothing: on reaching the closing quote
        ;; the literal is lifted out whole by `vector->string`.
        ;;
        ;; The end-of-input clause is load-bearing, not defensive: the `else`
        ;; branch advances on ANY character, so without it an unterminated
        ;; literal spins forever instead of raising. Every other scanner here
        ;; is already bounded (skip-ws and parse-number test `j < n`; the
        ;; object and array scanners test it explicitly), so this is the one
        ;; loop in the reader that could run away.
        ;;
        ;; A truncated payload is not hypothetical: json-parse's callers feed
        ;; it whatever a CLI printed, and (modaliser wms paneru)'s parse runs
        ;; at come-to-rest — on the main thread, between a keypress and the
        ;; next one. Raising degrades (callers already wrap this in `guard`);
        ;; spinning does not.
        (define (parse-string k)
          (let scan ((j k))
            (if (>= j n)
                (error "json-parse: unterminated string")
                (let ((c (vector-ref chars j)))
                  (cond
                    ((char=? c #\") (cons (vector->string chars k j) (+ j 1)))
                    ;; One backslash anywhere in the literal and the whole
                    ;; thing is re-read character at a time — the escape
                    ;; decoding has to build a string that is not a substring
                    ;; of the source. Rare enough in practice (paneru and
                    ;; herdr payloads carry none) that the re-scan is cheaper
                    ;; than making the fast path carry the machinery.
                    ((char=? c #\\) (parse-escaped-string k))
                    (else (scan (+ j 1))))))))

        (define (parse-escaped-string k)
          (let loop ((j k) (acc '()))
            (if (>= j n)
                (error "json-parse: unterminated string")
                (let ((c (vector-ref chars j)))
                  (cond
                    ((char=? c #\") (cons (list->string (reverse acc)) (+ j 1)))
                    ((char=? c #\\)
                     ;; Bounds-check before reading the escape character.
                     ;; `vector-ref` past the end raises a HOST range error —
                     ;; exactly as `string-ref` did before it — and that is not
                     ;; the guardable kind, which is the one thing every
                     ;; malformed-input path here must avoid. Moving to a
                     ;; vector changed the speed, not this hazard.
                     (if (>= (+ j 1) n)
                         (error "json-parse: unterminated string")
                         (let ((e (vector-ref chars (+ j 1))))
                           (cond
                             ((char=? e #\") (loop (+ j 2) (cons #\" acc)))
                             ((char=? e #\\) (loop (+ j 2) (cons #\\ acc)))
                             ((char=? e #\/) (loop (+ j 2) (cons #\/ acc)))
                             ((char=? e #\b) (loop (+ j 2) (cons #\x8 acc)))
                             ((char=? e #\f) (loop (+ j 2) (cons #\xc acc)))
                             ((char=? e #\n) (loop (+ j 2) (cons #\newline acc)))
                             ((char=? e #\r) (loop (+ j 2) (cons #\return acc)))
                             ((char=? e #\t) (loop (+ j 2) (cons #\tab acc)))
                             ((char=? e #\u)
                              (if (> (+ j 6) n)
                                  (error "json-parse: unterminated string")
                                  (let ((hex (string->number
                                               (vector->string chars (+ j 2) (+ j 6)) 16)))
                                    (if (number? hex)
                                        (loop (+ j 6) (cons (integer->char hex) acc))
                                        (error "json-parse: bad escape" #\u)))))
                             (else (error "json-parse: bad escape" e))))))
                    (else (loop (+ j 1) (cons c acc))))))))

        (define (number-char? c)
          (or (char-numeric? c)
              (char=? c #\-) (char=? c #\+)
              (char=? c #\.) (char=? c #\e) (char=? c #\E)))

        ;; parse-value falls through to here for ANY character that does not
        ;; start an object, array, string or literal — so this is where every
        ;; piece of non-JSON input lands, not just a bad number. Shell noise
        ;; ("paneru: command not found") arrives with the cursor on a
        ;; character that consumes no number token at all; empty output never
        ;; reaches here, having already been caught by parse-value's own
        ;; end-of-input clause.
        ;;
        ;; The empty-token case is checked BEFORE `string->number` sees it,
        ;; deliberately: LispKit's `string->number` raises a type error on an
        ;; empty string rather than answering #f, and that error is not the
        ;; guardable kind — it escapes the `(guard (e (#t #f)) …)` every caller
        ;; wraps this in and reaches the host as a failed evaluation. Raising
        ;; our own `error` instead keeps ALL malformed input on one guardable
        ;; path, which is what lets a caller degrade to no data (ADR-0017's
        ;; empty-output shape) instead of breaking a leader press.
        (define (parse-number k)
          (let loop ((j k))
            (if (and (< j n) (number-char? (vector-ref chars j)))
                (loop (+ j 1))
                (if (= j k)
                    (error "json-parse: expected a value" (vector-ref chars k))
                    (let* ((tok (vector->string chars k j))
                           (num (string->number tok)))
                      (if (number? num)
                          (cons num j)
                          (error "json-parse: malformed number" tok)))))))

        ;; Trailing text after the first complete value is ignored, exactly
        ;; as it always was — a CLI that prints a JSON line and then a
        ;; newline or a warning still reads.
        ;; After the internal defines, before the scan: R7RS bodies take
        ;; their definitions first, so the counter cannot sit next to the
        ;; `n` it reports.
        (instrument-sample! 'json-parse str n)
        (car (parse-value 0))))

    ;; ─── Writer ─────────────────────────────────────────────────────
    ;;
    ;; json-parse's mirror over the same representation, so a socket-API
    ;; backend can build a request line without rolling its own encoder —
    ;; the ad-hoc-per-backend outcome this library exists to prevent.
    ;;
    ;; Objects are emitted in alist order rather than sorted, which makes a
    ;; request line deterministic and therefore assertable in a test.
    ;; Output is compact (no spaces): these lines go on a socket, not to a
    ;; human.
    ;;
    ;; The representation's one ambiguity is inherited, not introduced: #f
    ;; means JSON `false`, so an "absent" value must be omitted from the
    ;; alist rather than written as #f. Symbols other than `null` and any
    ;; other unsupported value raise — a caller building a request from
    ;; malformed data is a programming error, not a wire condition.
    (define (json-write value)
      (let ((out (open-output-string)))
        (write-json value out)
        (get-output-string out)))

    (define (write-json v out)
      (cond
        ((eq? v 'null)  (write-string "null" out))
        ((eq? v #t)     (write-string "true" out))
        ((eq? v #f)     (write-string "false" out))
        ((string? v)    (write-json-string v out))
        ((number? v)    (write-string (number->string v) out))
        ((vector? v)    (write-json-array v out))
        ;; '() is the empty OBJECT (parse-object's result), not an empty
        ;; array — #() is the empty array. Both directions agree.
        ((null? v)      (write-string "{}" out))
        ((pair? v)      (write-json-object v out))
        (else (error "json-write: unsupported value" v))))

    (define (write-json-array vec out)
      (write-char #\[ out)
      (let loop ((k 0))
        (when (< k (vector-length vec))
          (when (> k 0) (write-char #\, out))
          (write-json (vector-ref vec k) out)
          (loop (+ k 1))))
      (write-char #\] out))

    (define (write-json-object alist out)
      (write-char #\{ out)
      (let loop ((rest alist) (first? #t))
        (unless (null? rest)
          (let ((entry (car rest)))
            (unless (and (pair? entry) (string? (car entry)))
              (error "json-write: object entry is not a (string . value) pair" entry))
            (unless first? (write-char #\, out))
            (write-json-string (car entry) out)
            (write-char #\: out)
            (write-json (cdr entry) out)
            (loop (cdr rest) #f))))
      (write-char #\} out))

    ;; Escapes exactly what JSON requires: the two structural characters
    ;; (" and \) and every control character below U+0020. Everything else
    ;; — including `/` and non-ASCII — goes out verbatim, which parse-string
    ;; reads back unchanged. The five short forms are used where they exist
    ;; because they are what a human debugging a captured line expects.
    ;;
    ;; Scans the vector, not the string, for the reason json-parse does: the
    ;; `(< k (string-length s))` + `(string-ref s k)` shape is Θ(n) per
    ;; character in LispKit and so Θ(n²) per scan. `measure-hot-scan-k2` found
    ;; this site cold on a leader press (35 calls, 249 characters in total),
    ;; so this is not the fix that mattered — it is the same cliff removed
    ;; while it is still cheap to remove, because the writer's inputs are
    ;; whatever a caller puts in a request and nothing bounds them.
    (define (write-json-string s out)
      (let* ((chars (string->vector s))
             (len   (vector-length chars)))
        (instrument-sample! 'write-json-string s len)
        (write-char #\" out)
        (let loop ((k 0))
          (when (< k len)
            (let* ((c (vector-ref chars k))
                   (n (char->integer c)))
              (cond
                ((char=? c #\")      (write-string "\\\"" out))
                ((char=? c #\\)      (write-string "\\\\" out))
                ((char=? c #\newline)(write-string "\\n" out))
                ((char=? c #\return) (write-string "\\r" out))
                ((char=? c #\tab)    (write-string "\\t" out))
                ((= n 8)             (write-string "\\b" out))
                ((= n 12)            (write-string "\\f" out))
                ((< n 32)            (write-string (unicode-escape n) out))
                (else                (write-char c out))))
            (loop (+ k 1))))
        (write-char #\" out)))

    ;; \u00XX — control codes only, so two hex digits always suffice and
    ;; the leading "00" is a constant.
    (define (unicode-escape n)
      (let ((hex "0123456789abcdef"))
        (string-append "\\u00"
                       (string (string-ref hex (quotient n 16))
                               (string-ref hex (remainder n 16))))))))
