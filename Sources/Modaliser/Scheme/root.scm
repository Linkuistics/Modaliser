;; root.scm — Modaliser application entry point
;;
;; This is the only file loaded by Swift. It bootstraps the entire
;; application by importing the (modaliser …) libraries, then
;; including the .scm modules that haven't been library-ized yet.
;; The library exports cascade into the top-level environment for the
;; included files and the user's config.scm to see. Phases C/D will
;; continue carving the included files into libraries.

;; ─── The shell seam, installed before anything else ───────────────
;;
;; This block is FIRST, ahead of every other import, and that ordering is
;; load-bearing (ADR-0023). `(modaliser shell)` ships with no runner installed,
;; so until these two lines run, every `run-shell` in the tree returns "" and
;; not one subprocess can be spawned. Libraries that shell out *at load time* —
;; (modaliser terminal) derives `modaliser-tool-path` from a login-shell spawn
;; the moment it is imported (ADR-0017 Layer 1) — must therefore be imported
;; after this, or they would silently bake the fallback floor.
;;
;; The corollary is the point of the whole arrangement: a bare `SchemeEngine()`
;; never runs this file, so `swift test` cannot reach a live tmux, zellij,
;; wezterm, kitty, or a Mac app over AppleScript. Before the seam existed a
;; single green run put 419 commands onto the developer's own machine
;; (test-live-backend-contact-k38) — 216 of them login-shell spawns running the
;; user's own .zprofile.
(import (modaliser shell)
        ;; The only import of the native library in the tree. Everything else
        ;; goes through the seam above; check-portable-surface.sh enforces it.
        (only (modaliser shell-native) run-shell-native run-shell-async-native))

(current-shell-runner run-shell-native)
(current-shell-async-runner run-shell-async-native)

;; ─── Modaliser libraries ──────────────────────────────────────────

(import (modaliser util)
        (modaliser keymap)
        (modaliser fsm)
        (modaliser event-dispatch)
        (modaliser dsl)
        (modaliser dom)
        (modaliser http)
        (modaliser web-search)
        (modaliser theming)
        (modaliser dialogs)
        (only (modaliser muxes herdr-socket)
              current-herdr-socket-path herdr-default-socket-path)
        ;; The only import of the native HTTP library in the tree; the seam
        ;; imported above is what everything else calls. The install is a few
        ;; lines below, with the rest of the host wiring.
        (only (modaliser http-native) http-get-native))

;; (modaliser fsm) stays host-portable, so it can't introspect a raw
;; on-leave hook's arity to decide whether to pass the exit reason. Install the
;; host's real arity predicate here (procedure-arity-includes? is a LispKit
;; primitive); the library's portable default assumes nullary until this runs.
(set-on-leave-accepts-reason! (lambda (thunk) (procedure-arity-includes? thunk 1)))

;; Same pattern for a raw entry/exit hook's arity — one host-injected predicate
;; serving both slots (fsm.sld's fsm-accepts-arg?). The
;; Terminal-leaf wrapping never depends on this being installed (it always
;; wraps as 0-arg and forwards the matched key through a captured cell
;; instead — see fsm.sld), but a transient (non-Terminal) leaf's
;; raw action still goes through this dispatch, so install it for real here.
(set-fsm-accepts-arg! (lambda (proc) (procedure-arity-includes? proc 1)))

;; Same pattern once more, for the one host resource the portable tree would
;; otherwise acquire by itself: herdr's Unix socket (ADR-0020). The transport
;; library ships `current-herdr-socket-path` as #f — "no herdr socket
;; configured", every call degrading to the #f a caller already handles — and
;; the live path is installed HERE, because reaching a running herdr is a
;; property of the app being live, not of the library being imported.
;;
;; That is what keeps `swift test` off the developer's own herdr session: a
;; bare SchemeEngine() never runs this file, so no test can dial a real socket
;; (test-live-herdr-contact-k35 — the load-time default had been sending
;; `pane.swap` into a live layout). The resolution policy itself stays in the
;; library; only the decision to go live is the host's.
(current-herdr-socket-path (herdr-default-socket-path))

;; And once more for the one outward reach that leaves the machine entirely:
;; fetching a URL (ADR-0023). `(modaliser http)` ships `current-http-runner` as
;; #f — every `http-get` answering its callback with the #f that already means
;; "the endpoint told us nothing" — and the live runner is installed HERE,
;; because reaching a third party is a property of the app being live.
;;
;; Unlike the shell install at the top of this file this one is NOT
;; order-sensitive, and it sits here with the rest of the host wiring for that
;; reason: nothing in the tree fetches at import time, and (modaliser
;; web-search) captures the seam's `http-get` — which dispatches at call time —
;; rather than the runner behind it.
;;
;; This is what keeps `swift test` off the public internet, a bare
;; SchemeEngine() never running this file. Before the seam existed one green run
;; fetched httpbin.org, and the only thing standing between the suite and Google
;; Suggest was that no test had yet called `web-search-handler` with a
;; three-character query (test-live-network-contact-k51).
(current-http-runner http-get-native)

;; ─── Plain .scm modules (Phase D will library-ize the remaining ones) ────────

(include "ui/css.scm")
(include "ui/overlay.scm")
(include "ui/chooser.scm")

;; chooser-push-results lives in the flat-included ui/chooser.scm. Wire it
;; into (modaliser web-search) now that both have loaded — the library
;; held a no-op placeholder until this point.
(set-chooser-push! chooser-push-results)

;; ─── App setup ────────────────────────────────────────────────────

;; Block until every required permission is granted. If any is missing on
;; first run (or after a revoke), this presents the onboarding window and
;; either relaunches the app once the user grants them, or terminates if
;; the user closes the window. By the line below this call, all listed
;; permissions are guaranteed to be granted.
(ensure-permissions! '(accessibility screen-recording))

(set-activation-policy! 'accessory)

;; ─── Config path ─────────────────────────────────────────────────

(define user-config-dir
  (string-append (get-environment-variable "HOME")
                 "/.config/modaliser"))

(define user-config-path
  (string-append user-config-dir "/config.scm"))

;; User-authored CSS lives in a real .css file so editors give syntax
;; highlighting and linting for free. Slurped into user-theme-css below
;; after the user config has loaded. The same file styles both the
;; overlay and the chooser/selector — hence the generic name.
(define user-theme-css-path
  (string-append user-config-dir "/theme.css"))

(define default-config-path
  (string-append *scheme-directory* "/default-config.scm"))

;; ─── Recovery actions ─────────────────────────────────────────────
;;
;; Every one of these stays reachable when the config failed to load —
;; that is the whole point of ADR-0022. They are the way back from a
;; wedged config, so none of them may depend on the config having
;; loaded.

;; Reveal the config directory in Finder. Users pick which file to edit
;; (config.scm / theme.css / their own .sld libraries) rather than us
;; assuming one canonical entry point.
(define (reveal-config!)
  (run-shell (string-append "/usr/bin/open \"" user-config-dir "\"")))

;; Open config.scm itself in whatever the user's default editor for
;; .scm is — the shortest path from "Config error: …" to a fix.
(define (open-config!)
  (run-shell (string-append "/usr/bin/open \"" user-config-path "\"")))

;; Copy file by streaming characters; preserves contents exactly.
(define (copy-file! src dst)
  (let ((in (open-input-file src))
        (out (open-output-file dst)))
    (let loop ((c (read-char in)))
      (if (eof-object? c)
        (begin
          (close-input-port in)
          (close-output-port out))
        (begin
          (write-char c out)
          (loop (read-char in)))))))

;; Seed user config from the bundled default on first run — one file,
;; user-owned from then on and never rewritten. It holds preference
;; only; machinery arrives always-fresh through the (modaliser …)
;; libraries, so a stale seed can never strand shipped code (ADR-0019).
(unless (file-exists? user-config-path)
  (run-shell (string-append "/bin/mkdir -p \"" user-config-dir "\""))
  (when (file-exists? default-config-path)
    (copy-file! default-config-path user-config-path)
    (log "Modaliser: seeded default config at " user-config-path)))

;; Replace config.scm with the bundled default, keeping a timestamped
;; copy of what was there. The last resort on the recovery menu: it
;; needs no working config, and after the relaunch the user is back to
;; a Modaliser that runs.
(define (reset-config-to-default!)
  (dialog-confirm
    (string-append
      "Replace your configuration with Modaliser's bundled default?"
      "\n\nYour current config.scm is copied alongside it as "
      "config.scm.backup-<timestamp> first, and Modaliser relaunches.")
    (lambda (confirmed?)
      (when confirmed?
        (when (file-exists? user-config-path)
          (run-shell (string-append "/bin/cp \"" user-config-path "\" \""
                                    user-config-path
                                    ".backup-$(/bin/date +%Y%m%d-%H%M%S)\"")))
        (copy-file! default-config-path user-config-path)
        (log "Modaliser: reset config to the bundled default")
        (relaunch!)))
    'title "Reset Configuration"
    'ok-label "Replace"
    'icon "caution"))

;; ─── Start keyboard capture ───────────────────────────────────────

(start-keyboard-capture!)

;; ─── Boot completion ──────────────────────────────────────────────
;;
;; The host loads the user's config (SchemeEngine.loadConfiguration) and
;; then calls back here with the outcome — 'loaded, 'degraded (the
;; bundled default is armed in the user config's place), or 'failed
;; (nothing is armed). The load cannot be guarded from Scheme: LispKit
;; implements `raise` in Scheme, so `guard` sees only deliberate raises,
;; while a read error, a type error or an unbound variable unwinds the
;; virtual machine past every handler. Only the host, sequencing two
;; top-level evaluations, can catch it (ADR-0022).

;; A menu-item-sized rendering of a multi-line evaluator error.
(define (config-error-summary message)
  (let ((line (car (string-split message "\n"))))
    (if (> (string-length line) 64)
      (string-append (substring line 0 64) "…")
      line)))

(define (show-config-error status message)
  (dialog-info
    (string-append
      "Modaliser couldn't load your configuration:\n"
      user-config-path "\n\n" message "\n\n"
      (if (eq? status 'degraded)
        "The bundled default configuration is running instead."
        "The bundled default configuration could not be loaded either — leader keys may not respond.")
      "\n\nUse the Modaliser menu to open your config, or to reset it.")))

;; The status-bar menu, built ONCE the config outcome is known so the
;; error item is part of the same menu. Every item is enabled in every
;; outcome: a failed config must still leave a way back.
(define (status-menu-items status message)
  (append
    (if (eq? status 'loaded)
      '()
      (list
        (list (cons 'title (string-append "⚠ Config error: "
                                          (config-error-summary message)))
              (cons 'action (lambda () (show-config-error status message))))
        'separator))
    (list
      (list (cons 'title "Open Config…")
            (cons 'action open-config!)
            (cons 'key-equivalent "o"))
      (list (cons 'title "Reveal Config in Finder")
            (cons 'action reveal-config!)
            (cons 'key-equivalent ","))
      (list (cons 'title "Reset Config to Bundled Default…")
            (cons 'action reset-config-to-default!))
      'separator
      (list (cons 'title "Relaunch")
            (cons 'action relaunch!)
            (cons 'key-equivalent "r"))
      'separator
      (list (cons 'title "Quit Modaliser")
            (cons 'action quit!)
            (cons 'key-equivalent "q")))))

;; Called by the host exactly once, whatever the config did. Ordered so
;; that the recovery surfaces come first: the menu, then the error, then
;; the theming work that a broken theme.css could itself derail.
(define (modaliser:config-load-finished! status message)
  (create-status-item! ":icon" (status-menu-items status message))

  ;; The error text itself is already on the host's os.Logger (the
  ;; `config` category); this is the user-visible half.
  (unless (eq? status 'loaded)
    (show-config-error status message))

  ;; Slurp ~/.config/modaliser/theme.css if present. Runs after the user
  ;; config so a programmatic user who wants to compose CSS in Scheme
  ;; can still do so by writing to user-theme-css before this point — but
  ;; the canonical authoring surface is the .css file.
  (when (file-exists? user-theme-css-path)
    (set! user-theme-css (read-file-text user-theme-css-path)))

  ;; Wire the (modaliser theming) probe to the overlay's CSS stack and
  ;; kick it off. The probe library can't see top-level user-theme-css
  ;; from inside its define-library scope, so we hand it a closure that
  ;; resolves them at call time — same deferred-resolution pattern
  ;; (modaliser overlay-assets) uses for its file resolver. Must run
  ;; AFTER the theme.css slurp so user overrides feed the probe.
  (theming-set-css-source! overlay-full-css)
  (run-chip-theme-probe!)

  ;; log-line, not (modaliser util)'s `log`: `log` is display + newline,
  ;; which reaches the context delegate's NSLog and is therefore invisible
  ;; in the unified log from an installed .app. The boot outcome is the one
  ;; line worth being able to query after the fact.
  (log-line (string-append "Modaliser Scheme runtime initialized (config: "
                           (symbol->string status) ")")))
