;; (modaliser handoff) — the Handoff: (modaliser:start! config), the
;; one effectful moment of the configuration-value model (ADR-0018,
;; docs/specs/configuration-value.md "The Handoff").
;;
;; Everything upstream — the constructors, `configuration`, the pure
;; lower — is inspectable, printable data; this library is where that
;; value meets the engine, exactly once:
;;
;;   1. run the pure lower + closure validation (lower-with-activation:
;;      context-reference closure, derived step-in decoration, the
;;      closed-graph check);
;;   2. install the result into the engine — the graph
;;      (fsm-install-graph!), the backend records (the terminal
;;      façade's registry via terminal-install-backends!, whose
;;      backend-install tool probe fires per
;;      ADR-0017), and the settings (overlay delay). The screen set and
;;      the Terminal context map need no separate installed form: they
;;      are READ from the installed value at every leader press;
;;   3. arm the leaders from the installed value (register-hotkey!,
;;      each handler resolving through resolve-activation against the
;;      installed value and the live detection chain).
;;
;; ONE-SHOT: a second call errors ('already-started) — reload is
;; relaunch. Validation is front-loaded so every failure happens BEFORE
;; the first effect: a config that fails leaves the engine cleanly
;; empty — the app's config-error state is DEFINED as "nothing was ever
;; installed" — and a corrected retry on the same engine is allowed,
;; because the one-shot latch sets only on success.


(define-library (modaliser handoff)
  (export modaliser:start!
          modaliser:configuration
          make-configured-leader-handler)
  (import (scheme base)
          (modaliser configuration)
          (modaliser activation)
          (modaliser fsm)
          (modaliser terminal)
          (modaliser keyboard)
          ;; Only the modifier-mask conversion: leader specs carry
          ;; modifiers as authored-altitude symbols; the mask is the
          ;; engine's business at arming (configuration.sld `leader`).
          (only (modaliser dsl) modifier-symbols->mask)
          ;; The press stopwatch (measure-hot-scan-k2). This handler IS the
          ;; `fireHotkeyHandler` the profile attributed 97 % of a 27 s stall
          ;; to, and it has exactly four stages — so bracketing them here
          ;; turns "somewhere in the press" into one named stage before any
          ;; finer instrument has to be read.
          (only (modaliser instrument)
                instrument-span instrument-reset! instrument-report!))
  (begin

;; ─── The installed value ─────────────────────────────────────────────

;; The one-shot cell: #f until the first successful handoff, the
;; installed Configuration value thereafter — written once, read-only
;; (the residual mutable engine internals are enumerated in the spec;
;; the value itself is not among them).
(define %installed-configuration #f)

;; (modaliser:configuration) → the installed value, or #f before (or
;; after a failed) handoff. #f IS the config-error state: nothing was
;; ever installed.
(define (modaliser:configuration) %installed-configuration)

;; ─── The configured leader path ──────────────────────────────────────

;; (make-configured-leader-handler leader-kc mode) → a 0-arg hotkey
;; handler. Toggle discipline (an open chooser closes;
;; an active modal exits; only an idle press activates), but activation
;; resolves through resolve-activation against the INSTALLED value and
;; the LIVE detection chain instead of the entry table. The chain is
;; probed only for a 'local press — the global screen is never
;; terminal-like, so a 'global press never pays for the walk. The
;; frontmost bundle-id comes from current-frontmost-bundle-id, the same
;; (parameterizable) source the chain walk itself reads, so activation
;; and detection always agree on the host app.
(define (make-configured-leader-handler leader-kc mode)
  (unless (memq mode '(global local))
    (error "make-configured-leader-handler: mode must be 'global or 'local"
           'invalid-leader-mode mode))
  (lambda ()
    (cond
      ((chooser-open?) (close-chooser))
      ((fsm-active?)   (modal-exit))
      ((not %installed-configuration) (if #f #f))
      (else
       ;; The epoch starts here, so every counter the report prints is
       ;; "since this press" — a tally accumulated across a whole session
       ;; would answer a question nobody asked.
       (instrument-reset! 'leader-press)
       (let* ((bundle-id (instrument-span 'leader/frontmost-bundle-id
                           (lambda () ((current-frontmost-bundle-id)))))
              (chain     (instrument-span 'leader/focused-terminal-path
                           (lambda ()
                             (if (eq? mode 'global) '() (focused-terminal-path)))))
              (landing   (instrument-span 'leader/resolve-activation
                           (lambda ()
                             (resolve-activation mode bundle-id chain
                                                 %installed-configuration)))))
         (when landing
           (instrument-span 'leader/modal-activate!
             (lambda ()
               (modal-activate! (cdr (assq 'root landing))
                                (cdr (assq 'stack landing))
                                leader-kc))))
         ;; Reported even when nothing landed: "the press cost 27 s and
         ;; activated nothing" is itself a finding.
         (instrument-report! 'leader-press))))))

;; ─── Pre-effect validation ───────────────────────────────────────────
;;
;; Runs BEFORE the first effect, so any failure leaves the engine
;; untouched. Constructor-built contributions are already well-formed;
;; these checks catch hand-built ones, with the merge's decodable-error
;; discipline (a symbolic code + structured details as irritants).

(define (all? pred lst)
  (or (null? lst) (and (pred (car lst)) (all? pred (cdr lst)))))

(define (alist-shaped? x) (and (list? x) (all? pair? x)))

(define (check-backend-records config)
  (for-each
    (lambda (kv)
      (unless (terminal-backend? (cdr kv))
        (error "modaliser:start!: backend contribution is not a terminal-backend record"
               'invalid-backend-record (car kv))))
    (configuration-backends config)))

(define (check-overlay-delay delay)
  (when delay
    (unless (and (real? delay) (>= delay 0))
      (error "modaliser:start!: 'overlay-delay must be a non-negative number"
             'invalid-overlay-delay delay))))

(define (leader-spec-field spec key)
  (let ((kv (assq key spec)))
    (and kv (cdr kv))))

(define (check-leader-specs specs)
  (unless (list? specs)
    (error "modaliser:start!: 'leaders must be a list of leader specs"
           'invalid-leader-spec specs))
  (for-each
    (lambda (spec)
      (unless (and (alist-shaped? spec)
                   (memq (leader-spec-field spec 'mode) '(global local))
                   ;; The upper bound matters: a keycode is a host
                   ;; CGKeyCode (16-bit), and arming is an EFFECT — a
                   ;; value only the native layer would reject (e.g. a
                   ;; bignum) must fail HERE, in the pre-effect phase,
                   ;; or a mid-arming error would strand a half-installed
                   ;; engine behind the one-shot latch.
                   (let ((kc (leader-spec-field spec 'keycode)))
                     (and (integer? kc) (exact? kc) (>= kc 0) (< kc 65536)))
                   (let ((mods (leader-spec-field spec 'modifiers)))
                     (or (not mods) (and (list? mods) (all? symbol? mods))))
                   (let ((arm (leader-spec-field spec 'arm-when-frontmost)))
                     (or (not arm) (and (list? arm) (all? string? arm)))))
        (error "modaliser:start!: malformed leader spec"
               'invalid-leader-spec spec)))
    specs))

;; ─── Arming ──────────────────────────────────────────────────────────

;; One register-hotkey! per (leader …) spec, each handler closing over
;; its own keycode and mode.
(define (arm-leader! spec)
  (let ((kc   (leader-spec-field spec 'keycode))
        (mode (leader-spec-field spec 'mode))
        (mods (or (leader-spec-field spec 'modifiers) '()))
        (arm  (or (leader-spec-field spec 'arm-when-frontmost) '())))
    (register-hotkey! kc
                      (make-configured-leader-handler kc mode)
                      (modifier-symbols->mask mods)
                      arm)))

;; ─── The handoff ─────────────────────────────────────────────────────

;; (modaliser:start! config) → config, installed — or an error with the
;; engine untouched. See the file header for the three steps and the
;; one-shot / config-error contracts. The chain source handed to the
;; lowering is focused-terminal-path itself: the derived `.` step-in
;; providers re-probe it at each visit snapshot, walking the very
;; backend records this call installs.
(define (modaliser:start! config)
  (unless (configuration? config)
    (error "modaliser:start!: not a configuration value"
           'invalid-configuration config))
  (when %installed-configuration
    (error "modaliser:start!: a configuration is already installed — reload is relaunch"
           'already-started))
  (let ((delay (configuration-setting-ref config 'overlay-delay #f))
        (specs (configuration-setting-ref config 'leaders '())))
    ;; Pure phase — lower + closure validation, then the pre-effect
    ;; checks. Any error raised through here leaves the engine EMPTY.
    (let ((graph (lower-with-activation config focused-terminal-path)))
      (check-backend-records config)
      (check-overlay-delay delay)
      (check-leader-specs specs)
      ;; Effect phase — install, arm, THEN latch: the one-shot cell
      ;; sets only once every effect has succeeded, so an effect-phase
      ;; error (none is reachable for a validated value, but the order
      ;; guarantees it structurally) can never strand a half-installed
      ;; engine behind 'already-started. Arming before the latch is
      ;; safe: a handler reads %installed-configuration at PRESS time,
      ;; and the whole call runs inside one serialized evaluation, so
      ;; no press can observe the in-between state.
      (fsm-install-graph! graph)
      (terminal-install-backends! (map cdr (configuration-backends config)))
      (when delay (set-overlay-delay! delay))
      (for-each arm-leader! specs)
      (set! %installed-configuration config)
      config)))

)) ;; end begin / define-library
