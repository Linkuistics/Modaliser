# Terminal-backends: focused-terminal path as the detection primitive

`(modaliser terminal)` exposes the focused-terminal context as an
**alist keyed by backend symbol**, with each value a vector carrying
that backend's focused pane-id and its foreground command:

```scheme
(focused-terminal-path) =>
  '((iterm  . #(pane "uuid-A"      fg "zellij"))
    (zellij . #(pane "terminal_3"  fg "lazygit")))
```

For iTerm alone with no mux inside:

```scheme
(focused-terminal-path) =>
  '((iterm . #(pane "uuid-A" fg "nvim")))
```

For Alacritty (no pane concept):

```scheme
(focused-terminal-path) =>
  '((alacritty . #(pane #f fg "nvim")))
```

Convenience accessors:

- `(focused-terminal-foreground-command)` — the leaf frame's `fg`
  field. Backward-compatible alias for the most common existing use.
- `(in-chain? 'zellij)` — predicate; true if `'zellij` appears in
  the path. Useful for context-suffix handlers like "anywhere in
  the chain is nvim?"

## Why alist-with-backend-keys

The alternatives were:

- A list of frame records (preserves order; supports nested muxes
  uniquely).
- A flat tagged list (`(host iterm ...) (program ...) (mux zellij
  ...)`); Lispy but harder to query.

The user picked alist-with-backend-keys for its `(assoc 'zellij
path)` convenience. The trade-off — and a constraint future readers
must respect — is that **each backend symbol appears at most once
in the path**. Nested muxes (e.g. tmux inside zellij) cannot be
represented uniquely; the second occurrence is silently dropped.

This matches typical real-world usage (one mux per host pane) but
*does* preclude nested-mux support. If nested muxes ever become
relevant, the structure must change.

## How it's produced

The same walk that `(active-backend)` performs to dispatch ops
populates the path. Each layer's backend is asked for the focused-
pane id + foreground command of its focused pane; if that fg command
matches a registered mux backend, the walk descends into the mux.
The result is the chain of `(backend . #(pane id fg cmd))` pairs.

The walk is cached per leader press (shared with `(active-backend)`),
so the path is essentially free.

## Vector frame shape

Frame values are 4-element vectors with positional `pane`/`fg` tag
prefixes for human readability when printed:

```
position 0: 'pane  (literal symbol; reader sees the shape)
position 1: pane-id value (backend-specific; may be #f)
position 2: 'fg    (literal symbol)
position 3: foreground-command string
```

Accessors:

```scheme
(frame-pane v) ≡ (vector-ref v 1)
(frame-fg   v) ≡ (vector-ref v 3)
```

A record type was rejected to keep the printed form self-describing
(`#(pane "uuid-A" fg "zellij")` reads cleanly in transcripts and REPL
output; an opaque `#<terminal-frame …>` would not).
