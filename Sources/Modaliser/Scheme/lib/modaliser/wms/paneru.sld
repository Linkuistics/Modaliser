;; (modaliser wms paneru) — paneru window-manager ops and the
;; installation predicate.
;;
;; paneru (karinushka/paneru) is an external sliding window manager: windows
;; live on an infinite horizontal strip and opening one never resizes its
;; neighbours. A daemon owns the strip; the `paneru` binary talks to it over a
;; Unix socket. Modaliser is a *client* of it, never a reimplementation.
;;
;; Quick start (prefix-style import, so the bare op names don't collide with
;; (modaliser window-actions)'s layout ops):
;;
;;   (import (prefix (modaliser wms paneru) paneru:))
;;
;;   (define windows-screen
;;     (if (paneru:installed?)
;;         (open …)          ; a screen built from the ops below
;;         (open …)))        ; the Window-layout-op screen
;;
;; That `if` is the **Paneru-installed composition**: one branch, taken once at
;; config load (ADR-0018). It tests *installation*, never daemon liveness — a
;; liveness test would make the meaning of a key depend on whether Modaliser or
;; the paneru daemon won the startup race, whereas installation cannot race. A
;; daemon that is down degrades to the established empty-output path.
;;
;; NO SCREEN, and no keys. Which op reaches which key under which label is the
;; user's (ADR-0021); every op below is a **facility**, its correctness fixed by
;; paneru's own CLI rather than by anybody's preference.
;;
;; `wms/` is a new category, peer to `muxes/`, `apps/` and `tools/`. This file
;; is shaped like `muxes/zellij.sld` and is deliberately missing that file's two
;; structural pieces: there is **no backend record** and **no `wiring`
;; fragment**, because paneru sits behind no façade. It is not a
;; (modaliser terminal) backend, it contributes no Terminal-context-map entry,
;; and it has nothing for the façade to dispatch to. Nothing replaces them — a
;; reader coming from `zellij.sld` should read that absence as the point.
;;
;; Seven ops, not twenty. The rest of paneru's surface — `resize`, `fullwidth`,
;; `stack`/`unstack`, `equalize`, `balance`, `manage`, the workspace verbs, the
;; display verbs, `focus first`/`last`/`<n>` — is deliberately absent. Each
;; further op is a config-visible follow-up costing one line here, not
;; speculative library surface.
;;
;; Fire-and-forget, with no error channel. Probed against the live daemon
;; (2026-08-04): an unrecognised command exits 0 and prints nothing — the daemon
;; silently discards it. A wrong wire form therefore fails *invisibly*, which is
;; why each op's exact command string is pinned by a test rather than trusted.
;; Note in particular that the wire form is space-separated
;; (`window focus east`); the underscored spelling (`window_focus_east`) is the
;; TOML *binding name* in the user's paneru.toml, not something send-cmd accepts.
;;
;; Every outward call goes through the (modaliser shell) seam (ADR-0023), which
;; ships with no runner installed — so under `swift test` this library reaches
;; no live daemon however many ops fire. See docs/specs/paneru-window-management.md.

(define-library (modaliser wms paneru)
  (export
          ;; ── Ops: the verbs a screen binds (ADR-0021) ───────────────
          ;;
          ;; All 0-arg thunks that land straight in a `(key K L op)` slot,
          ;; each one `paneru send-cmd …` and nothing else.
          ;;
          ;;   focus-west / focus-east  move focus one column along the strip
          ;;   swap-west  / swap-east   move the focused window one column
          ;;   grow / shrink            next / previous preset_column_widths entry
          ;;   center                   scroll the strip to centre the focused window
          focus-west  focus-east
          swap-west   swap-east
          grow        shrink
          center
          ;; ── The composition predicate ──────────────────────────────
          ;;
          ;; #t when the `paneru` binary resolves on the derived tool path
          ;; (ADR-0017). The **Paneru-installed composition** test — see the
          ;; header on why this is installation and not liveness.
          installed?)
  (import (scheme base)
          (modaliser shell)
          (only (modaliser util) string-trim)
          ;; Narrowly, for the PATH preamble below. Every CLI-native backend
          ;; in the tree reaches into the terminal façade for this one string;
          ;; relocating it to a neutral home is a separate concern.
          (only (modaliser terminal) modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that does
    ;; not include the prefixes `paneru` is installed under, so every
    ;; shell-out is prefixed with the derived tool path (ADR-0017 Layer 1).
    ;; Baked once at library load, exactly as tmux, zellij and the app
    ;; backends bake theirs.
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; ─── Ops ────────────────────────────────────────────────────────
    ;;
    ;; One helper, seven one-line ops. ARGS is the space-separated command
    ;; tail exactly as the daemon expects it; stderr is discarded on the
    ;; same terms as every other backend — a missing binary must degrade to
    ;; the empty string, never raise, because a leader press must never
    ;; raise (ADR-0017).
    (define (send-cmd args)
      (run-shell
        (string-append path-prefix "paneru send-cmd " args " 2>/dev/null")))

    (define (focus-west) (send-cmd "window focus west"))
    (define (focus-east) (send-cmd "window focus east"))

    (define (swap-west)  (send-cmd "window swap west"))
    (define (swap-east)  (send-cmd "window swap east"))

    (define (grow)       (send-cmd "window grow"))
    (define (shrink)     (send-cmd "window shrink"))

    (define (center)     (send-cmd "window center"))

    ;; ─── Installation ───────────────────────────────────────────────
    ;;
    ;; `command -v paneru` through the derived tool path, the same probe
    ;; ADR-0017 Layer 2 runs for a backend's CLI tool. Empty output — a
    ;; missing binary, or a bare engine with no shell runner installed —
    ;; reads as absent, so an unbootstrapped engine composes the non-paneru
    ;; screen and nothing else in this library ever runs.
    (define (installed?)
      (not (string=? ""
             (string-trim
               (run-shell
                 (string-append path-prefix
                                "command -v paneru 2>/dev/null"))))))))
