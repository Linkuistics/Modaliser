;; (modaliser tools nvim) — Neovim as a Terminal-context-map entry.
;;
;; nvim is an INNER TOOL (ADR-0013's vocabulary): it runs in a pane of
;; any terminal-like host, but unlike a mux (herdr, tmux, zellij) it
;; hosts no panes of its own — its splits are nvim windows, driven over
;; nvim's msgpack-RPC socket, not a terminal-backend op surface. Its
;; context entry is therefore TREE-ONLY: no backend reference, no
;; chain continuation, no derived step-in of its own.
;;
;; Quick start (prefix-style import — recommended, matching the peer
;; backend modules):
;;
;;   (import (prefix (modaliser tools nvim) nvim:))
;;   (configuration … (terminal-contexts (nvim:wiring) …) nvim-screen)
;;
;; `wiring` is the integration; the SCREEN — which window commands are
;; surfaced, on which keys, under which labels — is the user's
;; (ADR-0021), and the seeded default-config.scm carries the stock
;; composition to read and edit.
;;
;; With that composed, a leader press while the focused pane runs nvim
;; lands directly in the nvim tree (the map consult normalizes the
;; frame's foreground command line — "nvim README.md" — to its exe
;; name); backspace steps outward to the containing context.
;;
;; Focus routing rides the same discovery the legacy suffix path used:
;; nvim-remote-send resolves the FOCUSED nvim instance per press via
;; the g:modaliser_focused socket probe ((modaliser terminal) — see its
;; docstring for the FocusGained/FocusLost autocmd contract), so the
;; tree works for any number of concurrent nvim instances.

(define-library (modaliser tools nvim)
  (export ;; ── The wiring fragment (ADR-0018 / ADR-0013 / ADR-0021) ───
          ;;
          ;; nvim's integration and nothing else — for an inner tool with
          ;; no pane surface of its own that is a single tree-only
          ;; Terminal-context-map entry. No backend record: nvim hosts no
          ;; panes, so there is nothing for the façade to dispatch to
          ;; (the shape is deliberately unlike a mux's, not an omission).
          ;;
          ;; The tree scope 'nvim is machinery, not preference: the
          ;; context entry references it by key, so the screen the user
          ;; authors must carry that scope or the configuration fails
          ;; reference-closure validation at load — loudly.
          wiring
          ;; ── Ops: the verbs a screen binds (ADR-0021) ───────────────
          ;;
          ;; nvim's four window-focus commands as 0-arg thunks, ready for
          ;; a `(key K L op)` slot. `<C-w>h` IS nvim's focus-window-left,
          ;; so these are facilities; which of hjkl reaches each is the
          ;; screen's call.
          focus-window-left focus-window-right
          focus-window-up   focus-window-down
          ;; The general form the four are built from, for the rest of
          ;; nvim's `<C-w>` repertoire (`s` split, `v` vsplit, `q` quit,
          ;; `=` equalise, …): (nvim:wincmd "v") → a 0-arg thunk. The
          ;; notation crosses the RPC boundary verbatim, so nvim's own
          ;; documentation is the reference.
          wincmd)
  (import (scheme base)
          (only (modaliser terminal) nvim-remote-send)
          ;; The contribution constructors — prefixed, as in the peer
          ;; backend modules, so the one call site below reads as the
          ;; contribution it is rather than as a bare `context`.
          (prefix (modaliser configuration) config:))
  (begin

    ;; A 0-arg thunk sending <C-w>C to the focused nvim: the window
    ;; (split) commands. The key notation crosses the RPC boundary
    ;; verbatim — nvim parses "<C-w>h" itself.
    (define (wincmd c)
      (lambda () (nvim-remote-send (string-append "<C-w>" c))))

    (define focus-window-left  (wincmd "h"))
    (define focus-window-down  (wincmd "j"))
    (define focus-window-up    (wincmd "k"))
    (define focus-window-right (wincmd "l"))

    ;; (wiring) → the nvim Fragment: the tree-only map entry, and that is
    ;; all of it. The screen the entry resolves to is the user's — see
    ;; the seeded default-config.scm, which surfaces window focus on hjkl
    ;; so the pane-focus muscle memory crosses INTO nvim windows the way
    ;; it crosses into mux panes. Deliberately small there too: nvim
    ;; power users live inside nvim's own maps.
    (define (wiring)
      (list
        (config:context "nvim" 'tree 'nvim)))))
