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
;; focused-workspace-path answers "which directory is the front window
;; rooted at", and reveal-file! opens a path and lands the explorer on
;; it — the pair a caller composes into "open something belonging to
;; THIS project", whatever the something is.
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
;;   (code:focused-workspace-path)   (code:reveal-file! path)
;;   (code:editor-cycler 'next 'focus THUNK)
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
;; ─── Cycling the editor, and why it needs a focus step ──────────
;;
;; workbench.action.previousEditor / .nextEditor, read out of the same
;; bundle (1.136.2). Four properties of them, none guessed:
;;
;;   THE CHORDS. Mac primary is alt-cmd-Left / alt-cmd-Right, with
;;   shift-cmd-[ / shift-cmd-] registered as secondary. Both are
;;   defaults, so either reaches the command; the primary is what the
;;   ops below send.
;;
;;   NO `when` CLAUSE. Both register at weight 200 with no context
;;   condition, so the chord is live from anywhere in the workbench —
;;   which is what makes the focus problem below reachable at all.
;;
;;   THEY CROSS GROUPS AND WRAP. `navigate` walks the active group's
;;   SEQUENTIAL editor list; past either end it asks for the adjacent
;;   group with wrap-around on and takes that group's first (or last)
;;   editor, bounded by a visited-id set. So with one group they cycle
;;   its tabs, and with several they cycle every tab in the window.
;;
;;   THEY SURVIVE THE TERMINAL. Both ids sit in the default
;;   terminal.integrated.commandsToSkipShell array, so the workbench
;;   handles the chord rather than the shell swallowing it.
;;
;; AND THE ONE THAT MAKES `editor-cycler` EXIST. The command opens the
;; editor it navigated to, and an editor opened without preserveFocus
;; normally focuses itself — so it would be reasonable to expect the
;; chord alone to pull focus into the editor. It does not. The open
;; path guards that focus call on the element that had focus BEFORE
;; the open being inside the editor group's own DOM subtree; focus
;; sitting in the terminal or the explorer fails that test, so nothing
;; is focused and the tab changes under a pane you cannot type into.
;; Activating the group does not rescue it either — that path
;; short-circuits when the active GROUP has not changed, and focus
;; moving to the terminal never changes which editor group is active.
;;
;; Hence one op, not two rows: focus, then cycle. WHICH focus chord is
;; the user's call and is therefore a parameter — see focus-editor's
;; caveat above for why the default is imperfect, and note the strict
;; command is only reachable if you bind it in keybindings.json.

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

;; ─── Which directory is a window rooted at? ─────────────────────────
;;
;; The window enumeration cannot say. A title carries a folder's NAME
;; and never its path, and a name is not a location — two worktrees may
;; share one. So the path comes from the editor's own record of it, and
;; the title is demoted to a join key.
;;
;; THE SOURCE. VSCode stores its window state in the user-level
;; globalStorage file
;;
;;   ~/Library/Application Support/Code/User/globalStorage/storage.json
;;
;; whose `windowsState.openedWindows` is one entry per open window,
;; each carrying an exact `folder` URI. Nothing else in reach carries a
;; path: not the accessibility tree, not the title, not a scripting
;; dictionary VSCode does not have.
;;
;; TWO PROPERTIES OF IT, ACCEPTED WITH EYES OPEN.
;;
;;   The format is UNDOCUMENTED and may change across VSCode releases.
;;   The mitigation is placement, not cleverness: the reading is one
;;   pure function over the file's TEXT, and the test that pins it runs
;;   off a fixture captured from a real file. When the format moves, a
;;   test says so and one function changes. That is also why this did
;;   not earn a decision record — behind a seam this small, the choice
;;   is cheap to reverse.
;;
;;   It is written on window state CHANGE, not continuously. A window
;;   opened seconds ago may not be in it yet, and then the answer is
;;   #f. That is not an error and is not reported as one: what to say
;;   about a miss is the caller's call, and the caller is the screen.
;;
;; AND ONE FACT ABOUT ITS SIZE, WHICH DECIDED THE IMPLEMENTATION. The
;; file is ~100 KB of which `windowsState` is the last ~5%, and handing
;; the whole thing to (modaliser json)'s parser cost 899 ms on a debug
;; build — measured, not estimated, and squarely inside ADR-0014's
;; stalled-tap territory for something that runs on a key press. So the
;; reader SLICES the `openedWindows` array out by a bracket scan and
;; parses only that. Two details of that scan are load-bearing and both
;; came from measuring rather than reasoning: it reads a char vector
;; bridged ONCE (the cliff (modaliser json)'s own header sets out at
;; length), and it looks for its anchor key BACKWARDS from the end,
;; because the key is unique — so direction cannot change the answer —
;; and walking the last 5% instead of the first 95% took a release-build
;; scan from ~490 ms to ~40 ms.
;;
;; ─── Opening a file in the RIGHT window ─────────────────────────────
;;
;; `code <file>` with no flags routes the file to the window that owns
;; its folder — not to the last-focused window, which was the worry
;; worth checking. Established by reading the shipped main process
;; (VSCode 1.136.2,
;; /Applications/Visual Studio Code.app/Contents/Resources/app/out/
;; main.js), where the CLI open path with no folder argument calls a
;; findWindowOnFilePath helper: it returns the window whose opened
;; folder is an ancestor of the file, preferring the LONGEST such
;; folder when several nest, and only falls back to the last active
;; window when no window owns the file. The chosen window is focused by
;; the same call that sends it the file.
;;
;; Two flags would break that and are therefore absent: `-r` forces
;; reuse of the last active window, `-n` forces a new one. So does the
;; `window.openFilesInNewWindow` setting, if a user sets it to "on".
;;

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
          ;;   (windows-of enumeration) → items, alphabetical by project
          ;;   (project-name title)     → the folder segment
          ;;   (focus-choice item)      → the alist focus-window reads
          windows-of
          project-name
          focus-choice

          ;; ── The workspace surface (grove-leaf-reveal-k3) ───────────
          ;; What FOLDER each open window is rooted at — the thing the
          ;; window enumeration cannot tell you, because a window title
          ;; carries a folder's NAME and never its path. The answer comes
          ;; from VSCode's own stored window state; see the header.
          ;;
          ;; (focused-workspace-path) → the absolute path of the folder
          ;; the FRONTMOST VSCode window is rooted at, or #f. Impure: it
          ;; reads the state file and the live window list.
          focused-workspace-path
          ;; (open-workspaces) → every folder-rooted open window as
          ;; ((path . ABS) (name . BASENAME)). Impure: reads the file.
          open-workspaces
          ;; (state-file-path) → where that file lives.
          state-file-path
          ;; The pure halves, which is where the tests land:
          ;;   (workspaces-of TEXT)                 → the list above
          ;;   (opened-windows-json TEXT)           → the array's text
          ;;   (workspace-for-title TITLE WSS)      → one of them, or #f
          ;;   (title-of-window-id ID ENUMERATION)  → a title, or #f
          workspaces-of
          opened-windows-json
          workspace-for-title
          title-of-window-id

          ;; ── Opening a file ─────────────────────────────────────────
          ;; (reveal-file! path [after]) — open PATH in the window that
          ;; owns its folder, then run AFTER (default: focus-explorer).
          ;; Asynchronous; see the header for why, for the routing it
          ;; relies on, and for when to pass an AFTER of your own.
          reveal-file!
          ;; The command it would spawn (pure), where the test lands.
          open-file-command

          ;; ── The project panel (vscode-project-panel-k4) ───────────
          ;; The same windows, reached by a JUMP LABEL on a top-level panel
          ;; instead of by fuzzy matching in a chooser.
          ;;
          ;; project-provider — keyword opts (three alphabets, 'panel-label,
          ;;                    'enumerate) → the Edge provider a screen binds
          ;;                    on its 'provider slot. The engine invokes it
          ;;                    with the id of the state it was lowered onto
          ;;                    (provider-state-id-k9).
          ;; project-listing  — → the listing block spec, reading the SAME
          ;;                    per-Visit assignment the provider took, so the
          ;;                    rows can never disagree with the labels.
          project-provider
          project-listing

          ;; ── Ops: the verbs a screen binds (ADR-0021) ───────────────
          ;; 0-arg thunks over VSCode's default macOS chords, ready for a
          ;; key slot. Which key reaches each, and under what label, is
          ;; the screen's call. See the header for what each chord does
          ;; — toggle-terminal is named for the toggle it is.
          toggle-terminal
          focus-explorer
          focus-editor

          ;; ── Cycling the editor (vscode-editor-cycling-k5) ─────────
          ;; The same shape: 0-arg thunks over VSCode's own default
          ;; chords for workbench.action.previousEditor / .nextEditor.
          previous-editor
          next-editor
          ;; (editor-cycler DIRECTION ['focus THUNK-or-#f] ['cycle THUNK])
          ;; → a 0-arg thunk that focuses the editor and THEN cycles.
          ;; DIRECTION is 'previous or 'next. The focus step is not a
          ;; nicety: without it the chord changes the tab while leaving
          ;; focus in the terminal or the explorer — see the header.
          editor-cycler
          ;; (cycle-thunk DIRECTION) → the chord thunk for it. Pure,
          ;; and where the direction mapping is pinned by a test.
          cycle-thunk)
  (import (scheme base)
          (scheme char)
          ;; get-environment-variable, for $HOME in the state-file path.
          ;; R7RS, so it costs the portable surface nothing — the same
          ;; import (modaliser muxes herdr-socket) makes for its socket.
          (only (scheme process-context) get-environment-variable)
          (modaliser util)
          (only (modaliser json) json-parse json-ref)
          (only (modaliser input) send-keystroke)
          (only (modaliser window)
                list-windows focus-window focused-window)
          ;; The project panel's two halves. jump-labels-assign turns the
          ;; window list into prefix-free labels under the USER's alphabets;
          ;; jump-list-provider-result lowers that assignment onto the FSM,
          ;; leaders and narrowing prefix states and all. Neither knows
          ;; anything of VSCode — this library injects the three things that
          ;; are its own. Both portable.
          (only (modaliser jump-labels) jump-labels-assign)
          (only (modaliser jump-list) jump-list-provider-result)
          ;; The listing renderer. The dependency runs THIS way only: the
          ;; block is a generic labelled-row component that knows nothing of
          ;; VSCode, and this library composes it.
          (only (modaliser blocks project-list) make-project-list-block)
          ;; The canonical POSIX single-quote escaper: a path out of an
          ;; editor's stored state is arbitrary text going into a shell
          ;; word.
          (only (modaliser dialogs) sq-escape)
          (only (modaliser shell) run-shell-async)
          ;; Narrowly, for the PATH preamble — as every CLI-driven module
          ;; in the tree does.
          (only (modaliser terminal) tool-path-prefix))
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
    ;; ENUMERATION → one chooser item per open VSCode window, ordered
    ;; alphabetically by project name (see below). Each item is
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
    ;;
    ;; ─── Why the order is alphabetical, not the enumeration's ───────
    ;;
    ;; The enumeration's order is front-to-back stacking order, so it
    ;; changes every time you focus a window — and the list this feeds is
    ;; a CHOOSER, whose whole value is that the same project sits in the
    ;; same place twice running. A list that reshuffles itself between
    ;; presses cannot be learned; an alphabetical one can be, and the
    ;; fuzzy filter is there for when learning it is not worth the
    ;; bother. Case-insensitive, because a human reading a list of folder
    ;; names is not thinking in ASCII, with the case-sensitive comparison
    ;; as tie-break so the order is TOTAL — two folders differing only in
    ;; case must not swap places from run to run either.
    (define (windows-of enumeration)
      (sort-stable
        (map (lambda (w)
               (let ((title (or (alist-ref w 'text) "")))
                 (list (cons 'text     (project-name title))
                       (cons 'title    title)
                       (cons 'windowId (alist-ref w 'windowId))
                       (cons 'ownerPid (alist-ref w 'ownerPid)))))
             (filter (lambda (w) (equal? bundle-id (alist-ref w 'icon)))
                     enumeration))
        project<?))

    (define (project<? a b)
      (let ((x (or (alist-ref a 'text) ""))
            (y (or (alist-ref b 'text) "")))
        (or (string-ci<? x y)
            (and (string-ci=? x y) (string<? x y)))))

    ;; A stable sort, by insertion. LispKit ships no list-sort and no
    ;; set-cdr! (the same absence `(modaliser blocks herdr-list)` and
    ;; `(modaliser muxes herdr)` each note), and the list here is one
    ;; entry per open editor window — a handful — so a quadratic sort
    ;; over it is the honest trade against carrying a merge sort.
    ;;
    ;; Stability comes from the direction: each item is inserted into the
    ;; items BEFORE it, and `insert-sorted` walks past everything not
    ;; strictly greater, so equal items keep their input order. Sorting
    ;; the tail first and inserting the head would reverse them.
    (define (insert-sorted x sorted less?)
      (cond ((null? sorted)          (list x))
            ((less? x (car sorted))  (cons x sorted))
            (else (cons (car sorted) (insert-sorted x (cdr sorted) less?)))))

    (define (sort-stable items less?)
      (let loop ((rest items) (acc '()))
        (if (null? rest)
            acc
            (loop (cdr rest) (insert-sorted (car rest) acc less?)))))

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

    ;; ─── The project panel (vscode-project-panel-k4) ────────────────
    ;;
    ;; The same windows `window-source` lists, but reached by a JUMP LABEL
    ;; on a top-level panel rather than by fuzzy-matching inside a chooser.
    ;; Two halves, the shape (modaliser wms paneru)'s Strip listing
    ;; established: `project-provider` mints the edges at come-to-rest, and
    ;; `project-listing` draws the snapshot that same call took — so the
    ;; rows on screen and the live labels cannot disagree, and a label
    ;; pressed faster than the overlay appears still dispatches.
    ;;
    ;; Everything subtle about the lowering — leader escalation, the
    ;; narrowing prefix states and their re-minting providers — belongs to
    ;; (modaliser jump-list). What is VSCode's, and all that is passed in,
    ;; is how a project is named as a state, what pressing it does, and what
    ;; the narrowed listing draws.

    ;; The per-Visit assignment, written by the provider at come-to-rest and
    ;; read once the overlay's show delay elapses. One cell, for the same
    ;; reason paneru has one: the listing must render the exact assignment
    ;; the keypress dispatches through, never a re-query.
    (define *current-projects-assigned* '())

    (define (set-current-projects-assigned! assigned)
      (set! *current-projects-assigned* assigned))

    ;; A project's Terminal dispatch state id. Free-form — a Terminal state
    ;; deactivates before any presentation code consults a state id's shape
    ;; — so it needs collision-freedom across live targets and nothing else.
    ;; The window id supplies that, and the literal prefix namespaces it
    ;; against any other jump listing alive in the same Visit.
    ;;
    ;; Only ever called on a target `project-target-action` already answered
    ;; for, so the window id is known to be a number here.
    (define (project-target-state-id item)
      (string-append "vscode-project-target/"
                     (number->string (alist-ref item 'windowId))))

    ;; What pressing a project's label DOES — or #f when nothing does, which
    ;; is jump-list's own test for whether the row earns an edge at all. A
    ;; row missing either id still renders and still consumes its label, and
    ;; simply has no edge behind it: dropping it during ASSIGNMENT instead
    ;; would renumber every label below it on one transient enumeration
    ;; miss, and the labels are muscle memory.
    (define (project-target-action item)
      (and (number? (alist-ref item 'ownerPid))
           (number? (alist-ref item 'windowId))
           (lambda () (focus-window (focus-choice item)))))

    ;; (project-provider 'single-alphabet … 'leader-alphabet … 'second-alphabet …
    ;;                   ['panel-label STRING] ['enumerate THUNK])
    ;;   → a 1-arg procedure for a state's 'provider slot.
    ;;
    ;; All three alphabets come from the USER: jump labels are keys, and no
    ;; library file may author a key (ADR-0021). None is defaulted — an
    ;; omitted alphabet yields no labels rather than a library-chosen one.
    ;;
    ;; 'enumerate is the test seam: a 0-arg thunk returning Modaliser's
    ;; window enumeration, defaulting to the cross-space `list-windows` that
    ;; `window-source` already uses — so a project parked on another desktop
    ;; is labelled and reachable, which is the whole point when the windows
    ;; are one-per-worktree.
    ;;
    ;; OWNER-ID is the id of the state this provider was lowered onto, handed
    ;; over by the engine (provider-state-id-k9). It is the parent of every
    ;; prefix state minted below and their up-edge target.
    ;;
    ;; **This runs on the dispatch path**, re-run at every come-to-rest. It
    ;; is materially cheaper than paneru's — enumeration, filter, sort and
    ;; assign, with no subprocess spawn in it — but the enumeration is the
    ;; same 8-29ms warm and past 200ms cold accessibility sweep, and
    ;; KeyboardCapture filters no auto-repeat. So compose the ops on this
    ;; screen WITHOUT `'next 'self`, exactly as the paneru reference
    ;; composition does and for the same reason: a held key would queue
    ;; sweeps faster than they drain.
    (define (project-provider . opts)
      (let* ((alist       (apply props->alist opts))
             (single      (alist-ref alist 'single-alphabet '()))
             (leaders     (alist-ref alist 'leader-alphabet '()))
             (seconds     (alist-ref alist 'second-alphabet '()))
             (panel-label (alist-ref alist 'panel-label ""))
             (enumerate   (alist-ref alist 'enumerate list-windows)))
        (lambda (owner-id)
          (let* ((targets  (windows-of (enumerate)))
                 (assigned (jump-labels-assign targets single leaders seconds)))
            (set-current-projects-assigned! assigned)
            (jump-list-provider-result assigned owner-id panel-label
              'state-id project-target-state-id
              'action   project-target-action
              'block    (lambda (pairs)
                          (make-project-list-block
                            'assigned-fn (lambda () pairs))))))))

    ;; The un-narrowed panel's block, closed over the snapshot so it ALWAYS
    ;; renders the exact assignment project-provider took this Visit — never
    ;; re-querying. The user drops it into a panel of their VSCode screen.
    (define (project-listing)
      (make-project-list-block
        'assigned-fn (lambda () *current-projects-assigned*)))

    ;; ─── The chords ─────────────────────────────────────────────────

    (define (toggle-terminal) (send-keystroke '(ctrl) "`"))
    (define (focus-explorer)  (send-keystroke '(cmd shift) "e"))
    (define (focus-editor)    (send-keystroke '(cmd) "1"))

    ;; ─── Cycling the editor ───────────────────────────────────────────
    ;;
    ;; The two cycle chords, in the same shape as the three above: a
    ;; thunk over a chord VSCode ships by default. See the header for
    ;; what the commands behind them do at the ends of the list, across
    ;; editor groups, and inside the integrated terminal.
    (define (previous-editor) (send-keystroke '(cmd alt) "left"))
    (define (next-editor)     (send-keystroke '(cmd alt) "right"))

    ;; DIRECTION → the chord thunk that cycles that way. Pure, and the
    ;; single place the mapping lives, so `editor-cycler` cannot drift
    ;; from the two ops above. An unrecognised direction is `next`
    ;; rather than an error: a screen is built at config-load time, and
    ;; failing the whole config over a mistyped symbol costs more than
    ;; a key that cycles the wrong way and says so the first time it is
    ;; pressed.
    (define (cycle-thunk direction)
      (if (eq? direction 'previous) previous-editor next-editor))

    ;; (editor-cycler DIRECTION ['focus THUNK-or-#f] ['cycle THUNK])
    ;;
    ;; → a 0-arg thunk: focus the editor, then cycle. One op, because
    ;; the cycle chord alone leaves focus wherever it was — the header
    ;; records how that was established and why it is not obvious.
    ;;
    ;; 'focus is a PARAMETER because the right chord differs per user.
    ;; The default is `focus-editor`, VSCode's own cmd-1, which is
    ;; focusFirstEditorGroup and so lands on the LEFTMOST group rather
    ;; than the active one when several are open. A user who has bound
    ;; focusActiveEditorGroup in their keybindings.json passes a thunk
    ;; sending that chord instead and gets the exact behaviour. Passing
    ;; #f drops the focus step altogether.
    ;;
    ;; The focus step is sent UNCONDITIONALLY, because nothing here can
    ;; ask VSCode where focus is. That is correct as long as the focus
    ;; thunk is idempotent when the editor already has focus, which is
    ;; true of a strict-focus command and is why the caveat above
    ;; matters: cmd-1 pressed with a second group active MOVES you.
    ;;
    ;; 'cycle overrides the chord itself. It is the test seam — the
    ;; same role 'enumerate plays for `project-provider`, and for the
    ;; same reason, since sending a real keystroke reaches outside the
    ;; process (ADR-0023) — and it doubles as the escape hatch for a
    ;; user who has bound their own cycling command by hand.
    (define (editor-cycler direction . opts)
      (let* ((alist (apply props->alist opts))
             (focus (alist-ref alist 'focus focus-editor))
             (cycle (alist-ref alist 'cycle (cycle-thunk direction))))
        (lambda ()
          (when focus (focus))
          (cycle))))

    ;; ═══ The workspace surface ══════════════════════════════════════
    ;;
    ;; See the header for what this file is and why it is read the way
    ;; it is read.

    (define (state-file-path)
      (string-append (or (get-environment-variable "HOME") "")
                     "/Library/Application Support/Code/User"
                     "/globalStorage/storage.json"))

    ;; ─── Slicing the array out (pure) ───────────────────────────────
    ;;
    ;; The state file is ~100 KB and the four hundred bytes that matter
    ;; sit in its last 5%. See the header for the measurement; the job
    ;; here is to hand json-parse the array alone.
    ;;
    ;; Two literals, both unique in a real state file. `windowsState`
    ;; anchors the search so that an `openedWindows` appearing inside
    ;; some unrelated stored value earlier in the document cannot shadow
    ;; the real one.

    (define state-object-key "\"windowsState\"")
    (define state-array-key  "\"openedWindows\"")

    ;; Index of NEEDLE in HAY at or after START, or #f. Both are CHAR
    ;; VECTORS, never strings: indexing a LispKit string bridges the
    ;; whole string per access, which turns one scan of a 100 KB
    ;; document into a quadratic one — the cliff (modaliser json)'s own
    ;; header records in detail, and the reason everything below reads
    ;; a vector this library bridges exactly once.
    (define (chars-match-at? hay ndl i)
      (let ((nn (vector-length ndl)))
        (let match ((k 0))
          (cond ((= k nn) #t)
                ((char=? (vector-ref hay (+ i k)) (vector-ref ndl k))
                 (match (+ k 1)))
                (else #f)))))

    (define (chars-index-of hay ndl start)
      (let ((hn (vector-length hay))
            (nn (vector-length ndl)))
        (let loop ((i start))
          (cond ((> (+ i nn) hn) #f)
                ((chars-match-at? hay ndl i) i)
                (else (loop (+ i 1)))))))

    ;; The same search, walking BACKWARDS from the end.
    ;;
    ;; Direction is a speed heuristic and nothing else: the anchor key is
    ;; unique in the document — which is what makes the search meaningful
    ;; at all — so both directions find the same occurrence. What differs
    ;; is how much of a ~100 KB file gets walked to reach it, and
    ;; `windowsState` sits in the last 5%: measured, the forward scan
    ;; spent ~490 ms getting there on a release build, and the backward
    ;; one ~30 ms. If VSCode ever moves the key to the front this becomes
    ;; the slow direction, which is exactly where the forward scan
    ;; already was — the bet is one-sided, not a risk.
    (define (chars-last-index-of hay ndl)
      (let ((hn (vector-length hay))
            (nn (vector-length ndl)))
        (let loop ((i (- hn nn)))
          (cond ((< i 0) #f)
                ((chars-match-at? hay ndl i) i)
                (else (loop (- i 1)))))))

    ;; From FROM (just past a key literal), the index of the `[` that
    ;; opens that key's value — or #f if what follows is not an array.
    ;; Only a colon and whitespace may intervene, which is what makes
    ;; this a bounded look-ahead rather than a hunt: a key whose value
    ;; is an object or a string stops here instead of matching some
    ;; later, unrelated bracket.
    (define (array-open chars from n)
      (let skip ((i from))
        (cond
          ((>= i n) #f)
          ((char=? (vector-ref chars i) #\[) i)
          ((or (char=? (vector-ref chars i) #\:)
               (char-whitespace? (vector-ref chars i)))
           (skip (+ i 1)))
          (else #f))))

    ;; Index of the `]` matching the `[` at OPEN, or #f. Depth-counting
    ;; with string awareness: a `]` inside a JSON string is text, and a
    ;; backslash inside a string escapes whatever follows — including a
    ;; quote, which is how a Windows-style path or an escaped quote in a
    ;; window title would otherwise end the string early and throw the
    ;; depth count off for the rest of the document.
    (define (array-close chars open n)
      (let loop ((i (+ open 1)) (depth 1) (in-string #f) (escaped #f))
        (if (>= i n)
            #f
            (let ((c (vector-ref chars i)))
              (cond
                (escaped                        (loop (+ i 1) depth in-string #f))
                ((and in-string (char=? c #\\)) (loop (+ i 1) depth #t #t))
                ((char=? c #\")                 (loop (+ i 1) depth (not in-string) #f))
                (in-string                      (loop (+ i 1) depth #t #f))
                ((char=? c #\[)                 (loop (+ i 1) (+ depth 1) #f #f))
                ((char=? c #\])
                 (if (= depth 1) i (loop (+ i 1) (- depth 1) #f #f)))
                (else                           (loop (+ i 1) depth #f #f)))))))

    ;; TEXT → the JSON text of windowsState.openedWindows, or "". Every
    ;; way of not finding it — no such key, a value that is not an
    ;; array, a truncated document — yields "", because a state file
    ;; Modaliser cannot read is the same ordinary outcome as a window
    ;; that is not in it.
    (define (opened-windows-json text)
      (let* ((chars (string->vector text))
             (n     (vector-length chars))
             (ws    (chars-last-index-of chars (string->vector state-object-key)))
             (ow    (and ws (chars-index-of chars
                                            (string->vector state-array-key)
                                            ws)))
             (open  (and ow (array-open chars
                                        (+ ow (string-length state-array-key))
                                        n)))
             (close (and open (array-close chars open n))))
        (if close (vector->string chars open (+ close 1)) "")))

    ;; ─── file:// URIs → paths (pure) ────────────────────────────────

    (define (hex-digit c)
      (cond ((and (char>=? c #\0) (char<=? c #\9)) (- (char->integer c) 48))
            ((and (char>=? c #\a) (char<=? c #\f)) (+ 10 (- (char->integer c) 97)))
            ((and (char>=? c #\A) (char<=? c #\F)) (+ 10 (- (char->integer c) 65)))
            (else #f)))

    (define (bytes->text lst)
      (let ((bv (make-bytevector (length lst))))
        (let fill ((k 0) (rest lst))
          (if (null? rest)
              (utf8->string bv)
              (begin (bytevector-u8-set! bv k (car rest))
                     (fill (+ k 1) (cdr rest)))))))

    ;; Percent-decoding. A RUN of %XX escapes is decoded together rather
    ;; than one at a time, because VSCode percent-encodes a URI byte by
    ;; byte: a folder named "café" arrives as "caf%C3%A9", two escapes
    ;; that are one character. Decoding them separately would produce
    ;; two replacement characters, and the folder name is a JOIN KEY —
    ;; a mangled one silently stops matching its window.
    (define (percent-decode s)
      (let* ((chars (string->vector s))
             (n     (vector-length chars)))
        (define (escape-at? j)
          (and (< (+ j 2) n)
               (char=? (vector-ref chars j) #\%)
               (hex-digit (vector-ref chars (+ j 1)))
               (hex-digit (vector-ref chars (+ j 2)))
               #t))
        (define (byte-at j)
          (+ (* 16 (hex-digit (vector-ref chars (+ j 1))))
             (hex-digit (vector-ref chars (+ j 2)))))
        (let loop ((i 0) (pieces '()))
          (cond
            ((>= i n) (apply string-append (reverse pieces)))
            ((escape-at? i)
             (let run ((j i) (bytes '()))
               (if (escape-at? j)
                   (run (+ j 3) (cons (byte-at j) bytes))
                   (loop j (cons (bytes->text (reverse bytes)) pieces)))))
            (else (loop (+ i 1)
                        (cons (string (vector-ref chars i)) pieces)))))))

    (define file-uri-prefix "file://")

    ;; A stored folder URI → an absolute local path, or #f. #f covers
    ;; both a non-string (a malformed entry) and a URI this operation
    ;; has no path for — a remote window's `vscode-remote://…`, whose
    ;; folder does not exist on this machine at all.
    (define (folder-uri->path uri)
      (let ((plen (string-length file-uri-prefix)))
        (and (string? uri)
             (> (string-length uri) plen)
             (string=? (substring uri 0 plen) file-uri-prefix)
             (let ((rest (substring uri plen (string-length uri))))
               ;; A leading "/" is what distinguishes file:///path (no
               ;; authority, a local path) from file://host/path.
               (and (char=? (string-ref rest 0) #\/)
                    (guard (e (#t #f)) (percent-decode rest)))))))

    (define (path-basename path)
      (let ((segments (remove (lambda (s) (string=? s ""))
                              (string-split path "/"))))
        (if (null? segments) "" (car (reverse segments)))))

    ;; ─── The state file, read (pure) ────────────────────────────────
    ;;
    ;; TEXT → one entry per folder-rooted open window, in the file's own
    ;; order:
    ;;
    ;;   ((path . "/Users/me/Development/thing") (name . "thing"))
    ;;
    ;; Windows with no folder are simply absent: an empty window has no
    ;; `folder` key, and a multi-root window carries a `workspace`
    ;; instead — neither has a single directory to be the answer to
    ;; "which worktree is this", so neither is one.
    (define (workspaces-of text)
      (let ((slice (opened-windows-json text)))
        (if (string=? slice "")
            '()
            (let ((entries (guard (e (#t #f)) (json-parse slice))))
              (if (not (vector? entries))
                  '()
                  (let loop ((i 0) (acc '()))
                    (if (>= i (vector-length entries))
                        (reverse acc)
                        (let* ((entry (vector-ref entries i))
                               (path  (folder-uri->path
                                        (json-ref entry "folder"))))
                          (loop (+ i 1)
                                (if path
                                    (cons (list (cons 'path path)
                                                (cons 'name (path-basename path)))
                                          acc)
                                    acc))))))))))

    ;; ─── The join (pure) ────────────────────────────────────────────
    ;;
    ;; TITLE × WORKSPACES → the workspace that window is rooted at, or
    ;; #f. Every em-dash segment of the title is tested against the
    ;; folder NAMES, last segment first — last because that is where the
    ;; folder sits under the default profile, and every segment because
    ;; under a named profile it is the second-to-last instead, and
    ;; because a user-set `window.title` can put it anywhere. The title
    ;; only ever supplies a name to match; the PATH always comes from
    ;; the state file, so no directory-naming convention is load-bearing
    ;; here.
    ;;
    ;; Two open windows on same-named folders in different parents are
    ;; genuinely ambiguous from a title, and the earlier one in the
    ;; state file wins. That is a real limit, not a hidden one: rename
    ;; one, or set `window.title` to include more of the path.
    (define (workspace-for-title title workspaces)
      (let loop ((segments (reverse (map string-trim
                                         (string-split (or title "")
                                                       title-separator)))))
        (if (null? segments)
            #f
            (or (find (lambda (w) (equal? (car segments) (alist-ref w 'name)))
                      workspaces)
                (loop (cdr segments))))))

    ;; ID × ENUMERATION → the title of the VSCode window with that id,
    ;; or #f. Pure; the live half is focused-workspace-path below. A
    ;; window id of 0 is the enumeration's "could not resolve" sentinel
    ;; and never matches, so a cold-AX miss reads as "no title" rather
    ;; than joining every unresolved window together.
    (define (title-of-window-id id enumeration)
      (and (number? id)
           (not (= id 0))
           (let ((hit (find (lambda (w)
                              (and (equal? bundle-id (alist-ref w 'icon))
                                   (equal? id (alist-ref w 'windowId))))
                            enumeration)))
             (and hit (alist-ref hit 'text)))))

    ;; ─── The impure edges ───────────────────────────────────────────

    (define (open-workspaces)
      (workspaces-of (read-file-text (state-file-path))))

    ;; The frontmost VSCode window's folder, as an absolute path, or #f.
    ;; #f is an ordinary answer with several ordinary causes — the front
    ;; window is not VSCode's, it is an empty or multi-root window, or
    ;; it opened since the state file was last written. A caller decides
    ;; what to say about that; this library does not decide for it.
    (define (focused-workspace-path)
      (let ((focused (focused-window)))
        (and (pair? focused)
             (let ((title (title-of-window-id (alist-ref focused 'windowId)
                                              (list-windows))))
               (and title
                    (let ((w (workspace-for-title title (open-workspaces))))
                      (and w (alist-ref w 'path))))))))

    ;; ─── Opening a file ═════════════════════════════════════════════


    ;; PATH → the command that opens it (pure). No flags, deliberately:
    ;; `-r` would force the LAST ACTIVE window, which is precisely the
    ;; wrong window, and `-n` a new one. See the header for the routing
    ;; a bare invocation gets instead.
    (define (open-file-command path)
      (string-append tool-path-prefix "code '" (sq-escape path) "' 2>/dev/null"))

    ;; (reveal-file! path)        → open PATH, then focus-explorer
    ;; (reveal-file! path after)   → open PATH, then call AFTER
    ;;
    ;; Open PATH and land the explorer on it.
    ;;
    ;; ASYNCHRONOUS, and the ordering is the point. Measured on the
    ;; developer's machine, `code <file>` against a running instance
    ;; takes ~1.1 s to return — a synchronous run-shell here would hold
    ;; the thread that owns the CGEvent tap for that whole second, which
    ;; is exactly ADR-0014's stalled-tap hazard. Running the follow-up
    ;; from the callback also puts it after the open rather than racing
    ;; it, which is why "focus the explorer yourself afterwards" is not
    ;; an equivalent the caller can write.
    ;;
    ;; The explorer SELECTS the file without being asked: VSCode's
    ;; `explorer.autoReveal` defaults to true, so by the time the
    ;; explorer takes focus the tree has already revealed and selected
    ;; whatever the editor opened. Pin the setting explicitly if you
    ;; depend on it — an inherited default is not a promise.
    ;;
    ;; AFTER exists because WHICH chord reaches the explorer is not a
    ;; fact about VSCode on every machine. The default `focus-explorer`
    ;; is VSCode's own shift-cmd-e, which is correct for a stock install
    ;; but bounces to the EDITOR when the explorer already has focus
    ;; (see above) — so anyone who has bound a strict-focus command in
    ;; their own keybindings.json passes that instead. Preference stays
    ;; the caller's (ADR-0021).
    ;;
    ;; A non-string or empty PATH does nothing at all, so a caller may
    ;; pass a resolution that failed straight through.
    (define (reveal-file! path . after)
      (when (and (string? path) (not (string=? path "")))
        (let ((follow-up (if (and (pair? after) (procedure? (car after)))
                             (car after)
                             focus-explorer)))
          (run-shell-async (open-file-command path)
                           (lambda (code out err) (follow-up))))))))
