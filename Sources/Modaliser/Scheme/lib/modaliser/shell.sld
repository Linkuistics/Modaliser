;; (modaliser shell) — the seam every backend shells out through (ADR-0023).
;;
;; Spawning a subprocess is the widest side effect in the tree: it is how
;; Modaliser tells the user's *actual running* tmux to move a pane, its actual
;; iTerm2 to switch session, its actual nvim to accept keystrokes. The native
;; capability to do that lives in the modaliser shell-native library; NOTHING
;; in this portable tree imports it. What the tree imports is this library, whose
;; `run-shell` is a parameter dispatch with **no runner installed by default**
;; — so an unbootstrapped engine cannot reach a single tool, however many
;; `run-shell` calls it makes.
;;
;; The live runners are installed by the host, first thing in `root.scm`:
;;
;;   (current-shell-runner       run-shell-native)
;;   (current-shell-async-runner run-shell-async-native)
;;
;; the same shape as (modaliser fsm)'s arity predicates, (modaliser
;; web-search)'s chooser push, and (modaliser muxes herdr-socket)'s socket path
;; — a portable library ships an inert default and the host wires reality in at
;; bootstrap. `swift test` constructs a bare `SchemeEngine()`, which never runs
;; `root.scm`, so no test can reach a live tool. That is structural, not
;; per-test discipline: the audit at test-live-backend-contact-k38 found the
;; leaking calls came overwhelmingly from tests with no shell-out *intent* —
;; a backend-record shape check, a detection-chain walk, a library load — which
;; is exactly the set that would never think to stub a runner.
;;
;; Degradation is deliberately the one every caller already handles: empty
;; output. Backends `2>/dev/null` their commands and read `""` as "nothing
;; running" (ADR-0017), so an uninstalled runner degrades along the same path
;; as a missing binary — no new failure mode reaches a leader press.

(define-library (modaliser shell)
  (export ;; What the backends call. Same signatures as the native
          ;; procedures they dispatch to, so a caller reads identically
          ;; whether or not it knows a seam is here.
          run-shell
          run-shell-async
          ;; The install points. `root.scm` sets both at bootstrap; a test
          ;; may set either to a canned runner to assert on the command it
          ;; would have run.
          current-shell-runner
          current-shell-async-runner)
  ;; Nothing native, by design. This library holds the *decision* to spawn;
  ;; the *capability* stays in the native shell library, which only the host
  ;; bootstrap imports — see scripts/check-portable-surface.sh, which fails
  ;; the build on any parenthesised reference to it from this tree (so prose
  ;; here must name it as above, exactly as the portability rule requires of
  ;; the LispKit libraries).
  (import (scheme base))
  (begin

    ;; (runner command) → stdout string. #f = no runner installed.
    (define current-shell-runner (make-parameter #f))

    ;; (runner command callback ['timeout seconds]) → void, callback
    ;; receiving (exit-code stdout stderr). #f = no runner installed.
    (define current-shell-async-runner (make-parameter #f))

    ;; Run COMMAND, returning its stdout — or "" when no runner is
    ;; installed. Callers already treat "" as "the tool told us nothing",
    ;; so the inert path needs no handling anywhere.
    (define (run-shell command)
      (let ((runner (current-shell-runner)))
        (if runner (runner command) "")))

    ;; Run COMMAND in the background, calling CALLBACK with (exit-code
    ;; stdout stderr). With no runner installed the callback still fires —
    ;; with the same (-1 "" reason) shape the native runner uses for a
    ;; timeout or a failed spawn — so a caller waiting on a dialog answer
    ;; is answered rather than left hanging (ADR-0014: never block).
    (define (run-shell-async command callback . opts)
      (let ((runner (current-shell-async-runner)))
        (if runner
            (apply runner command callback opts)
            (callback -1 "" "no shell runner installed"))))))
