;; (modaliser instrument) — the leader-press stopwatch and string-scan tripwire.
;;
;; Why this exists. A leader press with herdr focused stalls for ~27 s, and a
;; `sample` profile of the installed app puts 97 % of that inside LispKit's
;; `string-ref` under `fireHotkeyHandler`. That names the *cost class* but not
;; the *call site*: `string-ref` is Θ(n) per character (it bridges the whole
;; NSMutableString on every call), so any index-based scan in this tree is a
;; candidate and deduction had already eliminated the obvious ones. This
;; library is the reading that ends the guessing.
;;
;; Two instruments, deliberately different in cost:
;;
;;   `instrument-span`  — a stopwatch around a COARSE stage (a leader-press phase, a
;;     socket round-trip, a parse). It calls `current-jiffy` twice and emits one
;;     line, so it must never wrap anything called per character.
;;
;;   `instrument-tally!` / `instrument-sample!` — a counter for a HOT primitive. No clock
;;     at all: a scan that runs a million times can afford an increment but not
;;     two `current-jiffy` calls, and the timing it would report is already
;;     bracketed by the enclosing span. `instrument-sample!` adds the tripwire that
;;     actually names the string: the first time a site is handed something
;;     larger than every string it has seen before AND past `instrument-threshold`,
;;     it logs the length and a short prefix. A prefix identifies a payload the
;;     way a length never can — 380 000 chars beginning `{"result":{"panes":`
;;     is a herdr reply; the same length beginning `.chip{position:` is CSS.
;;
;; **Length is always passed in, never measured here.** `string-length` bridges
;; the whole string too, so an instrument that called it would add a second Θ(n) cost
;; to the very loop it is measuring — turning the instrument into part of the
;; disease. Every call site already has the length in hand (that is why it is
;; scanning), so it hands it over.
;;
;; Cost when idle. `instrument-enabled?` is a parameter, and the host (`root.scm`)
;; decides. With it #f every entry point is a parameter read and a return, and
;; nothing reaches the log. `swift test` never runs `root.scm`, so the suite is
;; unaffected either way.
;;
;; Portability: (scheme …) plus the log library, which is host capability but
;; not outward reach — the same import (modaliser terminal) already makes.
;; No decisions here, only machinery (ADR-0021).

(define-library (modaliser instrument)
  (export ;; Host-installed on/off. #f by default, so an unbootstrapped
          ;; engine — every test — is silent.
          instrument-enabled?
          ;; Below this many characters a scan is not interesting; the
          ;; press costs 27 s, so the string that matters is not 200 bytes.
          instrument-threshold
          ;; Coarse stopwatch. Returns THUNK's value.
          instrument-span
          ;; Hot-primitive counters. No clock; LEN is supplied by the caller.
          instrument-tally!
          instrument-sample!
          ;; Free-form marker line, and the epoch controls.
          instrument-note
          instrument-reset!
          instrument-report!
          ;; The counters, readable. Exported for one reason: without it the
          ;; only way to check that this library counts correctly is to read
          ;; the unified log by eye — i.e. to trust the instrument that is
          ;; itself the thing under test. `(instrument-site 'json-parse)` →
          ;; #(calls total-chars max-chars), or #f for a site never touched.
          instrument-site)
  (import (scheme base)
          (scheme time)
          (scheme write)
          (modaliser log))
  (begin

    (define instrument-enabled? (make-parameter #f))
    (define instrument-threshold (make-parameter 4096))

    ;; ─── The site table ─────────────────────────────────────────────
    ;;
    ;; site-symbol → #(calls total-len max-len). A vector, not a list of
    ;; three set!-able variables, because the update is per call on the
    ;; hottest scanners in the tree: `vector-set!` is one store, where
    ;; rebuilding an alist entry would allocate on every character of every
    ;; scan. The table itself is an alist because sites are ~15 and are
    ;; added once each, so `assq` never grows into a cost.
    (define %sites '())

    (define (site-cell name)
      (let ((hit (assq name %sites)))
        (if hit
            (cdr hit)
            (let ((cell (vector 0 0 0)))
              (set! %sites (cons (cons name cell) %sites))
              cell))))

    ;; A COPY, so a caller reading the counters cannot write them: the
    ;; cell is live and shared with the hot path.
    (define (instrument-site name)
      (let ((hit (assq name %sites)))
        (and hit
             (vector (vector-ref (cdr hit) 0)
                     (vector-ref (cdr hit) 1)
                     (vector-ref (cdr hit) 2)))))

    (define (bump! cell len)
      (vector-set! cell 0 (+ (vector-ref cell 0) 1))
      (vector-set! cell 1 (+ (vector-ref cell 1) len))
      (when (> len (vector-ref cell 2))
        (vector-set! cell 2 len)))

    ;; ─── Emitting ───────────────────────────────────────────────────
    ;;
    ;; `log-line` rather than (modaliser util)'s `log`: `log` is display +
    ;; newline, which lands on the context delegate's NSLog and is invisible
    ;; in the unified log from an installed .app — and an installed .app is
    ;; the only build where this measurement is valid (a debug number
    ;; misattributed this exact cost once already). Read it back with
    ;;   log show --predicate 'subsystem == "dev.antony.Modaliser"' --style compact
    (define (emit . fragments)
      (log-line
        (let loop ((rest fragments) (acc "instr:"))
          (if (null? rest)
              acc
              (loop (cdr rest)
                    (string-append
                      acc " "
                      (let ((x (car rest)))
                        (cond ((string? x) x)
                              ((symbol? x) (symbol->string x))
                              ((number? x) (number->string x))
                              (else "?")))))))))

    (define (jiffies->ms j)
      ;; Integer milliseconds. `jiffies-per-second` is a host constant, so
      ;; this stays exact — no float formatting to read past in the log.
      (let ((per (jiffies-per-second)))
        (if (and (number? per) (> per 0))
            (round (/ (* j 1000) per))
            j)))

    ;; ─── Public surface ─────────────────────────────────────────────

    (define (instrument-note . fragments)
      (when (instrument-enabled?) (apply emit fragments))
      (if #f #f))

    ;; Time THUNK and log one line. Coarse stages only.
    (define (instrument-span name thunk)
      (if (not (instrument-enabled?))
          (thunk)
          (let* ((t0 (current-jiffy))
                 (v  (thunk))
                 (dt (- (current-jiffy) t0)))
            (emit 'span name (jiffies->ms dt) "ms")
            v)))

    ;; Count one call at SITE over a string of LEN characters.
    (define (instrument-tally! name len)
      (when (instrument-enabled?) (bump! (site-cell name) len))
      (if #f #f))

    ;; As `instrument-tally!`, plus the tripwire: a new record length past the
    ;; threshold logs a prefix, so the string is named by its content and
    ;; not merely by its size. Gated on "new record" so a scanner called a
    ;; million times over the same payload logs once, not a million times.
    (define (instrument-sample! name str len)
      (when (instrument-enabled?)
        (let ((cell (site-cell name)))
          (when (and (> len (instrument-threshold))
                     (> len (vector-ref cell 2))
                     (string? str))
            (emit 'big name 'len len 'head
                  (substring str 0 (if (< len 72) len 72))))
          (bump! cell len)))
      (if #f #f))

    ;; Start an epoch: clear the table and mark the log. Called at the top
    ;; of a leader press, so every report below reads "since this press".
    (define (instrument-reset! label)
      (when (instrument-enabled?)
        (set! %sites '())
        (emit 'epoch label))
      (if #f #f))

    ;; Dump the table. Sites appear in first-touch order reversed, which is
    ;; not meaningful — read the numbers, not the order.
    (define (instrument-report! label)
      (when (instrument-enabled?)
        (emit 'report label)
        (for-each
          (lambda (entry)
            (let ((cell (cdr entry)))
              (emit '- (car entry)
                    'calls (vector-ref cell 0)
                    'total-chars (vector-ref cell 1)
                    'max-chars (vector-ref cell 2))))
          %sites)
        (emit 'end label))
      (if #f #f))))
