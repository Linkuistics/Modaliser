# Terminal-backends: keep direction-word procedure names (not hjkl)

The existing iTerm module exports `focus-pane-left`, `focus-pane-right`,
`focus-pane-up`, `focus-pane-down` (and the same for split / move — 12
direction procedures total). The user's recall and on-screen language
consistently use "hjkl"; this is about the *keys the user types*, not
the procedure names. Renaming would break 12 procedures × ~20 call
sites in the user's `config.scm:157-176` for zero behaviour change.

Phase 2 backends export the same direction-word names. If a future
request demands hjkl aliases, the façade `(modaliser pane)` is the
right place to add them — backends stay canonical with one name per
operation.
