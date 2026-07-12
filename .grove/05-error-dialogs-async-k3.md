# error-dialogs-async-k3

**Kind:** work

## Goal

Build the **slim** `(modaliser dialogs)` library (ADR-0014: async-only — no
capture handling, that is dispatch's job per ADR-0015) and cut the backend
error/confirm dialog sites over to it — `apps/iterm.sld` (the configure
confirm + any error alert), `apps/kitty.sld:402`, `apps/alacritty.sld:224`
(line numbers as of k4) — so their Return/OK dismissal lands in the dialog
and the Scheme thread stays free.

## Context

- Same defect class as k2, lower severity: dialogs with no typed input,
  currently raised via blocking `run-shell` osascript from action thunks.
- The library surface: `dialog-confirm` (message, continuation receiving
  #t/#f — the iTerm configure flow consumes a result, so it goes CPS) and
  `dialog-info` (message, optional no-arg continuation). **No `modal-exit`
  anywhere** — the firing leaves are terminal, dispatch has already
  released. Execution only through the `current-dialog-runner` parameter
  (default `run-shell-async`), the single test seam.
- Audit while converting: any dialog site *not* reached via command dispatch
  (e.g. fired from a chooser callback or during config load) — confirm the
  no-modal case is naturally a no-op.
- Reusable snippets from the discarded k2-era draft (never committed;
  reproduced here so they survive):

```scheme
;; POSIX single-quote escaping: each ' becomes '\''
(define (sq-escape s)
  (let loop ((cs (string->list s)) (acc '()))
    (if (null? cs)
        (list->string (reverse acc))
        (loop (cdr cs)
              (if (char=? (car cs) #\')
                  (cons #\' (cons #\' (cons #\\ (cons #\' acc))))
                  (cons (car cs) acc))))))

;; AppleScript double-quoted-literal escaping: \ and "
(define (as-escape s)
  (let loop ((cs (string->list s)) (acc '()))
    (if (null? cs)
        (list->string (reverse acc))
        (let ((c (car cs)))
          (loop (cdr cs)
                (cond ((char=? c #\\) (cons #\\ (cons #\\ acc)))
                      ((char=? c #\") (cons #\" (cons #\\ acc)))
                      (else (cons c acc))))))))

;; Fire PROGRAM (an AppleScript command string) through the seam.
(define (run-dialog program callback)
  ((current-dialog-runner)
   (string-append "osascript -e '" (sq-escape program) "' 2>/dev/null")
   callback))

;; Confirm: default button Cancel so a stray Return never confirms;
;; Cancel raises in AppleScript (empty stdout) => #f.
(define (dialog-confirm message k)
  (run-dialog
    (string-append
      "button returned of (display dialog \"" (as-escape message) "\" "
      "buttons {\"Cancel\", \"OK\"} default button \"Cancel\")")
    (lambda (exit-code stdout stderr)
      (k (string=? (string-trim stdout) "OK")))))

(define (dialog-info message . opt)
  (run-dialog
    (string-append
      "display dialog \"" (as-escape message) "\" "
      "buttons {\"OK\"} default button \"OK\"")
    (lambda (exit-code stdout stderr)
      (when (and (pair? opt) (procedure? (car opt)))
        ((car opt))))))
```

## Done when

- All audited sites go through the library; their local osascript/escaping
  duplication is gone. `sq-escape`'s home is settled once (library export vs
  local copies — herdr.sld still needs it, see k2).
- New `ModaliserDialogsLibraryTests`: hostile-input escaping via the
  captured command string; confirm/cancel plumbing via canned callback
  stdout. Touched backend tests pass through the `current-dialog-runner`
  seam; no test spawns osascript. `swift test` green (usual skips);
  portable-surface check passes (mind the "(lispkit " literal rule in
  comments).
- `docs/reference/libraries.md` (or wherever the portable tree is
  enumerated) gains the library.
- Live spot-check of one site: trigger the iTerm configure/error dialog —
  Return/OK dismisses it while the leader stays responsive.
