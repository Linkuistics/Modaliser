;; (modaliser apps vscode) — Visual Studio Code (com.microsoft.VSCode)
;; utilities.
;;
;; VSCode exposes no scripting dictionary and no IPC socket worth the
;; name, so everything here is built from two things Modaliser already
;; has: the window enumeration, and synthetic keystrokes onto VSCode's
;; own default chords. That is why this library is small — it is a
;; shaping layer over `list-windows`, plus three named chords, and
;; nothing else.
;;
;; window-source / focus-window! are ready for a chooser row: the source
;; lists every open VSCode window keyed on its PROJECT (the folder the
;; window is rooted at), and focus-window! focuses the chosen one.
;; toggle-terminal / focus-explorer / focus-editor are 0-arg thunks over
;; VSCode's default macOS chords, each ready for a screen's key slot.
;;
;; Utilities layer only (ADR-0019, ADR-0021): the per-app SCREEN — keys,
;; labels, grouping — is preference and is authored in user config; this
;; library carries the machinery so it stays current across upgrades.
;; `Scheme/examples/vscode.scm` is a complete worked screen to copy from.
;;
;; Recommended import is prefix-style (bare exports collide with peers,
;; and `focus-window!` sits one character from the window library's own
;; `focus-window`):
;;
;;   (import (prefix (modaliser apps vscode) code:))
;;   (code:window-source)      (code:focus-window! item)
;;   (code:toggle-terminal)    (code:focus-explorer)   (code:focus-editor)
;;
;; ─── The three chords, and what they actually do ────────────────────
;;
;; Established by reading the shipped bundle's own command registrations
;; (VSCode 1.136.2,
;; /Applications/Visual Studio Code.app/Contents/Resources/app/out/vs/
;; workbench/workbench.desktop.main.js), not from documentation about
;; keyboard shortcuts, which is where all three of these are commonly
;; mis-stated.
;;
;;   ctrl-`  workbench.action.terminal.toggleTerminal.  A TOGGLE: pressed
;;           while the terminal already has focus it HIDES the panel.
;;           The strict-focus command, workbench.action.terminal.focus,
;;           is bound to cmd-Down and only `when` the terminal is already
;;           the active panel, so it is not reachable as a general focus
;;           chord. Bind terminal.focus in keybindings.json if the
;;           toggle grates.
;;
;;   shift-cmd-e  workbench.view.explorer.  NOT a sidebar toggle, despite
;;           the folklore: the registered action opens and focuses the
;;           explorer unless the sidebar already has focus, in which case
;;           it focuses the editor instead. So it reaches the explorer
;;           from anywhere except the explorer.
;;
;;   cmd-1   workbench.action.focusFirstEditorGroup. The exact command
;;           for "focus the editor" is focusActiveEditorGroup, but it
;;           registers with no default keybinding at all, so a synthetic
;;           keystroke cannot reach it. cmd-1 differs only when several
;;           editor groups are open, where it lands on the leftmost
;;           rather than the active one; bind focusActiveEditorGroup in
;;           keybindings.json to close that gap.
;;
;; ─── Where the project name comes from ──────────────────────────────
;;
;; VSCode's default macOS window title is
;; `${activeEditorShort}${separator}${rootName}${separator}${profileName}`
;; with `${separator}` defaulting to a spaced em dash — again read out of
;; the shipped bundle. Empty variables collapse, so under the default
;; profile a window title is either "<folder>" or "<file> — <folder>",
;; and the LAST em-dash segment is the folder name. Under a NAMED
;; profile the profile is appended after the folder and the last segment
;; is the profile instead — which is why every item keeps its untouched
;; title under 'title. A caller that needs to resolve a window to a real
;; directory should join against a source that knows the folders (the
;; editor's own stored window state) and test every segment, rather than
;; trusting the last one.

(define-library (modaliser apps vscode)
  (export ;; ── Identity ───────────────────────────────────────────────
          ;; VSCode's bundle id. The screen's scope symbol is spelled by
          ;; the user (it is the per-app screen's key), but the id is
          ;; VSCode's own fact, so a caller filtering or launching by it
          ;; need not restate the literal.
          bundle-id

          ;; ── The window surface ─────────────────────────────────────
          ;; (window-source) → chooser items, one per open VSCode window.
          ;; Impure: it calls the window enumeration.
          window-source
          ;; (focus-window! item) → focuses the window that item names.
          focus-window!
          ;; The pure halves the two above are built from, exported
          ;; because they are where the behaviour is and therefore where
          ;; the tests land:
          ;;   (windows-of enumeration) → items
          ;;   (project-name title)     → the folder segment
          ;;   (focus-choice item)      → the alist focus-window reads
          windows-of
          project-name
          focus-choice

          ;; ── Ops: the verbs a screen binds (ADR-0021) ───────────────
          ;; 0-arg thunks over VSCode's default macOS chords, ready for a
          ;; key slot. Which key reaches each, and under what label, is
          ;; the screen's call. See the header for what each chord does
          ;; — toggle-terminal is named for the toggle it is.
          toggle-terminal
          focus-explorer
          focus-editor)
  (import (scheme base)
          (modaliser util)
          (only (modaliser input) send-keystroke)
          (only (modaliser window) list-windows focus-window))
  (begin

    (define bundle-id "com.microsoft.VSCode")

    ;; The spaced em dash VSCode joins its title segments with. A literal
    ;; rather than a character class: the folder name may itself contain
    ;; a hyphen or a dash, and only this exact three-character run is a
    ;; separator.
    (define title-separator " — ")

    ;; ─── The project name (pure) ────────────────────────────────────
    ;;
    ;; A window title → the folder segment. A title with no separator is
    ;; its own folder name, which is the no-editor-open case; the empty
    ;; string maps to itself. See the header for the named-profile
    ;; caveat.
    (define (project-name title)
      (let ((segments (string-split title title-separator)))
        (if (null? segments)
            ""
            (string-trim (car (reverse segments))))))

    ;; ─── The window items (pure) ────────────────────────────────────
    ;;
    ;; ENUMERATION → one chooser item per open VSCode window, in
    ;; enumeration order. Each item is
    ;;
    ;;   ((text . <folder name>) (title . <raw window title>)
    ;;    (windowId . N) (ownerPid . N))
    ;;
    ;; 'text is the chooser's display AND fuzzy-match field, which is why
    ;; the folder name lands there rather than the whole title: selecting
    ;; among windows here means selecting among projects. The raw title
    ;; stays under 'title for two callers — focus-choice, which needs it
    ;; as a fallback match, and anything resolving a window to a
    ;; directory, which must not trust one segment of it.
    ;;
    ;; ENUMERATION is an ARGUMENT rather than a call, and that is the
    ;; whole reason this is a pure function: the live sweep happens one
    ;; level up, in window-source.
    (define (windows-of enumeration)
      (map (lambda (w)
             (let ((title (or (alist-ref w 'text) "")))
               (list (cons 'text     (project-name title))
                     (cons 'title    title)
                     (cons 'windowId (alist-ref w 'windowId))
                     (cons 'ownerPid (alist-ref w 'ownerPid)))))
           (filter (lambda (w) (equal? bundle-id (alist-ref w 'icon)))
                   enumeration)))

    ;; ─── Focusing (pure) ────────────────────────────────────────────
    ;;
    ;; One item → the choice alist focus-window reads: 'ownerPid (without
    ;; which it no-ops), 'windowId, and 'text as a title hint. The hint
    ;; must be the REAL title, not the item's display text: the window id
    ;; is resolved against a live accessibility sweep and the title is
    ;; the fallback when that misses, so handing it a folder name would
    ;; silently degrade the fallback to never matching.
    (define (focus-choice item)
      (list (cons 'ownerPid (alist-ref item 'ownerPid))
            (cons 'windowId (alist-ref item 'windowId))
            (cons 'text     (or (alist-ref item 'title) ""))))

    ;; ─── The impure edges ───────────────────────────────────────────

    ;; Every open VSCode window as chooser items. Cross-space: it rides
    ;; the full enumeration, so a project parked on another desktop is
    ;; still selectable.
    (define (window-source)
      (windows-of (list-windows)))

    (define (focus-window! item)
      (focus-window (focus-choice item)))

    ;; ─── The chords ─────────────────────────────────────────────────

    (define (toggle-terminal) (send-keystroke '(ctrl) "`"))
    (define (focus-explorer)  (send-keystroke '(cmd shift) "e"))
    (define (focus-editor)    (send-keystroke '(cmd) "1"))))
