;; (modaliser web-search) — Google web search via chooser.
;;
;; Exposes a `google` factory whose selector spins up a dynamic chooser
;; populated from Google autocomplete suggestions, and opens the chosen
;; query in the default browser via `open-url`.
;;
;; Carved out of the old lib/web-search.scm flat-include in Phase H.
;; The dynamic-search callback needs to push results into the chooser
;; WebView, but `chooser-push-results` is defined in ui/chooser.scm —
;; still a flat include. To keep the library closed, dependency is
;; injected: the library exposes a no-op `chooser-push!` and a
;; `set-chooser-push!` setter; root.scm wires the real procedure in
;; after the chooser include has run.

(define-library (modaliser web-search)
  (export google
          web-search-handler
          web-search-on-select
          build-web-search-results
          google-suggest-url
          google-search-url
          url-encode
          parse-google-suggestions
          set-web-search-fetch!
          set-web-search-open-url!
          set-chooser-push!)
  (import (scheme base)
          (modaliser util)
          (modaliser dsl)
          (modaliser http)
          (modaliser app))
  (begin

    ;; ─── Chooser-push injection ─────────────────────────────────
    ;; chooser-push-results is defined in ui/chooser.scm (still a flat
    ;; include). root.scm calls (set-chooser-push! chooser-push-results)
    ;; after both have loaded.

    (define chooser-push! (lambda (results) #f))

    (define (set-chooser-push! proc)
      (set! chooser-push! proc))

    ;; ─── URL Encoding ───────────────────────────────────────────

    (define hex-chars "0123456789ABCDEF")

    ;; Percent-encode a single byte as a 3-character string "%XX".
    (define (percent-encode-byte b)
      (string #\%
              (string-ref hex-chars (quotient b 16))
              (string-ref hex-chars (remainder b 16))))

    ;; Percent-encode a string for use in URL query parameters.
    ;; Handles multi-byte Unicode: converts each char to UTF-8 bytes via
    ;; string->utf8, then percent-encodes each byte.
    (define (url-encode str)
      (let loop ((chars (string->list str)) (result ""))
        (if (null? chars)
          result
          (let ((c (car chars)))
            (cond
              ;; Unreserved ASCII characters pass through (RFC 3986)
              ((or (and (char>=? c #\A) (char<=? c #\Z))
                   (and (char>=? c #\a) (char<=? c #\z))
                   (and (char>=? c #\0) (char<=? c #\9))
                   (char=? c #\-) (char=? c #\_)
                   (char=? c #\.) (char=? c #\~))
               (loop (cdr chars) (string-append result (string c))))
              ;; Space -> +
              ((char=? c #\space)
               (loop (cdr chars) (string-append result "+")))
              ;; Everything else -> UTF-8 bytes -> %XX per byte
              (else
               (let* ((bv (string->utf8 (string c)))
                      (len (bytevector-length bv))
                      (encoded (let bloop ((i 0) (acc ""))
                                 (if (>= i len) acc
                                   (bloop (+ i 1)
                                          (string-append acc
                                            (percent-encode-byte
                                              (bytevector-u8-ref bv i))))))))
                 (loop (cdr chars) (string-append result encoded)))))))))

    ;; ─── URL Construction ───────────────────────────────────────

    ;; Google Suggest API URL for a query.
    (define (google-suggest-url query)
      (string-append
        "https://suggestqueries.google.com/complete/search?client=firefox&q="
        (url-encode query)))

    ;; Google Search URL for a query.
    (define (google-search-url query)
      (string-append "https://www.google.com/search?q=" (url-encode query)))

    ;; ─── Response Parsing ───────────────────────────────────────

    ;; Parse a comma-separated list of JSON strings: "str1","str2",...
    ;; Returns a list of unescaped strings.
    (define (parse-json-string-array content)
      (let ((len (string-length content)))
        (let loop ((i 0) (results '()))
          (if (>= i len)
            (reverse results)
            (let ((c (string-ref content i)))
              (cond
                ;; Skip commas and whitespace
                ((or (char=? c #\,) (char=? c #\space) (char=? c #\tab)
                     (char=? c #\newline) (char=? c #\return))
                 (loop (+ i 1) results))
                ;; Parse a quoted string
                ((char=? c #\")
                 (let parse-str ((j (+ i 1)) (chars '()))
                   (if (>= j len)
                     (reverse results)  ;; unterminated string, return what we have
                     (let ((sc (string-ref content j)))
                       (cond
                         ((char=? sc #\")
                          (loop (+ j 1) (cons (list->string (reverse chars)) results)))
                         ((char=? sc #\\)
                          (if (< (+ j 1) len)
                            (let ((esc (string-ref content (+ j 1))))
                              (cond
                                ;; \uXXXX Unicode escape (use integer 117 = 'u' to avoid #\u parse issue)
                                ((and (= (char->integer esc) 117) (<= (+ j 6) len))
                                 (let ((hex (substring content (+ j 2) (+ j 6))))
                                   (let ((cp (string->number hex 16)))
                                     (if cp
                                       (parse-str (+ j 6) (cons (integer->char cp) chars))
                                       (parse-str (+ j 2) (cons esc chars))))))
                                ;; Named escapes
                                (else
                                 (parse-str (+ j 2)
                                            (cons (cond ((char=? esc #\n) #\newline)
                                                        ((char=? esc #\t) #\tab)
                                                        ((char=? esc #\r) #\return)
                                                        (else esc))
                                                  chars)))))
                            (reverse results)))
                         (else
                          (parse-str (+ j 1) (cons sc chars))))))))
                ;; Skip anything else
                (else (loop (+ i 1) results))))))))

    ;; Parse the Google Suggest JSON response into a list of suggestion strings.
    ;; Response format: ["query",["suggestion1","suggestion2",...]]
    ;; Returns '() on parse failure.
    (define (parse-google-suggestions response)
      (let* ((len (string-length response))
             ;; Find the second '[' which starts the suggestions array
             (start (let loop ((i 0) (count 0))
                      (if (>= i len)
                        #f
                        (if (char=? (string-ref response i) #\[)
                          (if (= count 1) (+ i 1) (loop (+ i 1) (+ count 1)))
                          (loop (+ i 1) count)))))
             ;; Find the matching ']'
             (end (and start
                       (let loop ((i start) (depth 0))
                         (if (>= i len)
                           #f
                           (let ((c (string-ref response i)))
                             (cond
                               ((char=? c #\]) (if (= depth 0) i (loop (+ i 1) (- depth 1))))
                               ((char=? c #\[) (loop (+ i 1) (+ depth 1)))
                               (else (loop (+ i 1) depth)))))))))
        (if (and start end)
          (parse-json-string-array (substring response start end))
          '())))

    ;; ─── Result Building ────────────────────────────────────────

    ;; Build the chooser items list from a query and suggestions.
    ;; First item is always the pinned "Search Google for '...'" item.
    ;; Each item has 'text for display and 'search-url for the action.
    (define (build-web-search-results query suggestions)
      (let* ((pinned (list (cons 'text (string-append "Search Google for '" query "'"))
                           (cons 'search-url (google-search-url query))))
             (suggestion-items
               (map (lambda (s)
                      (list (cons 'text s)
                            (cons 'search-url (google-search-url s))))
                    suggestions)))
        (cons pinned suggestion-items)))

    ;; ─── Dynamic Search Handler ─────────────────────────────────

    ;; Generation counter for discarding stale HTTP responses.
    (define web-search-generation 0)

    ;; Minimum characters before firing an HTTP request.
    (define web-search-min-chars 3)

    ;; HTTP function (indirection allows test stubbing via
    ;; set-web-search-fetch! — `set!` from outside the library would
    ;; modify the importer's binding, not this one).
    (define web-search-fetch http-get)

    (define (set-web-search-fetch! proc)
      (set! web-search-fetch proc))

    ;; The dynamic-search callback for the Google search chooser.
    ;; Called by the chooser message handler on each search input.
    ;; Empty query (from "ready" message) resets the generation counter
    ;; to invalidate any in-flight HTTP responses from a previous session.
    (define (web-search-handler query)
      (when (= (string-length query) 0)
        (set! web-search-generation 0))
      (set! web-search-generation (+ web-search-generation 1))
      (let ((current-gen web-search-generation))
        (if (< (string-length query) web-search-min-chars)
          ;; Below threshold: show only the pinned item (no HTTP request)
          (if (> (string-length query) 0)
            (chooser-push! (build-web-search-results query '()))
            (chooser-push! '()))
          ;; At or above threshold: show pinned item immediately, then fire HTTP
          (begin
            (chooser-push! (build-web-search-results query '()))
            (web-search-fetch (google-suggest-url query)
              (lambda (response)
                ;; Discard if a newer search has been initiated
                (when (= current-gen web-search-generation)
                  (if response
                    (let ((suggestions (parse-google-suggestions response)))
                      (chooser-push! (build-web-search-results query suggestions)))
                    ;; Network error: keep showing just the pinned item
                    #f))))))))

    ;; ─── On Select ──────────────────────────────────────────────

    ;; open-url indirection (same rationale as web-search-fetch — the
    ;; library binding is captured at import time, so test stubs at the
    ;; top level can't override it without this setter).
    (define web-search-open-url open-url)

    (define (set-web-search-open-url! proc)
      (set! web-search-open-url proc))

    ;; Called when the user selects a web search result.
    ;; Opens the search URL in the default browser.
    (define (web-search-on-select item)
      (let ((url (alist-ref item 'search-url #f)))
        (when url (web-search-open-url url))))

    ;; ─── Selector factory ────────────────────────────────────────
    ;;
    ;; Returns an undecorated selector node. Bind it via the call site:
    ;;
    ;;   (import (prefix (modaliser web-search) web-search:))
    ;;   (screen 'global
    ;;     (panel "Search"
    ;;       (key "g" "Google" (web-search:google)))
    ;;     …)
    ;;
    ;; Options:
    ;;   'prompt — chooser prompt (default "Search Google…")
    (define (google . opts)
      (let* ((alist  (apply props->alist opts))
             (prompt (alist-ref alist 'prompt "Search Google…")))
        (selector
          'prompt prompt
          'dynamic-search web-search-handler
          'on-select web-search-on-select)))))
