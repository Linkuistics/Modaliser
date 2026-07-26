;; (modaliser muxes herdr-socket) — how Modaliser talks to herdr (ADR-0020):
;; newline-delimited JSON-RPC over herdr's Unix socket, one
;; {"id","method","params"} request per connection. herdr is socket-native —
;; its CLI is a thin wrapper over this same socket — so this is the correct
;; integration boundary, not a workaround. The other muxes (tmux, zellij) are
;; genuinely CLI-native and stay on the CLI; that divergence is justified by
;; herdr's nature, not adopted for uniformity.
;;
;; This library exists SEPARATELY from (modaliser muxes herdr) because two
;; other libraries need the same transport and cannot reach it through the mux
;; backend: (modaliser muxes herdr) already imports (modaliser blocks
;; herdr-list) for the chip-paint pipeline, so a herdr-list → muxes/herdr
;; import would close a cycle. Everything about *how to reach herdr* lives
;; here; what to SAY to herdr stays with each caller.
;;
;; Connect-per-request is the model: herdr closes the connection after one
;; response, so every call is connect → one line out → one line back → close.
;; No pool, no keep-alive, and no id correlation to track (one request per
;; connection is trivially one-to-one). `unix-socket-request` owns the newline
;; framing in both directions, so nothing here appends or strips a terminator.

(define-library (modaliser muxes herdr-socket)
  (export ;; The socket path this transport dials, and the host-side policy
          ;; that resolves one. The parameter's default is #f — "no herdr
          ;; socket configured" — and the HOST installs the resolved path at
          ;; bootstrap (root.scm), exactly as it installs (modaliser fsm)'s
          ;; arity predicates and (modaliser web-search)'s chooser push. See
          ;; the definitions below for why the safe value is the default.
          current-herdr-socket-path
          herdr-default-socket-path
          ;; The two transports. Exported so a test can exercise the REAL
          ;; envelope/parse/error path — stubbing the query seam below would
          ;; otherwise leave the transports themselves uncovered.
          ;;   (herdr-socket-request method params) → parsed envelope | #f
          ;;   (herdr-socket-send    method params) → #t | #f  (reply unread)
          herdr-socket-request
          herdr-socket-send
          ;; The ONE query seam, shared by every herdr reader in the tree
          ;; (list-block-query-cutover-k32): (modaliser muxes herdr)'s
          ;; detection/jump/ring queries, (modaliser blocks herdr-list)'s five
          ;; live lists and two chip-geometry queries, and (modaliser blocks
          ;; herdr-jump-legend)'s three name lookups. It was two parallel
          ;; parameters while the list block shelled out on its own; once both
          ;; spoke (method params) to the same socket they were the same
          ;; operation, so they are one — a test stubs herdr's reads once.
          current-herdr-query-runner
          herdr-query)
  (import (scheme base)
          ;; get-environment-variable, for the herdr socket path. R7RS, so
          ;; portable-contract-clean even though LispKit implements it
          ;; natively — no new native surface needed for path resolution.
          (only (scheme process-context) get-environment-variable)
          (modaliser util)
          (modaliser json)
          ;; The native surface the socket transport needs (ADR-0020):
          ;;   (unix-socket-request path line timeout-ms) → reply-line | #f
          ;;   (unix-socket-send    path line timeout-ms) → #t | #f
          ;; the second for the ops whose reply cannot arrive promptly (see
          ;; the send seam in (modaliser muxes herdr)). Swift owns the AF_UNIX
          ;; round-trip and knows nothing of herdr; the envelope, parsing and
          ;; error mapping are all Scheme, here.
          (modaliser unix-socket))
  (begin

    ;; Where herdr's socket lives, as a policy — resolved on demand, never
    ;; at load time.
    ;;
    ;; $HERDR_SOCKET_PATH is exported into herdr's own panes, but
    ;; GUI-launched Modaliser inherits a stripped environment and will not
    ;; see it — the same fact ADR-0017's PATH derivation exists for — so
    ;; the fallback below is the production path in practice, and the env
    ;; var only wins when Modaliser is run from a shell inside herdr. An
    ;; unset HOME yields a path that cannot exist, and the transport then
    ;; degrades to #f exactly as an unreachable socket does.
    (define (herdr-default-socket-path)
      (or (get-environment-variable "HERDR_SOCKET_PATH")
          (string-append (or (get-environment-variable "HOME") "")
                         "/.config/herdr/herdr.sock")))

    ;; The socket path this transport dials. **#f — no herdr socket
    ;; configured — is the default, and the host installs the real one**
    ;; (`root.scm`: `(current-herdr-socket-path (herdr-default-socket-path))`),
    ;; the same shape as (modaliser fsm)'s arity predicates and (modaliser
    ;; web-search)'s chooser push: a portable library ships an inert default
    ;; and the host wires reality in at bootstrap.
    ;;
    ;; The inert default is load-bearing, not tidiness. Resolving the live
    ;; path here — at library load, off the process environment — made every
    ;; herdr caller live the instant this library was imported, including
    ;; inside `swift test`. An audit at test-live-herdr-contact-k35 found
    ;; nineteen requests reaching the developer's own running herdr in one
    ;; green run: not just reads, but `pane.focus_direction`, `pane.focus`,
    ;; `workspace.focus` and `pane.swap` — the last of which rearranges a
    ;; live pane layout. Most came from tests with no herdr-I/O intent at all
    ;; (backend-record shape, the detection chain walk, a key-walk re-arm),
    ;; which is why stubbing the seams test-by-test could not have held: the
    ;; tests that leak are the ones with no reason to think about sockets.
    ;;
    ;; With the safe value as the default, a bare `SchemeEngine()` — which is
    ;; every test — cannot reach a live herdr at all; only the app bootstrap
    ;; makes the transport live (feedback_no_live_env_mutation_in_tests).
    ;;
    ;; It stays a parameter so a test can point the REAL transport at a
    ;; throwaway responder socket and assert the bytes it puts on the wire.
    (define current-herdr-socket-path (make-parameter #f))

    ;; Wall-clock bound on a whole round-trip. A local AF_UNIX exchange with
    ;; a healthy herdr is sub-millisecond, so a second is ~1000x headroom;
    ;; what the number actually buys is a ceiling on how long a WEDGED
    ;; server can block the eval thread — and with it the keyboard tap
    ;; (ADR-0014's stalled-tap failure mode). The shell-out this replaces
    ;; had no bound at all, so any finite number is strictly better.
    (define herdr-socket-timeout-ms 1000)

    ;; The JSON-RPC envelope, built in one place for both transports below.
    ;; `json-write` owns escaping, so every param of every method — user-typed
    ;; labels included — is escaped identically and the shell-era `sq-escape`
    ;; single-quoting has no successor.
    (define (herdr-request-line method params)
      (json-write (list (cons "id" "modaliser")
                        (cons "method" method)
                        (cons "params" params))))

    ;; METHOD + PARAMS (an alist json-write renders as the params object) →
    ;; the parsed response envelope, or #f.
    ;;
    ;; **`#f` means herdr did not answer** — unreachable socket, timeout, or a
    ;; reply that would not parse — and nothing raises: a leader press must not
    ;; raise.
    ;;
    ;; A structured `{"error":…}` reply is NOT `#f`: herdr answered, and said
    ;; something specific. It comes back as the envelope, logged. Collapsing it
    ;; into `#f` would conflate "no answer" with "an answer I don't like", and
    ;; the difference is load-bearing for anything that reports herdr's state
    ;; to the user: `worktree.list` returns `not_git_worktree` whenever the
    ;; focused workspace is not inside a git work tree — an ordinary, expected
    ;; condition that must not read as "herdr is not responding". Callers need
    ;; no branch for it: every one of them reads `(json-ref j "result")`, which
    ;; an error envelope has not got, and `json-ref` is total — so an error
    ;; degrades to exactly the empty/`#f` each caller already handles.
    ;;
    ;; Either way the reason is logged, unlike the `2>/dev/null` this replaces
    ;; (which is precisely what hid the `agent_not_found` behind the
    ;; pane-switching regression).
    ;;
    ;; On success the envelope is returned WHOLE, so callers keep reading
    ;; `(json-ref j "result")` exactly as they did from CLI stdout: the
    ;; socket reply and the CLI's printed output are the same document.
    ;; The one place the unconfigured default is turned into an outcome.
    ;; Both transports below refuse to dial when no path is installed, and
    ;; say so loudly — "herdr did not answer" is the right verdict for a
    ;; transport with nowhere to dial, and a silent #f would leave a host
    ;; that forgot the install (root.scm) looking like an absent herdr.
    ;; One `display`, not `log`'s usual arg-per-fragment: this is the message
    ;; most likely to repeat (it fires for every herdr call in a process that
    ;; never ran the host bootstrap, i.e. the whole test suite), and the host
    ;; port emits one line per fragment.
    (define (herdr-socket-unconfigured method)
      (log (string-append
             "herdr: " method
             " — no socket configured; the host installs"
             " current-herdr-socket-path at bootstrap"))
      #f)

    (define (herdr-socket-request method params)
      (if (not (string? (current-herdr-socket-path)))
          (herdr-socket-unconfigured method)
      (let ((reply (unix-socket-request
                     (current-herdr-socket-path)
                     (herdr-request-line method params)
                     herdr-socket-timeout-ms)))
        (if (not (string? reply))
            #f                          ; the primitive already logged why
            (let ((parsed (guard (e (#t #f)) (json-parse reply))))
              (cond
                ((not parsed)
                 (log "herdr: " method " — unparseable reply: " reply)
                 #f)
                ((json-ref parsed "error")
                 => (lambda (err)
                      (log "herdr: " method " failed: "
                           (or (json-ref err "code") "?")
                           " — " (or (json-ref err "message") ""))
                      parsed))
                (else parsed)))))))

    ;; The no-reply sibling: connect, send, close, never read. For the ops
    ;; whose answer does not arrive promptly — or at all — so that waiting on
    ;; it would stall the eval thread for the full timeout as a matter of
    ;; routine (ADR-0014's hazard). Which ops those are, and why abandoning
    ;; the reply does not abandon the op, is the send seam's business — see
    ;; `herdr-cmd-send` in (modaliser muxes herdr).
    (define (herdr-socket-send method params)
      (if (not (string? (current-herdr-socket-path)))
          (herdr-socket-unconfigured method)
          (unix-socket-send (current-herdr-socket-path)
                            (herdr-request-line method params)
                            herdr-socket-timeout-ms)))

    ;; ─── The query seam ─────────────────────────────────────────────
    ;;
    ;; Every herdr READ in the tree goes through here, so a test hands back
    ;; canned JSON once and no query reaches a live herdr session
    ;; (feedback_no_live_env_mutation_in_tests). Mirrors
    ;; `current-frontmost-bundle-id` in (modaliser terminal).
    ;;
    ;; Reads need no seam of their own beyond this parameter: a #f is simply
    ;; propagated, and each caller degrades it in its own terms (no detection,
    ;; no jump targets, an "unresponsive" row in a live list). herdr's health
    ;; needs no separate probe either — see the note in (modaliser muxes
    ;; herdr)'s backend record on why herdr carries no tool-name.
    (define current-herdr-query-runner
      (make-parameter herdr-socket-request))

    (define (herdr-query method params)
      ((current-herdr-query-runner) method params))))
