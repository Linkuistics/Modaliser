;; (modaliser http) — the seam every outward fetch in the tree passes through
;; (ADR-0023).
;;
;; Fetching a URL leaves the machine. Unlike a shell-out, which reaches the
;; user's own running tools, this reaches a *third party*: an endpoint that may
;; be slow, rate-limiting, down, or watching who asks. The native capability to
;; do it lives in the native HTTP library; NOTHING in this portable tree imports
;; that. What the tree imports is this library, whose `http-get` is a parameter
;; dispatch with **no runner installed by default** — so an unbootstrapped
;; engine cannot reach one endpoint, however many `http-get` calls it makes.
;;
;; The live runner is installed by the host, in `root.scm`:
;;
;;   (current-http-runner http-get-native)
;;
;; the same shape as the shell seam, (modaliser fsm)'s arity predicates,
;; (modaliser web-search)'s chooser push, and (modaliser muxes herdr-socket)'s
;; socket path — a portable library ships an inert default and the host wires
;; reality in at bootstrap. `swift test` constructs a bare `SchemeEngine()`,
;; which never runs `root.scm`, so no test can reach the public internet. That
;; is structural, not per-test discipline: before this seam existed, one green
;; run fetched httpbin.org — and the only thing standing between the suite and
;; Google Suggest was that no test had yet called `web-search-handler` with a
;; three-character query (test-live-network-contact-k51).
;;
;; Degradation is deliberately the value the one caller already handles: `#f`.
;; `(modaliser web-search)` reads a `#f` response as "network error — keep
;; showing just the pinned suggestion", so an uninstalled runner degrades along
;; the same path as an endpoint that is down. No new failure mode reaches a
;; leader press.
;;
;; Unlike the shell seam, this install is NOT order-sensitive: no library
;; derives anything from an HTTP fetch at import time, and the one consumer
;; captures this library's `http-get` — which dispatches at call time — rather
;; than the runner behind it.

(define-library (modaliser http)
  (export ;; What the tree calls. Same signature as the native procedure it
          ;; dispatches to, so a caller reads identically whether or not it
          ;; knows a seam is here.
          http-get
          ;; The install point. `root.scm` sets it at bootstrap; a test may
          ;; set or `parameterize` a canned runner to assert on the URL it
          ;; would have fetched, or to answer with a canned body.
          current-http-runner)
  ;; Nothing native, by design. This library holds the *decision* to fetch;
  ;; the *capability* stays in the native HTTP library, which only the host
  ;; bootstrap imports — see scripts/check-portable-surface.sh, which fails
  ;; the build on any parenthesised reference to a native library from this
  ;; tree (so prose here must name it as above, exactly as the portability
  ;; rule requires of the LispKit libraries).
  (import (scheme base))
  (begin

    ;; (runner url callback) → void, callback receiving the response body
    ;; string or #f. #f = no runner installed.
    (define current-http-runner (make-parameter #f))

    ;; Fetch URL, calling CALLBACK with the response body — or with #f when
    ;; no runner is installed. The callback fires either way, so a caller
    ;; awaiting a response is answered rather than stranded (ADR-0014: never
    ;; block), and #f is already its "the endpoint told us nothing" path.
    (define (http-get url callback)
      (let ((runner (current-http-runner)))
        (if runner
            (runner url callback)
            (callback #f))))))
