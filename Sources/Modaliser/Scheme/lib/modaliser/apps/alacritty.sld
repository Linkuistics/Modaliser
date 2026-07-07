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
;;   (alacritty:register!)
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
;; ─── configure-entry (optional) ───────────────────────────────────
;;
;; Useful only when Alacritty was installed via the (Gatekeeper-
;; deprecated) brew cask: that path leaves `com.apple.quarantine` on
;; the .app, which macOS uses to silently refuse `open`. The recipe
;; is one xattr call.
;;
;; The entry is hidden when there is *nothing for the user to do*:
;;
;;   - Alacritty isn't installed at all (nothing to configure).
;;   - Alacritty is installed and quarantine-free (e.g. direct DMG).
;;
;; It is visible only when /Applications/Alacritty.app exists *and*
;; carries the quarantine xattr. Removing the xattr is non-
;; destructive — Alacritty's binary itself is unchanged. This is
;; the optional companion to the recommended
;; install path (direct GitHub-releases DMG), which never sets
;; quarantine in the first place.

(define-library (modaliser apps alacritty)
  (export register!
          configure-entry
          backend)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (only (modaliser terminal)
                make-terminal-backend
                register-backend!
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

    ;; ─── configure-entry ────────────────────────────────────────────
    ;;
    ;; Probe: `xattr` lists extended attributes one per line. The entry
    ;; is "needed" (configured? = #f) only when /Applications/
    ;; Alacritty.app exists AND `xattr` mentions com.apple.quarantine.
    ;; A missing .app or a quarantine-free .app both report configured?
    ;; = #t, keeping the entry hidden.

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

    ;; Cached state — the overlay's 'hidden thunk reads
    ;; alacritty-configured? on every render, so the probe must be
    ;; cheap (one xattr call, but still). 'unknown forces a one-time
    ;; lazy probe; the refresh hook re-runs after the action so the
    ;; entry disappears without a Modaliser reload.
    (define *alacritty-state* 'unknown)

    (define (alacritty-refresh-state!)
      (set! *alacritty-state* (alacritty-probe-state))
      *alacritty-state*)

    (define (alacritty-configured?)
      (when (eq? *alacritty-state* 'unknown)
        (alacritty-refresh-state!))
      ;; Hidden = configured? truthy. Both 'clean and 'no-app hide
      ;; the entry; only 'quarantined surfaces it.
      (not (eq? *alacritty-state* 'quarantined)))

    ;; Single-quote escape for safe interpolation inside an
    ;; osascript -e '...' word. Same idiom (modaliser apps iterm /
    ;; kitty) use; the dialog message contains the literal command
    ;; "xattr -d com.apple.quarantine ..." so it's already
    ;; apostrophe-free, but the helper is here for symmetry and
    ;; future edits.
    (define (shell-sq-escape s)
      (let loop ((cs (string->list s)) (acc '()))
        (if (null? cs)
          (list->string (reverse acc))
          (loop (cdr cs)
                (if (char=? (car cs) #\')
                  (cons #\' (cons #\' (cons #\\ (cons #\' acc))))
                  (cons (car cs) acc))))))

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

    (define (alacritty-confirm-configure)
      (string-contains?
        (run-shell
          (string-append
            "osascript -e 'display dialog \""
            (shell-sq-escape alacritty-configure-dialog-message)
            "\" with title \"Configure Alacritty\" "
            "buttons {\"Cancel\", \"Continue\"} "
            "default button \"Cancel\" cancel button \"Cancel\" "
            "with icon caution' 2>/dev/null"))
        "Continue"))

    ;; The action itself: re-probe (the user may have fixed it
    ;; manually since the entry rendered), confirm, run xattr, re-
    ;; probe so the cache flips to 'clean and the entry hides.
    (define (alacritty-configure!)
      (cond
        ((not (eq? (alacritty-probe-state) 'quarantined))
         (alacritty-refresh-state!))
        ((alacritty-confirm-configure)
         (run-shell
           (string-append
             "xattr -d com.apple.quarantine \""
             alacritty-app-path "\" 2>/dev/null"))
         (alacritty-refresh-state!))
        (else #f)))

    ;; A `(key …)` node bound to Ctrl+Shift+I — same key as iTerm's
    ;; and Kitty's configure-entry. They're mutually exclusive by
    ;; frontmost app (and Alacritty's entry vanishes the moment the
    ;; xattr is gone), so the keybinding can be re-used.
    (define (configure-entry)
      (cons (cons 'hidden alacritty-configured?)
            (key "C-I" "Configure Alacritty" alacritty-configure!)))

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
        'alacritty "Alacritty" 'host "org.alacritty"
        detect-fg-command
        focused-pane-id
        #f #f #f #f                       ; focus-pane-{l,r,u,d}
        #f #f #f #f                       ; split-pane-{l,r,u,d}
        #f #f #f #f                       ; move-pane-{l,r,u,d}
        #f                                ; focus-pane-by-digit
        #f                                ; toggle-pane-zoom
        alacritty-configured?))

    ;; Register the backend. Safe to call more than once: register-
    ;; backend! is last-write-wins on backend symbol. No pane-digit
    ;; tree to register — detection-only.
    (define (register!)
      (register-backend! backend))))
