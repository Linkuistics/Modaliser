;; (modaliser terminal) — focused-terminal detection + the pane-ops façade.
;;
;; Two concerns live here:
;;
;; 1. The legacy detection primitives (focused-iterm-tty, tty-foreground-command,
;;    nvim socket discovery, etc.) — unchanged from Phase 1.
;;
;; 2. The terminal-backends façade (see docs/reference/terminal-detection.md):
;;    a backend record, a registry, active-backend resolution, the focused-
;;    terminal-path walk, the 14 op shims, and 5 capability predicates. Per-
;;    backend modules ((modaliser apps iterm), (modaliser muxes tmux), …)
;;    register populated `<terminal-backend>` records; user configs call the
;;    façade ops by direction-word name through this module's prefix.
;;
;; Design notes: the direction-word op names, the façade-only public
;; surface, the capability predicates, multi-session tty correlation, and
;; the focused-terminal path shape are documented in
;; docs/reference/terminal-detection.md and
;; docs/how-to/terminal-pane-aware-tree.md.

(define-library (modaliser terminal)
  (export ;; Legacy detection (unchanged).
          focused-iterm-tty
          tty-foreground-command
          focused-terminal-foreground-command
          modaliser-tool-path
          merge-tool-path
          list-nvim-sockets
          nvim-server-focused?
          focused-nvim-socket
          nvim-remote-send
          nvim-remote-expr

          ;; Backend façade — registry & path.
          make-terminal-backend
          terminal-backend?
          register-backend!
          current-frontmost-bundle-id
          active-backend
          focused-terminal-path
          in-chain?

          ;; Backend tool health (ADR-0017 Layer 2). backend-tool-missing?
          ;; is what a block consults to render a "tool not found" message
          ;; instead of an empty list; note-backend-query-result! is what a
          ;; backend's own query wrapper calls after every query, so a #f
          ;; result triggers the lazily-memoized re-probe.
          backend-tool-missing?
          note-backend-query-result!
          current-tool-probe-runner

          ;; 14 op shims.
          focus-pane-left focus-pane-right focus-pane-up focus-pane-down
          split-pane-left split-pane-right split-pane-up split-pane-down
          move-pane-left  move-pane-right  move-pane-up  move-pane-down
          focus-pane-by-digit
          toggle-pane-zoom

          ;; Capability predicates.
          supports-splits?
          supports-move-pane?
          supports-digit-jump?
          supports-zoom?
          supports?

          ;; Multi-session-local tty correlation. Mux backends
          ;; pass their own host-tty source + pgrep pattern.
          correlate-mux-client-to-host-tty)
  (import (scheme base)
          (modaliser app)
          (modaliser shell)
          (modaliser util)
          ;; log-line: the one Scheme-facing diagnostic primitive
          ;; (ADR-0017 Layer 2) — a missing backend tool logs here, never
          ;; raises through a leader press.
          (modaliser log))
  (begin

    ;; ─── Legacy detection ───────────────────────────────────────────

    ;; Return the pty path of iTerm2's focused session (e.g. "/dev/ttys003"),
    ;; or #f if iTerm2 is not running or the query fails.
    ;; The `is running` guard prevents the naked `tell application "iTerm2"`
    ;; from auto-launching iTerm via Launch Services.
    (define (focused-iterm-tty)
      (let* ((script
               (string-append
                 "if application \"iTerm2\" is running then "
                 "tell application \"iTerm2\" to "
                 "tell current session of current window to get tty"))
             (out (run-shell
                    (string-append "osascript -e '" script "' 2>/dev/null")))
             (trimmed (string-trim out)))
        (if (string=? trimmed "") #f trimmed)))

    ;; Given a pty path like "/dev/ttys003", return the command string of
    ;; the foreground process on that tty, or #f if none.
    ;; `ps -t <name>` expects the short name without /dev/.
    (define (tty-foreground-command tty)
      (let* ((slash (string-split tty "/"))
             (name  (if (null? slash) tty (list-ref slash (- (length slash) 1))))
             (cmd   (string-append
                      "ps -t " name " -o pgid=,tpgid=,command= | "
                      "awk '$1==$2 { for (i=3; i<=NF; i++) "
                      "printf \"%s%s\", $i, (i==NF?\"\":\" \"); exit }'"))
             (out   (run-shell cmd))
             (trimmed (string-trim out)))
        (if (string=? trimmed "") #f trimmed)))

    ;; PATH prefix for subprocesses that need tools the user's login shell
    ;; resolves but GUI-launched Modaliser's minimal path_helper PATH
    ;; doesn't. Derived once at load (ADR-0017): spawn the login shell,
    ;; capture its $PATH, and merge it with the previous hardcoded floor —
    ;; so a tool that moves off the floor but stays on the user's shell
    ;; PATH needs no Modaliser change. Any spawn failure degrades to the
    ;; floor alone.

    ;; STR's ":"-separated segments, trimmed and with empty segments
    ;; dropped — a trailing newline from `echo $PATH`, or an empty string
    ;; outright, must not become a "" entry (which PATH treats as ".").
    (define (tool-path-segments str)
      (remove (lambda (seg) (string=? seg ""))
              (string-split (string-trim str) ":")))

    ;; LST with later duplicates dropped, first occurrence kept in place.
    (define (dedupe-preserving-first lst)
      (let loop ((rest lst) (seen '()) (acc '()))
        (cond
          ((null? rest) (reverse acc))
          ((member (car rest) seen) (loop (cdr rest) seen acc))
          (else (loop (cdr rest)
                      (cons (car rest) seen)
                      (cons (car rest) acc))))))

    ;; Pure merge: LOGIN-PATH (a raw, possibly empty/malformed $PATH
    ;; string captured from the user's login shell) union FLOOR (the
    ;; previous hardcoded constant), login entries first so a relocated
    ;; tool resolves there before falling through to the floor. Entries
    ;; shared between the two collapse to their first occurrence, so the
    ;; floor's entries always survive even when the login PATH repeats
    ;; them.
    (define (merge-tool-path login-path floor)
      (string-join
        (dedupe-preserving-first
          (append (tool-path-segments login-path) (tool-path-segments floor)))
        ":"))

    (define modaliser-tool-path
      (merge-tool-path
        (guard (e (#t "")) (run-shell "/bin/zsh -lc 'echo $PATH' 2>/dev/null"))
        "/opt/homebrew/bin:/usr/local/bin:/usr/sbin"))

    ;; ─── Backend façade ─────────────────────────────────────────────
    ;;
    ;; Each backend module builds one <terminal-backend> record and hands
    ;; it to `register-backend!`. The façade indexes backends two ways:
    ;; host-by-bundle-id (`focused-app-bundle-id`) and mux-by-fg-command
    ;; (e.g. "tmux", "zellij"), discriminated by the record's `kind`.
    ;; Each backend's `symbol` (e.g. 'iterm, 'zellij) is what appears in
    ;; the focused-terminal-path alist.
    ;;
    ;; Op fields are thunks of zero args or #f when unsupported. Capability
    ;; predicates AND the field's presence with `configured?` so bindings
    ;; gated by `(supports-move-pane?)` etc. flip on only after configure-
    ;; entry has done its provisioning.
    ;;
    ;; `focus-pane-by-digit` is the one exception: it holds a plain
    ;; digit-mode-id symbol (or #f when unsupported), not a thunk — the
    ;; façade export of the same name resolves it at fire time (see
    ;; below) rather than dispatching-and-calling it like the other 13.
    (define-record-type <terminal-backend>
      (make-terminal-backend symbol name kind match-key tool-name
                             detect-foreground-command
                             focused-pane-id
                             focus-pane-left focus-pane-right
                             focus-pane-up   focus-pane-down
                             split-pane-left split-pane-right
                             split-pane-up   split-pane-down
                             move-pane-left  move-pane-right
                             move-pane-up    move-pane-down
                             focus-pane-by-digit
                             toggle-pane-zoom
                             configured?)
      terminal-backend?
      (symbol                    terminal-backend-symbol)
      (name                      terminal-backend-name)
      (kind                      terminal-backend-kind)        ;; 'host or 'mux
      (match-key                 terminal-backend-match-key)   ;; bundle-id or fg-cmd
      ;; The CLI binary this backend's shell-outs depend on (e.g. "herdr",
      ;; "tmux"), or #f for a backend with no separate tool (AppleScript-
      ;; driven iTerm/Ghostty, the tool-less Alacritty). Distinct from
      ;; match-key: a 'host backend's match-key is a bundle-id, not
      ;; necessarily its CLI tool's name (kitty/wezterm: both).
      (tool-name                 terminal-backend-tool-name)
      (detect-foreground-command terminal-backend-detect-fg)
      (focused-pane-id           terminal-backend-focused-pane-id)
      (focus-pane-left           terminal-backend-focus-pane-left)
      (focus-pane-right          terminal-backend-focus-pane-right)
      (focus-pane-up             terminal-backend-focus-pane-up)
      (focus-pane-down           terminal-backend-focus-pane-down)
      (split-pane-left           terminal-backend-split-pane-left)
      (split-pane-right          terminal-backend-split-pane-right)
      (split-pane-up             terminal-backend-split-pane-up)
      (split-pane-down           terminal-backend-split-pane-down)
      (move-pane-left            terminal-backend-move-pane-left)
      (move-pane-right           terminal-backend-move-pane-right)
      (move-pane-up              terminal-backend-move-pane-up)
      (move-pane-down            terminal-backend-move-pane-down)
      (focus-pane-by-digit       terminal-backend-focus-pane-by-digit)
      (toggle-pane-zoom          terminal-backend-toggle-pane-zoom)
      (configured?               terminal-backend-configured?))

    ;; Registry. A list of records; re-registering a symbol replaces the
    ;; previous entry (last-write-wins, the only sensible policy for
    ;; reload-by-relaunch). LispKit lacks set-cdr!, so we rebuild the
    ;; list via set! rather than mutating in place
    ;; ([[feedback_lispkit_no_mutable_pairs]]).
    (define *backend-registry* '())

    (define (register-backend! backend)
      (let ((sym (terminal-backend-symbol backend)))
        (set! *backend-registry*
              (cons backend
                    (remove
                      (lambda (b)
                        (eq? (terminal-backend-symbol b) sym))
                      *backend-registry*)))
        ;; Configure-entry probe (ADR-0017 Layer 2): catches a broken tool
        ;; path at every relaunch, before any op fires. A backend with no
        ;; separate CLI tool (tool-name #f) has nothing to probe.
        (let ((tool (terminal-backend-tool-name backend)))
          (when tool (probe-backend-tool! sym tool)))))

    ;; ─── Backend tool health (ADR-0017 Layer 2) ─────────────────────
    ;;
    ;; Two detection points, both driven off the SAME per-symbol health
    ;; table: register-backend! above (configure-entry — eager, once) and
    ;; note-backend-query-result! below (lazy — fired by a backend's own
    ;; query wrapper whenever a query returns #f). A successful query is
    ;; itself proof the tool exists (a genuinely-missing binary can never
    ;; produce real output through run-shell), so the success branch just
    ;; clears the flag — no probe, no extra subprocess spawn on the
    ;; healthy path. Only the ambiguous #f moment ("tool gone" vs
    ;; "nothing running") re-probes, which is also what lets a restored
    ;; tool clear its flag without a relaunch.
    ;;
    ;; *backend-health* is a symbol -> 'ok | 'missing alist, rebuilt via
    ;; set! (no set-cdr!, [[feedback_lispkit_no_mutable_pairs]]). A symbol
    ;; absent from the table (not yet probed, or tool-name-less) reads as
    ;; 'ok — the fail-open default a leader press needs.

    ;; (command -v TOOL) through the derived tool path, #t if resolvable.
    ;; Test seam mirroring current-herdr-query-runner (muxes/herdr.sld):
    ;; a test hands back a canned present/absent verdict instead of
    ;; shelling out (feedback_no_live_env_mutation_in_tests).
    (define current-tool-probe-runner
      (make-parameter
        (lambda (tool)
          (not (string=? ""
                 (string-trim
                   (run-shell
                     (string-append "export PATH=" modaliser-tool-path ":$PATH; "
                                    "command -v " tool " 2>/dev/null"))))))))

    (define *backend-health* '())

    (define (set-backend-health! sym status)
      (set! *backend-health*
            (cons (cons sym status)
                  (remove (lambda (kv) (eq? (car kv) sym)) *backend-health*))))

    (define (backend-tool-missing? sym)
      (let ((kv (assq sym *backend-health*)))
        (and kv (eq? (cdr kv) 'missing))))

    ;; Probe TOOL for backend SYM, update the health table, and log —
    ;; once per transition into 'missing, not on every repeated probe —
    ;; so a backend stuck missing doesn't spam `log show` on every op.
    (define (probe-backend-tool! sym tool)
      (let ((present? ((current-tool-probe-runner) tool))
            (was-missing? (backend-tool-missing? sym)))
        (set-backend-health! sym (if present? 'ok 'missing))
        (when (and (not present?) (not was-missing?))
          (log-line
            (string-append "(modaliser terminal): backend '"
                           (symbol->string sym) "' tool \"" tool
                           "\" not found on the tool path")))))

    ;; The registered backend's own tool-name, or #f if none is
    ;; registered under SYM (nothing to probe).
    (define (registered-backend-tool sym)
      (let loop ((bs *backend-registry*))
        (cond
          ((null? bs) #f)
          ((eq? (terminal-backend-symbol (car bs)) sym)
           (terminal-backend-tool-name (car bs)))
          (else (loop (cdr bs))))))

    ;; A backend's query wrapper calls this with its raw result's success/
    ;; failure (OK? — #t for a real result, #f for the query's own "empty
    ;; or unparseable" sentinel). Success clears any stale 'missing flag
    ;; with no probe; failure re-probes (the ambiguous moment) unless this
    ;; backend has no tracked tool at all.
    (define (note-backend-query-result! sym ok?)
      (if ok?
          (set-backend-health! sym 'ok)
          (let ((tool (registered-backend-tool sym)))
            (when tool (probe-backend-tool! sym tool)))))

    ;; Frontmost bundle-id source. Parameterizable so tests can stub the
    ;; OS query without registering a backend at the real frontmost app.
    (define current-frontmost-bundle-id
      (make-parameter focused-app-bundle-id))

    (define (resolve-host-backend bundle-id)
      (and bundle-id
           (let loop ((bs *backend-registry*))
             (cond
               ((null? bs) #f)
               ((and (eq? (terminal-backend-kind (car bs)) 'host)
                     (string=? (terminal-backend-match-key (car bs)) bundle-id))
                (car bs))
               (else (loop (cdr bs)))))))

    (define (resolve-mux-backend fg-cmd)
      (and fg-cmd
           (let loop ((bs *backend-registry*))
             (cond
               ((null? bs) #f)
               ((and (eq? (terminal-backend-kind (car bs)) 'mux)
                     (string=? (terminal-backend-match-key (car bs)) fg-cmd))
                (car bs))
               (else (loop (cdr bs)))))))

    ;; The single root→leaf walk that both `focused-terminal-path` and
    ;; `active-backend` consume. Returns `((backend . #(pane <id> fg <cmd>)) …)`
    ;; with the host frame first and the innermost mux last. Empty if no
    ;; host backend is registered for the frontmost app.
    ;;
    ;; Invariant: each backend symbol appears at most once. We track
    ;; `seen` so a future case like tmux-inside-tmux can't loop — the
    ;; second occurrence is silently dropped.
    ;;
    ;; Not cached. Future work: memoise per leader press once the leader
    ;; layer exposes a "press epoch" hook.
    (define (walk-path)
      (let* ((bundle ((current-frontmost-bundle-id)))
             (host   (resolve-host-backend bundle)))
        (if (not host)
            '()
            (let loop ((b host) (acc '()) (seen '()))
              (let* ((pane-id ((terminal-backend-focused-pane-id b)))
                     (fg-cmd  ((terminal-backend-detect-fg b)))
                     (frame   (vector 'pane pane-id 'fg fg-cmd))
                     (acc1    (cons (cons b frame) acc))
                     (seen1   (cons (terminal-backend-symbol b) seen))
                     (next    (and fg-cmd (resolve-mux-backend fg-cmd))))
                (if (and next
                         (not (memq (terminal-backend-symbol next) seen1)))
                    (loop next acc1 seen1)
                    (reverse acc1)))))))

    (define (focused-terminal-path)
      (map (lambda (entry)
             (cons (terminal-backend-symbol (car entry)) (cdr entry)))
           (walk-path)))

    (define (active-backend)
      (let ((p (walk-path)))
        (if (null? p)
            #f
            (car (list-ref p (- (length p) 1))))))

    (define (in-chain? sym)
      (and (assq sym (focused-terminal-path)) #t))

    ;; Frame accessors used internally + by the backward-compat path below.
    (define (frame-fg v) (vector-ref v 3))

    ;; The leaf frame's fg. When no backend is registered yet (e.g. during
    ;; phase 010 before iTerm's register! in 020), fall back to the legacy
    ;; iTerm-direct lookup so the user's existing Phase 1 setup keeps
    ;; working through the cutover (BRIEF "Daily-driver continuity").
    (define (focused-terminal-foreground-command)
      (let ((p (walk-path)))
        (if (null? p)
            (cond ((focused-iterm-tty) => tty-foreground-command)
                  (else #f))
            (frame-fg (cdr (list-ref p (- (length p) 1)))))))

    ;; ─── Op shims ───────────────────────────────────────────────────
    ;;
    ;; Each shim resolves `(active-backend)`, reads its op slot, and calls
    ;; the thunk. Missing op = error naming the registry as truth so a
    ;; misconfigured import surfaces clearly.

    (define (dispatch op-name accessor)
      (let ((b (active-backend)))
        (cond
          ((not b)
           (error
             (string-append
               "(modaliser terminal): no backend registered for frontmost app")))
          (else
            (let ((thunk (accessor b)))
              (cond
                ((not thunk)
                 (error
                   (string-append
                     "(modaliser terminal): "
                     (symbol->string (terminal-backend-symbol b))
                     " does not implement " op-name)))
                (else (thunk))))))))

    (define (focus-pane-left)   (dispatch "focus-pane-left"   terminal-backend-focus-pane-left))
    (define (focus-pane-right)  (dispatch "focus-pane-right"  terminal-backend-focus-pane-right))
    (define (focus-pane-up)     (dispatch "focus-pane-up"     terminal-backend-focus-pane-up))
    (define (focus-pane-down)   (dispatch "focus-pane-down"   terminal-backend-focus-pane-down))

    (define (split-pane-left)   (dispatch "split-pane-left"   terminal-backend-split-pane-left))
    (define (split-pane-right)  (dispatch "split-pane-right"  terminal-backend-split-pane-right))
    (define (split-pane-up)     (dispatch "split-pane-up"     terminal-backend-split-pane-up))
    (define (split-pane-down)   (dispatch "split-pane-down"   terminal-backend-split-pane-down))

    (define (move-pane-left)    (dispatch "move-pane-left"    terminal-backend-move-pane-left))
    (define (move-pane-right)   (dispatch "move-pane-right"   terminal-backend-move-pane-right))
    (define (move-pane-up)      (dispatch "move-pane-up"      terminal-backend-move-pane-up))
    (define (move-pane-down)    (dispatch "move-pane-down"    terminal-backend-move-pane-down))

    ;; Fire-time resolver, not a dispatch-and-call op shim (ADR-0015
    ;; Context item 3): the active backend's slot is a digit-mode-id
    ;; symbol (or #f), returned as-is for a procedure-valued `'next` to
    ;; follow. No active backend, or an unsupported slot, resolves to
    ;; #f — dispatch's fail-safe branch then keeps capture and does
    ;; normal cleanup, never an error.
    (define (focus-pane-by-digit)
      (let ((b (active-backend)))
        (and b (terminal-backend-focus-pane-by-digit b))))
    (define (toggle-pane-zoom)
      (dispatch "toggle-pane-zoom" terminal-backend-toggle-pane-zoom))

    ;; ─── Capability predicates ──────────────────────────────────────
    ;;
    ;; Trees built via `set-local-context-suffix!`-style rebuild see
    ;; per-press capabilities. The AND with `configured?` is the
    ;; provisioning-gate (WezTerm pre-configure-entry: ops are defined
    ;; but the keybinds aren't installed → predicate is #f).

    (define (op-configured? b accessor)
      (and b (accessor b)
           ((terminal-backend-configured? b))))

    (define (supports-splits?)
      (let ((b (active-backend)))
        (and b
             (op-configured? b terminal-backend-focus-pane-left)
             (op-configured? b terminal-backend-focus-pane-right)
             (op-configured? b terminal-backend-focus-pane-up)
             (op-configured? b terminal-backend-focus-pane-down)
             (op-configured? b terminal-backend-split-pane-left)
             (op-configured? b terminal-backend-split-pane-right)
             (op-configured? b terminal-backend-split-pane-up)
             (op-configured? b terminal-backend-split-pane-down)
             (op-configured? b terminal-backend-move-pane-left)
             (op-configured? b terminal-backend-move-pane-right)
             (op-configured? b terminal-backend-move-pane-up)
             (op-configured? b terminal-backend-move-pane-down)
             #t)))

    (define (supports-move-pane?)
      (let ((b (active-backend)))
        (and b
             (op-configured? b terminal-backend-move-pane-left)
             (op-configured? b terminal-backend-move-pane-right)
             (op-configured? b terminal-backend-move-pane-up)
             (op-configured? b terminal-backend-move-pane-down)
             #t)))

    (define (supports-digit-jump?)
      (let ((b (active-backend)))
        (and b
             (op-configured? b terminal-backend-focus-pane-by-digit)
             #t)))

    (define (supports-zoom?)
      (let ((b (active-backend)))
        (and b
             (op-configured? b terminal-backend-toggle-pane-zoom)
             #t)))

    ;; Universal introspection. Each op symbol maps to the accessor that
    ;; reads its slot off the active backend; the predicate is the same
    ;; configured-and-present check used by the four coarse predicates.
    (define (supports? op-sym)
      (let ((b (active-backend))
            (accessor
              (case op-sym
                ((focus-pane-left)     terminal-backend-focus-pane-left)
                ((focus-pane-right)    terminal-backend-focus-pane-right)
                ((focus-pane-up)       terminal-backend-focus-pane-up)
                ((focus-pane-down)     terminal-backend-focus-pane-down)
                ((split-pane-left)     terminal-backend-split-pane-left)
                ((split-pane-right)    terminal-backend-split-pane-right)
                ((split-pane-up)       terminal-backend-split-pane-up)
                ((split-pane-down)     terminal-backend-split-pane-down)
                ((move-pane-left)      terminal-backend-move-pane-left)
                ((move-pane-right)     terminal-backend-move-pane-right)
                ((move-pane-up)        terminal-backend-move-pane-up)
                ((move-pane-down)      terminal-backend-move-pane-down)
                ((focus-pane-by-digit) terminal-backend-focus-pane-by-digit)
                ((toggle-pane-zoom)    terminal-backend-toggle-pane-zoom)
                (else                  #f))))
        (and b accessor (op-configured? b accessor) #t)))

    ;; ─── Multi-session tty correlation ──────────────────────────────
    ;;
    ;; Mux backends call this to find *their* CLI client whose controlling
    ;; tty matches the focused host pane's tty. Caller passes:
    ;;
    ;;   host-tty      — e.g. "/dev/ttys003" from (focused-iterm-tty)
    ;;   proc-pattern  — pgrep -f pattern, e.g. "^tmux " / "^zellij "
    ;;
    ;; Returns the matching mux pid (string) or #f. The mux backend then
    ;; queries that pid (e.g. `tmux -L <socket> list-clients`) to derive
    ;; the session name and target subsequent CLI commands at it.
    ;;
    ;; `lsof -p <pid> -d 0` prints the controlling tty of fd 0; we strip
    ;; the device-row header and match. PATH is forced because GUI-
    ;; launched Modaliser doesn't inherit /usr/sbin (lsof, pgrep).
    (define (correlate-mux-client-to-host-tty host-tty proc-pattern)
      (and host-tty
           (let* ((cmd (string-append
                         "export PATH=" modaliser-tool-path ":$PATH; "
                         "for pid in $(pgrep -f '" proc-pattern "'); do "
                         "  tty=$(lsof -p $pid -d 0 -Fn 2>/dev/null "
                         "        | awk '/^n/ {print substr($0,2); exit}'); "
                         "  if [ \"$tty\" = '" host-tty "' ]; then "
                         "    echo $pid; exit 0; "
                         "  fi; "
                         "done"))
                  (out (string-trim (run-shell cmd))))
             (if (string=? out "") #f out))))

    ;; ─── Neovim RPC discovery ─────────────────────────────────────
    ;;
    ;; Every running nvim binds a Unix socket (its msgpack-RPC server).
    ;; macOS lsof only emits the socket path when scoped to a specific
    ;; pid — globally it shows peer-pointer aliases — so we pgrep nvim
    ;; and scan each process.
    ;;
    ;; Focus disambiguation (multiple nvim instances, or nvim nested
    ;; inside a multiplexer): each nvim exposes its own belief about
    ;; terminal focus via the user-maintained global g:modaliser_focused,
    ;; updated by FocusGained / FocusLost autocmds. Modern terminals
    ;; (iTerm2, zellij, tmux) forward the xterm focus-reporting escapes
    ;; to their active pane, so exactly one nvim across the system
    ;; should report 1 at any given moment.

    ;; Unix-socket paths bound by running nvim processes.
    (define (list-nvim-sockets)
      (let ((out (run-shell
                   (string-append
                     "export PATH=" modaliser-tool-path ":$PATH; "
                     "for pid in $(pgrep -x nvim); do "
                     "  lsof -p $pid -a -U -Fn 2>/dev/null "
                     "  | awk '/^n\\// {print substr($0,2)}'; "
                     "done | sort -u"))))
        (let loop ((lines (string-split out "\n")) (acc '()))
          (cond
            ((null? lines) (reverse acc))
            (else
              (let ((s (string-trim (car lines))))
                (loop (cdr lines)
                      (if (string=? s "") acc (cons s acc)))))))))

    ;; True if the nvim at SOCK reports g:modaliser_focused == 1. The
    ;; `get` form treats a missing variable as 0, so unconfigured nvim
    ;; instances simply register as not-focused rather than producing a
    ;; Vim error.
    ;;
    ;; Critical: redirect stdin from /dev/null. When stdin is a TTY, the
    ;; nvim client decides to attach a UI, emits its alt-screen init +
    ;; teardown escapes (including \E[?1004l which globally disables
    ;; terminal focus reporting), and writes the expression result to
    ;; stderr instead of stdout. That single leaked escape would break
    ;; every subsequent focus probe silently. Closing stdin flips
    ;; isatty() to false and nvim runs as a proper non-UI RPC client.
    (define (nvim-server-focused? sock)
      (let ((out (run-shell
                   (string-append
                     "export PATH=" modaliser-tool-path ":$PATH; "
                     "nvim --server " sock
                     " --remote-expr 'get(g:, \"modaliser_focused\", 0)'"
                     " </dev/null 2>/dev/null"))))
        (string=? (string-trim out) "1")))

    ;; Socket of the focused nvim (direct, or via a multiplexer), or
    ;; #f if no running nvim claims focus. O(n) RPC calls in the worst
    ;; case, but typical n is 1–2.
    (define (focused-nvim-socket)
      (let loop ((socks (list-nvim-sockets)))
        (cond
          ((null? socks) #f)
          ((nvim-server-focused? (car socks)) (car socks))
          (else (loop (cdr socks))))))

    ;; Helpers for bindings to act on the focused nvim without refetching
    ;; the socket each time at the call site.
    (define (nvim-remote-send keys)
      (let ((sock (focused-nvim-socket)))
        (when sock
          (run-shell
            (string-append "export PATH=" modaliser-tool-path ":$PATH; "
                           "nvim --server " sock
                           " --remote-send '" keys "'"
                           " </dev/null 2>/dev/null")))))

    (define (nvim-remote-expr expr)
      (let ((sock (focused-nvim-socket)))
        (if sock
          (string-trim
            (run-shell
              (string-append "export PATH=" modaliser-tool-path ":$PATH; "
                             "nvim --server " sock
                             " --remote-expr '" expr "'"
                             " </dev/null 2>/dev/null")))
          #f)))))
