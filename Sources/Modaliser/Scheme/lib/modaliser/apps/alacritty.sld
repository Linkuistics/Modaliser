;; (modaliser apps alacritty) — Alacritty host backend behind the
;; (modaliser terminal) façade. Detection-only: Alacritty has no panes
;; by design, so all 14 pane ops are #f. The value the backend
;; contributes is the *host* row of (focused-terminal-path) — a
;; `(alacritty . #(pane #f fg <cmd>))` entry that lets a mux running
;; inside Alacritty (the typical splits configuration: tmux or zellij
;; set as Alacritty's `shell.program`) take over the 14-op surface.
;;
;; Quick start (prefix-style import — recommended to avoid collisions
;; with peer backend modules and the façade):
;;
;;   (import (prefix (modaliser apps alacritty) alacritty:))
;;   (configuration (alacritty:fragment) …)
;;
;; ─── Op surface (0/14) ────────────────────────────────────────────
;;
;; Every focus / split / move / digit-jump / zoom op is #f. Alacritty
;; exposes no pane CLI, no AppleScript dictionary (`sdef` returns
;; -192), and `alacritty msg` covers only window/config management.
;; Users who want splits run a mux inside; the mux backend then
;; supplies the 14 ops via the façade.
;;
;; (terminal:supports-splits?), (terminal:supports-move-pane?),
;; (terminal:supports-digit-jump?) and (terminal:supports-zoom?) all
;; return #f when Alacritty alone is the active backend — exactly the
;; "detection-only" capability story this backend was sized for. With a
;; mux inside, the façade resolves the mux as active-backend and
;; those predicates reflect the mux's capabilities instead.
;;
;; ─── Detection ────────────────────────────────────────────────────
;;
;; (focused-pane-id) is constant #f — Alacritty has no pane concept.
;; The vector frame produced by the façade walk is therefore
;; `#(pane #f fg <cmd>)` — the detection-only shape.
;;
;; (detect-fg-command) walks the local process tree:
;;
;;   1. `pgrep -x alacritty` — every alacritty parent pid.
;;   2. For each parent, `pgrep -P <pid>` — child shells. `alacritty
;;      msg create-window` reuses the parent, so one alacritty pid
;;      can host several child shells across windows.
;;   3. For each child, `lsof -p <pid> -d 0 -Fn` — the tty its stdin
;;      is bound to.
;;   4. (tty-foreground-command tty) → foreground command.
;;
;; The shell pipeline emits the *first* tty/fg-cmd pair it finds.
;; Single-window-single-instance — the daily case — is fully
;; supported. Multi-window or multi-instance is honest v1: without an
;; AX-side correlation from the focused NSWindow back to its child
;; shell pid (TCC-required; not wired up yet), we can't disambiguate
;; which child the user is actually looking at, so the first child
;; wins. This matches what `notes/alacritty.md` calls "indirect and
;; inexact"; a follow-up could thread an AX walk through
;; (modaliser accessibility) when multi-window becomes a real ask.
;;
;; ─── Chip rendering — not applicable ──────────────────────────────
;;
;; `focus-pane-by-digit` is #f, so the digit-jump chip path is
;; inert — there is nothing to label. When a user runs a mux inside
;; Alacritty, that mux's backend owns chip rendering (e.g. the tmux
;; backend's per-pane geometry over the Alacritty host frame).
;;
;; ─── Provisioning (optional) ──────────────────────────────────────
;;
;; Useful only when Alacritty was installed via the (Gatekeeper-
;; deprecated) brew cask: that path leaves `com.apple.quarantine` on
;; the .app, which macOS uses to silently refuse `open`. The recipe
;; is one xattr call.
;;
;; `configured?` reports #t — nothing for the user to do — in two
;; cases:
;;
;;   - Alacritty isn't installed at all (nothing to configure).
;;   - Alacritty is installed and quarantine-free (e.g. direct DMG).
;;
;; It reports #f — there IS something to do, so a row gated on it
;; shows — only when /Applications/Alacritty.app exists *and* carries
;; the quarantine xattr. Removing the xattr is non-destructive —
;; Alacritty's binary itself is unchanged. This is the optional
;; companion to the recommended install path (direct GitHub-releases
;; DMG), which never sets quarantine in the first place.

(define-library (modaliser apps alacritty)
  (export ;; Provisioning (ADR-0021): `configure!` strips the quarantine
          ;; xattr the brew cask leaves behind, and `configured?` is the
          ;; cached probe saying whether there is anything to strip. Both
          ;; are facilities — what macOS blocks is macOS's business.
          ;; Surfacing the action, and hiding the row when the probe says
          ;; there is nothing to do, is the configuration's call:
          ;;
          ;;   (key "C-I" "Configure Alacritty" alacritty:configure!
          ;;        'hidden alacritty:configured?)
          configure! configured?
          backend
          ;; The configuration-value constructor (ADR-0018,
          ;; library-fragments-k11): a pure fragment carrying the
          ;; detection-only backend record — no digit tree (no pane ops)
          ;; and no stock screen. Compose with your own (screen
          ;; "org.alacritty" …), whose scope is what makes the screen
          ;; terminal-like against this record's match-key; splits come
          ;; from a mux context inside (that is the point of a
          ;; detection-only host).
          fragment)
  (import (scheme base)
          ;; No (modaliser dsl): this library authors no keys and no
          ;; labels (ADR-0021), and its fragment carries a backend record
          ;; rather than a tree, so it needs none of the tree DSL.
          ;;
          ;; The contribution constructors for `fragment` — prefixed to
          ;; keep the bare names (backend, tree, …) clear of this
          ;; module's own vocabulary.
          (prefix (modaliser configuration) config:)
          (modaliser util)
          (modaliser shell)
          (modaliser dialogs)
          (only (modaliser terminal)
                make-terminal-backend
                tty-foreground-command
                modaliser-tool-path))
  (begin

    ;; ─── Shell preamble ─────────────────────────────────────────────
    ;;
    ;; GUI-launched Modaliser inherits a stripped path_helper PATH that
    ;; doesn't include /usr/sbin (lsof, pgrep) — same prefix pattern as
    ;; tmux / zellij / wezterm / kitty.
    (define path-prefix
      (string-append "export PATH=" modaliser-tool-path ":$PATH; "))

    ;; ─── Detection ──────────────────────────────────────────────────

    ;; Detection-only backend: pane-id is structurally #f, so the
    ;; façade walk emits `#(pane #f fg <cmd>)` as the host-no-pane
    ;; frame shape.
    (define (focused-pane-id) #f)

    ;; Walk alacritty → child shell → tty in one shell pipeline. Emit
    ;; the first tty discovered; the Scheme side feeds it to
    ;; tty-foreground-command. An empty echo means "no alacritty
    ;; running, or no child shell with a tty we can read".
    ;;
    ;; -Fn formats lsof so the tty path appears alone on a line
    ;; prefixed with `n` (see (modaliser terminal) correlate-mux-
    ;; client-to-host-tty for the same idiom).
    ;;
    ;; The pipeline does not try to pick the *focused* window in a
    ;; multi-window setup — see module header. The first tty wins
    ;; (honest v1).
    (define (first-alacritty-tty)
      (let* ((cmd (string-append
                    path-prefix
                    "for parent in $(pgrep -x alacritty); do "
                    "  for child in $(pgrep -P $parent); do "
                    "    tty=$(lsof -p $child -d 0 -Fn 2>/dev/null "
                    "          | awk '/^n/ {print substr($0,2); exit}'); "
                    "    if [ -n \"$tty\" ]; then "
                    "      echo $tty; exit 0; "
                    "    fi; "
                    "  done; "
                    "done"))
             (out (string-trim (run-shell cmd))))
        (if (string=? out "") #f out)))

    (define (detect-fg-command)
      (let ((tty (first-alacritty-tty)))
        (and tty (tty-foreground-command tty))))

    ;; ─── Provisioning ───────────────────────────────────────────────
    ;;
    ;; Probe: `xattr` lists extended attributes one per line. Work is
    ;; "needed" (configured? = #f) only when /Applications/
    ;; Alacritty.app exists AND `xattr` mentions com.apple.quarantine.
    ;; A missing .app or a quarantine-free .app both report configured?
    ;; = #t, so a row gated on it stays hidden.

    (define alacritty-app-path "/Applications/Alacritty.app")

    (define alacritty-probe-script
      (string-append
        "P=" alacritty-app-path "\n"
        "if [ ! -d \"$P\" ]; then echo no-app; exit 0; fi\n"
        "if xattr \"$P\" 2>/dev/null | grep -q '^com\\.apple\\.quarantine$'; then\n"
        "  echo quarantined\n"
        "else\n"
        "  echo clean\n"
        "fi\n"))

    ;; Three-state probe: 'no-app | 'clean | 'quarantined. Only
    ;; 'quarantined surfaces the entry; the other two hide it. Kept
    ;; as a small Scheme symbol so the cache + the action share a
    ;; single source of truth.
    (define (alacritty-probe-state)
      (let ((out (string-trim (run-shell alacritty-probe-script))))
        (cond
          ((string=? out "quarantined") 'quarantined)
          ((string=? out "clean")       'clean)
          (else                         'no-app))))

    ;; Cached state — a configuration that gates its setup row on
    ;; `configured?` has the overlay reading it on every render, so the
    ;; probe must be cheap (one xattr call, but still). 'unknown forces a
    ;; one-time lazy probe; the refresh hook re-runs after the action so
    ;; the row disappears without a Modaliser reload.
    (define *alacritty-state* 'unknown)

    (define (alacritty-refresh-state!)
      (set! *alacritty-state* (alacritty-probe-state))
      *alacritty-state*)

    (define (configured?)
      (when (eq? *alacritty-state* 'unknown)
        (alacritty-refresh-state!))
      ;; Hidden = configured? truthy. Both 'clean and 'no-app hide a
      ;; gated row; only 'quarantined surfaces it.
      (not (eq? *alacritty-state* 'quarantined)))

    (define alacritty-configure-dialog-message
      (string-append
        "Alacritty is installed but macOS is blocking it from "
        "launching because the brew cask carries the\n"
        "com.apple.quarantine attribute.\n\n"
        "Choosing Continue will:\n\n"
        "  - Run: xattr -d com.apple.quarantine "
        alacritty-app-path "\n"
        "  - Leave Alacritty itself unchanged\n\n"
        "After this Alacritty will launch normally. (The direct "
        "GitHub-releases DMG never sets this attribute; the brew "
        "cask does.)"))

    ;; The provisioning action a configuration binds: re-probe (the user
    ;; may have fixed it manually since the row rendered); if still
    ;; quarantined, confirm (async, ADR-0014 — through the slim
    ;; (modaliser dialogs) library so the Scheme thread stays free while
    ;; the dialog is up), run xattr, re-probe so the cache flips to
    ;; 'clean and a row gated on `configured?` hides itself.
    (define (configure!)
      (if (not (eq? (alacritty-probe-state) 'quarantined))
        (alacritty-refresh-state!)
        (dialog-confirm alacritty-configure-dialog-message
          (lambda (continue?)
            (when continue?
              (run-shell
                (string-append
                  "xattr -d com.apple.quarantine \""
                  alacritty-app-path "\" 2>/dev/null"))
              (alacritty-refresh-state!)))
          'title "Configure Alacritty" 'ok-label "Continue" 'icon "caution")))

    ;; ─── Backend record ─────────────────────────────────────────────
    ;;
    ;; All 14 op slots #f — detection-only. configured? wraps the
    ;; same cached probe the overlay reads, so capability predicates
    ;; (none of which can be true on Alacritty anyway) and any future
    ;; introspection see the live state.
    ;;
    ;; Bundle-id `org.alacritty` is the upstream canonical id (set in
    ;; the project's Info.plist for both the brew cask and the direct
    ;; GitHub-releases DMG). Verify at hand-verify time with
    ;; `mdls -name kMDItemCFBundleIdentifier /Applications/Alacritty.app`.

    (define backend
      (make-terminal-backend
        ;; tool-name #f: Alacritty exposes no CLI tool at all (module
        ;; header) — every op is #f, so there is nothing this backend
        ;; could ever shell out to that a relocation could break.
        'alacritty "Alacritty" 'host "org.alacritty" #f
        detect-fg-command
        focused-pane-id
        #f #f #f #f                       ; focus-pane-{l,r,u,d}
        #f #f #f #f                       ; split-pane-{l,r,u,d}
        #f #f #f #f                       ; move-pane-{l,r,u,d}
        #f                                ; focus-pane-by-digit
        #f                                ; toggle-pane-zoom
        configured?))

    ;; (fragment) → the Alacritty Fragment (library-fragments-k11):
    ;; just the detection-only backend record. Compose ONE call's value.
    (define (fragment)
      (list
        (config:backend 'alacritty backend)))))
