;; (modaliser apps vscode) — Visual Studio Code (com.microsoft.VSCode)
;; utilities.
;;
;; VSCode as an application seen FROM OUTSIDE exposes no scripting
;; dictionary and no IPC socket worth the name, so most of what is here
;; is built from two things Modaliser already has: the window
;; enumeration, and synthetic keystrokes onto VSCode's own default
;; chords.
;;
;; That framing is right about the outside and wrong as a whole, and
;; ADR-0026 is where it was corrected. VSCode's EXTENSION API is a
;; first-class, versioned surface onto exactly the state that is out of
;; reach from outside — what is open inside one window — and its
;; extension host is an ordinary Node process, so the missing IPC was
;; missing only until someone wrote the peer. The last section of this
;; library is Modaliser's half of that conversation.
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
;;   (code:vscode-parts)
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

;; ─── What is open INSIDE a window: the companion extension ──────────
;;
;; Everything above reads VSCode from outside. Nothing outside VSCode
;; can say what is open *inside* one window — its editor tabs, its
;; terminals — because VSCode ships no scripting dictionary and the IPC
;; socket its own CLI uses is private and unversioned. Its EXTENSION
;; API does carry exactly that state (`window.terminals`,
;; `window.tabGroups`), so Modaliser runs a small peer inside each
;; window and asks it. Reading a RENDERING of that state through the
;; accessibility tree was designed, reviewed and rejected on what the
;; rendering costs (ADR-0026, considered options).
;;
;; The peer is `vscode-extension/` in this repository. It SHIPS INSIDE
;; `Modaliser.app` — `build-app.sh` builds it into `Contents/Resources`
;; — and Modaliser copies it into `~/.vscode/extensions` only when the
;; user presses a row and confirms (ADR-0028). Nothing writes there on
;; Modaliser's initiative. The last section of this library is that op.
;; It is bundled rather than left to a script because the release
;; tarball is `Modaliser.app`, `README.md` and `LICENSE`, so a cask user
;; has no `scripts/` directory; the cost is the extension's independent
;; upgrade cadence, which that decision spends knowingly.
;;
;; It is still NOT covered by `build-app.sh`'s exact-mirror invariant
;; (ADR-0019), which stops at `Scheme/`: the payload's freshness is
;; structural — it is compiled by the step immediately before the copy —
;; rather than checked, and an INSTALLED copy can be older than the
;; bundled one, which is exactly what the install row's gate notices.
;;
;; THE TRANSPORT IS NOT NEW. It is ADR-0020's, built for herdr and
;; reused unchanged: newline-delimited JSON over a Unix-domain socket,
;; one `{"id","method","params"}` request per connection, the peer
;; closing after it responds, `unix-socket-request` owning the framing
;; in both directions. (modaliser muxes herdr-socket) is the worked
;; model and this follows its shape deliberately rather than inventing
;; a second one — including its parameter-defaults-to-#f discipline,
;; which is what keeps `swift test` structurally unable to dial a live
;; editor (ADR-0023).
;;
;; FOUR METHODS, AND THE SET IS THE SECURITY SURFACE. `parts` is a
;; query and is answered; `focus-terminal`, `focus-editor`, and
;; `close-editor-if-missing` are
;; NOTIFICATIONS and are answered with nothing at all (ADR-0014 — no
;; caller consumes an acknowledgement, so waiting for one would spend
;; the eval thread's time, and the keyboard tap's, on a discarded
;; value). There is deliberately no method that runs a workbench
;; command; ADR-0026 enumerates what the bounded set exposes and
;; accepts.
;;
;; WHICH WINDOW A READ GOES TO, AND WHICH WINDOW AN ACT GOES TO, ARE
;; DIFFERENT QUESTIONS (ADR-0027). The extension host is per-window, so
;; there are several peers. A read is addressed through a last-focused
;; POINTER FILE that each window's extension rewrites when its window
;; takes focus. An act is addressed through the `peer` path the READ's
;; own reply carried — never the pointer read a second time, because
;; every window's token counter starts at the same place, so a pointer
;; that moved between the read and the press would deliver window A's
;; token to window B, where it RESOLVES, to a different tab. The read
;; and the act name the same peer because the act's address came out of
;; the read. That is why `vscode-query`/`vscode-notify` take the socket
;; path as an ARGUMENT and only `vscode-parts` resolves the pointer.
;;
;; A 200 ms READ TIMEOUT, NOT herdr's 1000. The budget that matters is
;; the whole come-to-rest: only `parts` waits, a screen reads once per
;; panel, and a blocked eval thread is a blocked keyboard tap
;; (ADR-0014). Two panels at herdr's second apiece would be two seconds
;; of that; 200 ms is still ~300x the 0.1-0.6 ms wire time herdr
;; measures, so a healthy peer never notices it and a wedged one costs
;; a bounded fraction of a press. herdr's ceiling is right for a peer
;; Modaliser launched and can be sure of; this peer's event loop is
;; shared with every other extension in the window.
;;
;; EVERY MISS IS AN EMPTY LISTING, NEVER A WRONG ONE. Extension not
;; installed, not yet activated, disabled for the profile, a stale
;; pointer, a crashed host, a protocol skew, a reply from a window that
;; is no longer focused — every one of them ends at #f here, and #f is
;; no rows. A window with NO FOLDER OPEN is deliberately not on that
;; list: it is an ordinary peer with a null `workspace`.

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
          cycle-thunk

          ;; ── The companion extension's transport ───────────────────
          ;;      (vscode-companion-extension-k12)
          ;; How Modaliser reaches the peer running INSIDE a VSCode
          ;; window. See the header for the protocol, the addressing
          ;; and why the timeout is 200 ms rather than herdr's second.
          ;;
          ;; Where the last-focused pointer file is. The parameter's
          ;; default is #f — "no VSCode extension configured" — and the
          ;; HOST installs the real path at boot (root.scm), exactly as
          ;; it installs the herdr socket path. That default is what
          ;; keeps `swift test` structurally unable to dial a live
          ;; editor (ADR-0023): with no pointer there is no socket path,
          ;; and every runner below takes its path as an argument.
          current-vscode-socket-pointer-path
          vscode-default-socket-pointer-path
          ;; The protocol version this Modaliser understands. A reply
          ;; that does not carry it is treated as an unreachable peer:
          ;; the two halves are installed separately and can skew.
          vscode-protocol-version
          ;; The two transports, exported so a test can exercise the
          ;; REAL envelope and parse path rather than only the seams.
          ;;   (vscode-socket-request PEER METHOD PARAMS) → envelope|#f
          ;;   (vscode-socket-send    PEER METHOD PARAMS) → #t|#f
          vscode-socket-request
          vscode-socket-send
          ;; The two seams, and the dispatchers that go through them.
          ;; TWO rather than one, for the reason (modaliser unix-socket)
          ;; has two primitives: a deliberately abandoned reply must not
          ;; be indistinguishable from a timeout. The query seam is
          ;; where a test hands back canned JSON; the notify seam is
          ;; where a test asserts which bytes went to which peer, which
          ;; is how the peer-binding invariant is pinned at all.
          current-vscode-query-runner
          current-vscode-notify-runner
          vscode-query
          vscode-notify
          ;; (vscode-parts) → the `parts` RESULT object, or #f. Impure:
          ;; reads the pointer file and does one round-trip.
          vscode-parts

          ;; ── The Terminal and Editor panels (vscode-part-panels-k7) ──
          ;; The same jump-label shape the Projects panel has, one level
          ;; in: the parts of the FRONTMOST window rather than the open
          ;; windows. Two panels, two alphabets, two `parts` round-trips
          ;; per come-to-rest (bounded at 200 ms each, not memoised —
          ;; docs/specs/vscode-window-parts.md decision 5).
          ;;
          ;; The PURE joins, and where every behavioural test of either
          ;; listing lands: a parsed `parts` result → targets, each
          ;; carrying the reply's own `peer` path beside its token.
          ;;   (terminal-rows PARTS) → Terminal targets
          ;;   (editor-rows PARTS)   → Editor targets
          terminal-rows
          editor-rows
          ;; (shorten-path PATH WORKSPACE) → PATH with the workspace
          ;; prefix off, or PATH. Pure, and exported because the
          ;; folderless and outside-the-workspace cases are the ones
          ;; worth pinning by name.
          shorten-path
          ;; The impure sources: (… -rows (vscode-parts)), '() on a miss.
          terminal-source
          editor-source
          ;; The actions. One fire-and-forget notification to the
          ;; TARGET'S OWN peer, carrying its token. Nothing is waited for
          ;; and nothing is returned (ADR-0014).
          focus-terminal!
          focus-editor-tab!
          close-editor-if-missing!
          ;; The Edge providers a screen binds, and the block specs its
          ;; panels draw — the same pair as project-provider /
          ;; project-listing, and the same contract: the listing reads
          ;; the snapshot its provider took this Visit, so the rows and
          ;; the live labels cannot disagree.
          terminal-provider
          terminal-listing
          editor-provider
          editor-listing

          ;; ── Installing the companion (vscode-companion-install-k18) ─
          ;; ADR-0028: the extension ships inside the .app and is copied
          ;; into ~/.vscode/extensions only on the user's confirmed
          ;; request. The user's config binds the key and the label
          ;; (ADR-0021); this library carries the op and the gate.
          ;;
          ;; Where the payload is, is HOST knowledge. The parameter's
          ;; default is #f — "no payload in this build" — and root.scm
          ;; installs the real path at boot, exactly as it installs the
          ;; socket pointer above. Un-configured, the predicate answers
          ;; not-installed and the op is a no-op that logs why, which is
          ;; what keeps `swift test` away from both the bundle and
          ;; ~/.vscode (ADR-0023).
          current-vscode-companion-payload-dir
          ;; (companion-installed?) → is THIS build's version already in
          ;; ~/.vscode/extensions. Cached; pair it with a row as a
          ;; 'hidden gate and the row retires itself, returning when an
          ;; upgrade ships a newer payload than what is on disk.
          companion-installed?
          ;; (install-companion!) → confirm, copy, re-probe. Idempotent.
          install-companion!
          ;; The pure halves, which is where the tests land:
          ;;   (companion-identity)         → '<publisher>.<name>-<ver>'
          ;;   (companion-install-dir)      → where it would land
          ;;   (companion-install-command)  → what would be spawned
          ;;   (companion-install-succeeded? TRANSCRIPT) → did it work
          companion-identity
          companion-install-dir
          companion-install-command
          companion-install-succeeded?)
  (import (scheme base)
          (scheme char)
          ;; get-environment-variable, for $HOME in the state-file path.
          ;; R7RS, so it costs the portable surface nothing — the same
          ;; import (modaliser muxes herdr-socket) makes for its socket.
          (only (scheme process-context) get-environment-variable)
          (modaliser util)
          (only (modaliser json) json-parse json-ref json-write)
          ;; The press stopwatch, split into wire time and parse time
          ;; exactly as the herdr transport splits it — so a read that
          ;; starts costing seconds says which half grew. k6's cost
          ;; conclusion had to be withdrawn because its instrument was a
          ;; standalone binary nobody committed; this one ships.
          (only (modaliser instrument)
                instrument-enabled? instrument-note instrument-span
                instrument-sample!)
          ;; The native AF_UNIX round-trip (ADR-0020). Swift owns the
          ;; socket and knows nothing of the envelope; the framing,
          ;; parsing and error mapping are all here. The same import
          ;; (modaliser muxes herdr-socket) makes, and quarantined the
          ;; same way — by a parameter that defaults to unconfigured.
          (modaliser unix-socket)
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
          ;; The listing renderers. The dependency runs THIS way only: a
          ;; block is a generic labelled-row component that knows nothing of
          ;; VSCode, and this library composes it. TWO blocks and three
          ;; panels: the Projects panel's row is one long worktree name in
          ;; the full width, and both part panels' rows are a short name
          ;; with a path trailing it — one presentation with two callers,
          ;; which is why blocks/part-list is not written twice.
          (only (modaliser blocks project-list) make-project-list-block)
          (only (modaliser blocks part-list) make-part-list-block)
          ;; sq-escape: the canonical POSIX single-quote escaper — a path
          ;; out of an editor's stored state, or out of a bundle that may
          ;; sit anywhere, is arbitrary text going into a shell word.
          ;; dialog-confirm: the companion install is a confirmed act and
          ;; never happens without one (ADR-0028).
          (only (modaliser dialogs) sq-escape dialog-confirm dialog-info)
          ;; log-line: the one Scheme-facing diagnostic primitive. A
          ;; confirmed write that fails must say so where an installed .app
          ;; can be queried — (modaliser util)'s `log` reaches the context
          ;; delegate's NSLog and is invisible there.
          (modaliser log)
          (only (modaliser shell) run-shell run-shell-async)
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
                           (lambda (code out err) (follow-up))))))

    ;; ─── The companion extension's transport ────────────────────────
    ;;
    ;; Shaped after (modaliser muxes herdr-socket) deliberately — see
    ;; the header. What differs, and why, is noted at each definition.

    ;; The wire contract's version, checked on every reply. Modaliser
    ;; and the extension are installed separately (ADR-0026), so skew
    ;; is an ordinary condition rather than a fault: a mismatch is
    ;; treated as an unreachable peer — empty listing, log line, and no
    ;; attempt to interpret fields whose meaning is not agreed.
    (define vscode-protocol-version 1)

    ;; Where the extension writes the socket path of whichever window
    ;; last took focus. Both halves hard-code `~/.config/modaliser` —
    ;; SchemeEngine does not honour $XDG_CONFIG_HOME, so honouring it
    ;; on one side only would put the two in different directories.
    ;; The directory is created 0700 by the extension, which is what
    ;; keeps the sockets and this file out of another user's reach.
    ;;
    ;; An unset $HOME yields a path that cannot exist, and the read
    ;; then degrades to #f exactly as an absent extension does.
    (define (vscode-default-socket-pointer-path)
      (string-append (or (get-environment-variable "HOME") "")
                     "/.config/modaliser/vscode/focused"))

    ;; **#f — no VSCode extension configured — is the default, and the
    ;; host installs the real path** (`root.scm`). The inert default is
    ;; the quarantine, not tidiness: with no pointer path there is no
    ;; socket path, and every runner below takes its peer as an
    ;; argument rather than resolving one, so a bare `SchemeEngine()`
    ;; — which is every test — has no path by which to reach a live
    ;; editor (ADR-0023). It stays a parameter so a test can point the
    ;; REAL transport at a throwaway responder socket.
    (define current-vscode-socket-pointer-path (make-parameter #f))

    ;; Wall-clock bound on a whole round-trip. 200 ms, not herdr's
    ;; 1000 — see the header for the come-to-rest budget that decides
    ;; it. Only `parts` ever waits this long; the notification path
    ;; bounds only its connect+send, which against a local peer is
    ;; sub-millisecond.
    (define vscode-socket-timeout-ms 200)

    ;; The envelope, built in one place for both transports.
    ;; `json-write` owns the escaping, so a token and a method name are
    ;; escaped by the same code as everything else.
    (define (vscode-request-line method params)
      (json-write (list (cons "id" "modaliser")
                        (cons "method" method)
                        (cons "params" params))))

    ;; PEER is a socket path — the pointer's contents for a read, the
    ;; reply's own `peer` field for an act (ADR-0027). It is an
    ;; argument rather than something the transport resolves, and that
    ;; is the whole of the addressing decision expressed in a signature.
    ;;
    ;; **#f means the peer did not answer** — no socket there, a
    ;; timeout, or a reply that would not parse — and nothing raises: a
    ;; leader press must not raise. A structured `{"error":…}` reply is
    ;; NOT #f: the peer answered and said something specific, so it
    ;; comes back as the envelope, logged. Callers read
    ;; `(json-ref j "result")`, which an error envelope has not got,
    ;; and `json-ref` is total — so an error degrades to the same #f
    ;; every caller already handles.
    (define (vscode-socket-request peer method params)
      (if (not (string? peer))
          (begin (log "vscode: " method " — no peer to dial") #f)
          (let ((reply (instrument-span 'vscode-wire
                         (lambda ()
                           (unix-socket-request
                             peer
                             (vscode-request-line method params)
                             vscode-socket-timeout-ms)))))
            (if (not (string? reply))
                #f                      ; the primitive already logged why
                (let ((parsed
                        (begin
                          (when (instrument-enabled?)
                            (let ((n (string-length reply)))
                              (instrument-sample! 'vscode-reply reply n)
                              (instrument-note 'vscode method 'reply-chars n)))
                          (instrument-span 'vscode-parse
                            (lambda ()
                              (guard (e (#t #f)) (json-parse reply)))))))
                  (cond
                    ((not parsed)
                     (log "vscode: " method " — unparseable reply: " reply)
                     #f)
                    ((json-ref parsed "error")
                     => (lambda (err)
                          (log "vscode: " method " failed: "
                               (or (json-ref err "message") ""))
                          parsed))
                    (else parsed)))))))

    ;; The no-reply sibling: connect, send, close, never read. The peer
    ;; answers a notification with nothing at all, so there is no reply
    ;; to abandon — this is the shape ADR-0014 asks for rather than an
    ;; optimisation over waiting.
    ;;
    ;; **Nothing acts on the result and the failure is still logged.**
    ;; `unix-socket-send` returns #f when the bytes never reached a
    ;; socket at all, which is precisely the dangling-path case a stale
    ;; target produces; discarding that would leave "the peer refused
    ;; this" and "there was no peer" indistinguishable even in
    ;; Modaliser's own log, for nothing. One log line, no behaviour.
    (define (vscode-socket-send peer method params)
      (if (not (string? peer))
          (begin (log "vscode: " method " — no peer to dial") #f)
          (let ((sent (unix-socket-send peer
                                        (vscode-request-line method params)
                                        vscode-socket-timeout-ms)))
            (or sent
                (begin (log "vscode: " method " — no peer at " peer) #f)))))

    ;; ─── The two seams ──────────────────────────────────────────────
    ;;
    ;; TWO, not one, for the reason (modaliser unix-socket) has two
    ;; primitives: a deliberately abandoned reply must not be
    ;; indistinguishable from a timeout. The read side's seam is where
    ;; a test hands back canned JSON. The act side's is where a
    ;; recording runner pins the peer-binding invariant — build targets
    ;; from a reply whose `peer` is one path and assert the action was
    ;; addressed to THAT path and no other. Without that assertion
    ;; ADR-0027 is an assertion again, which this design has already
    ;; been caught at once.
    (define current-vscode-query-runner (make-parameter vscode-socket-request))
    (define current-vscode-notify-runner (make-parameter vscode-socket-send))

    (define (vscode-query peer method params)
      ((current-vscode-query-runner) peer method params))

    (define (vscode-notify peer method params)
      ((current-vscode-notify-runner) peer method params))

    ;; The focused window's socket path, or #f. One `read-file-text`
    ;; against the pointer file — the portable tree has no directory
    ;; listing, and needs none, because the extension names the file
    ;; and Modaliser only reads it (ADR-0027).
    ;;
    ;; Consulted to START a read and never again: every act goes to the
    ;; `peer` the reply itself carried, so a pointer that moves between
    ;; the read and the press cannot redirect an action.
    (define (vscode-focused-peer)
      (let ((pointer (current-vscode-socket-pointer-path)))
        (and (string? pointer)
             (let ((text (string-trim (read-file-text pointer))))
               (and (not (string=? text "")) text)))))

    ;; (vscode-parts) → the `parts` RESULT object, or #f.
    ;;
    ;; The RESULT, not the whole envelope: an error envelope, a
    ;; protocol skew and a lost window are all already collapsed to #f
    ;; here, so handing callers the envelope would buy them nothing but
    ;; a `json-ref` each. Callers read `peer`, `workspace`, `terminals`
    ;; and `editors` straight off what comes back.
    ;;
    ;; Three ways to get #f beyond "no answer", and all three are the
    ;; same outcome on screen — no rows, never wrong rows:
    ;;
    ;;   a PROTOCOL that is not the version this Modaliser understands.
    ;;   Interpreting fields whose meaning is not agreed is how a skew
    ;;   becomes a wrong jump instead of an empty panel.
    ;;
    ;;   a FOCUSED of false. This is the "row and action come from one
    ;;   snapshot and cannot disagree" contract applied to WINDOW
    ;;   identity: a stale pointer — a window that closed, a race —
    ;;   yields an empty listing rather than a neighbouring project's
    ;;   terminals. Note what it requires, which the screen already
    ;;   has rather than this adding: `window.state.focused` is false
    ;;   in every VSCode window while another application is frontmost,
    ;;   and the overlay is created non-activating (`ui/overlay.scm`,
    ;;   'activating #f) so VSCode keeps focus through the whole modal.
    ;;   A screen that rendered these rows through the CHOOSER instead
    ;;   would take that focus and the gate would reject every reply,
    ;;   with nothing in the protocol to explain it.
    ;;
    ;;   a reply with no `result` at all.
    (define (vscode-parts)
      (let ((peer (vscode-focused-peer)))
        (and peer
             (let ((envelope (vscode-query peer "parts" '())))
               (and envelope
                    (let ((result (json-ref envelope "result")))
                      (cond
                        ((not (list? result))
                         (log "vscode: parts — reply carried no result")
                         #f)
                        ((not (eqv? (json-ref result "protocol")
                                    vscode-protocol-version))
                         (log "vscode: parts — protocol "
                              (or (json-ref result "protocol") "?")
                              ", expected " vscode-protocol-version
                              "; reinstall the companion extension")
                         #f)
                        ((not (eq? (json-ref result "focused") #t))
                         (log "vscode: parts — the peer's window is not"
                              " focused; discarding the reply")
                         #f)
                        (else result))))))))

    ;; ─── The Terminal and Editor panels ─────────────────────────────
    ;;
    ;; (vscode-part-panels-k7, docs/specs/vscode-window-parts.md
    ;; decisions 4, 5 and 6.) The Projects panel one level in: the same
    ;; jump-label machinery over the parts of ONE window instead of over
    ;; the open windows. Everything below `vscode-parts` is pure, which
    ;; is the whole test story — a fixture captured off a real reply
    ;; drives every behavioural case, and no suite has a path to a live
    ;; editor (ADR-0023).

    ;; A TARGET is what the two joins produce, what a label dispatches
    ;; through, and what the row block draws. Its keys:
    ;;
    ;;   peer     the socket path THIS reply came from. Present on every
    ;;            target and read by every action.
    ;;   token    the peer's own integer, or #f when the row is inert.
    ;;   kind     'terminal or 'editor. Not on the wire — it is which
    ;;            join built the target, and it decides both the state-id
    ;;            namespace and which notification the action sends.
    ;;   text     the name drawn in the row's main column.
    ;;   detail   the dimmed trailing column: a cwd, or a path.
    ;;   current  VSCode's own active flag for this part.
    ;;   dirty    an editor's unsaved marker (always #f for a terminal).
    ;;   inert    no token, so no action and no edge.
    ;;   group    an editor's `viewColumn`, carried so a renderer MAY
    ;;            show it. Nothing addresses a group by it, and the
    ;;            listing offers no way to focus a group as such.
    ;;
    ;; **A target is (peer, token), never a token alone**, and that is
    ;; the load-bearing half. The counter is per-window and every window
    ;; has its own, so the integer 3 is live in as many windows as are
    ;; open; an action carrying only the integer would be an address
    ;; several windows answer to. Carrying the peer the reply itself
    ;; named means a row can only ever reach the window that drew it,
    ;; whatever the pointer file has done in between (ADR-0027).

    ;; A JSON null parses to the symbol `null`, and an absent key to #f
    ;; via json-ref — two ways to say "not there" that every reader here
    ;; has to collapse. These three do it once each.
    (define (field-string obj key)
      (let ((v (json-ref obj key)))
        (and (string? v) v)))

    (define (field-number obj key)
      (let ((v (json-ref obj key)))
        (and (number? v) v)))

    (define (field-true? obj key) (eq? (json-ref obj key) #t))

    ;; A JSON array parses to a VECTOR, so every listing crosses here.
    ;; A missing or null array degrades to no rows rather than raising,
    ;; which is the same empty listing every other miss produces.
    (define (field-rows obj key)
      (let ((v (json-ref obj key)))
        (if (vector? v) (vector->list v) '())))

    ;; (shorten-path PATH WORKSPACE) → PATH with WORKSPACE's prefix and
    ;; the separator after it removed, or PATH unchanged.
    ;;
    ;; Every row in a one-window listing shares the workspace prefix and
    ;; it is the least informative part of a forty-character path, so it
    ;; comes off. Two cases take the path UNCHANGED rather than being
    ;; special-cased away, and both are ordinary (spec decision 6):
    ;;
    ;;   a folderless window, where `workspace` is JSON null — a
    ;;   perfectly ordinary listing, not an empty one;
    ;;   a file opened from outside the workspace, whose path does not
    ;;   lie under the prefix at all.
    ;;
    ;; So the rule is SHORTEN WHERE THE PREFIX MATCHES, never assume it
    ;; matches. The separator is required as well as the prefix, or a
    ;; sibling directory sharing a name prefix (`…/Modaliser` against
    ;; `…/Modaliser.local-tree`) would have its leading characters
    ;; sliced off and the row would name a file that does not exist.
    (define (shorten-path path workspace)
      (if (not (and (string? path) (string? workspace)
                    (> (string-length workspace) 0)))
          (if (string? path) path "")
          (let* ((prefix (if (char=? (string-ref workspace
                                                 (- (string-length workspace) 1))
                                     #\/)
                             workspace
                             (string-append workspace "/")))
                 (plen   (string-length prefix)))
            (if (and (> (string-length path) plen)
                     (string=? (substring path 0 plen) prefix))
                (substring path plen (string-length path))
                path))))

    ;; PARTS (a parsed `parts` result) → Terminal targets, in
    ;; `window.terminals` order. Pure.
    ;;
    ;; Every terminal is actionable — `Terminal.show` reaches all of
    ;; them — so a terminal row is inert only if the peer somehow sent no
    ;; token, which is a protocol violation rather than a case. It is
    ;; still handled the same way an unfocusable tab is, because the
    ;; alternative is a label that raises instead of doing nothing.
    ;;
    ;; `current` is VSCode's `activeTerminal`, which is the terminal that
    ;; has focus OR MOST RECENTLY HAD IT — so it is set even with the
    ;; panel hidden, and it is not the same predicate as a tab's
    ;; `isActive`. Nothing here depends on it; the renderer marks it.
    (define (terminal-rows parts)
      (let ((peer      (field-string parts "peer"))
            (workspace (field-string parts "workspace")))
        (map (lambda (row)
               (let ((token (field-number row "token")))
                 (list (cons 'peer    peer)
                       (cons 'token   token)
                       (cons 'kind    'terminal)
                       (cons 'text    (or (field-string row "name") ""))
                       (cons 'detail  (shorten-path (field-string row "cwd")
                                                    workspace))
                       (cons 'current (field-true? row "active"))
                       (cons 'dirty   #f)
                       (cons 'inert   (not (and peer token))))))
             (field-rows parts "terminals"))))

    ;; PARTS → Editor targets, in `tabGroups.all` order and within each
    ;; group its own `tabs` order. Pure.
    ;;
    ;; The peer has already dropped a terminal dragged into the editor
    ;; grid from this list — it is a terminal, listed once, in the
    ;; terminal listing, where the action works — so there is no
    ;; filtering to do here. What DOES arrive is the inert row: a tab of
    ;; a kind with no specified, identity-preserving activation carries
    ;; `token: null` (spec decision 1). It is listed, it consumes its
    ;; label, and it has no action — so an unfocusable tab cannot
    ;; renumber the labels below it, and the panel cannot disagree with
    ;; the tab strip the human is looking at.
    ;;
    ;; The detail is the WHOLE workspace-relative path, not its
    ;; directory half. `Tab.label` is usually the basename but VSCode
    ;; disambiguates it when two tabs share one, so a directory-only
    ;; detail would sometimes repeat what the name already said and
    ;; sometimes be the only thing distinguishing two rows. The whole
    ;; path is the same answer every time, and the block ellipsizes it.
    ;;
    ;; A path of JSON null — the diff kinds carry two URIs and no single
    ;; one, a webview carries none — yields an empty detail and the name
    ;; owns the row.
    (define (editor-rows parts)
      (let ((peer      (field-string parts "peer"))
            (workspace (field-string parts "workspace")))
        (map (lambda (row)
               (let ((token (field-number row "token")))
                 (list (cons 'peer    peer)
                       (cons 'token   token)
                       (cons 'kind    'editor)
                       (cons 'text    (or (field-string row "label") ""))
                       (cons 'path    (field-string row "path"))
                       (cons 'detail  (shorten-path (field-string row "path")
                                                    workspace))
                       (cons 'current (field-true? row "active"))
                       (cons 'dirty   (field-true? row "dirty"))
                       (cons 'inert   (not (and peer token)))
                       (cons 'group   (field-number row "group")))))
             (field-rows parts "editors"))))

    ;; The impure sources. One `parts` round-trip each; `#f` — an
    ;; unreachable peer, a protocol skew, a reply from a window that is
    ;; no longer focused — becomes NO ROWS, never wrong rows.
    (define (terminal-source) (terminal-rows (vscode-parts)))
    (define (editor-source)   (editor-rows (vscode-parts)))

    ;; ─── The actions ────────────────────────────────────────────────
    ;;
    ;; One notification to the target's OWN peer, carrying its token.
    ;; Nothing is waited for and nothing is returned: the peer answers a
    ;; notification with nothing at all (ADR-0014), so there is no reply
    ;; to abandon.
    ;;
    ;; Every refusal is the peer's and is silent from here — a stale
    ;; token, a token of the other kind, a window that is no longer
    ;; focused. A refused press is indistinguishable from a delivered
    ;; one on this side, which is exactly the bargain the requirement
    ;; asks for: a label activates its own part OR NOTHING.
    ;;
    ;; The one failure that IS visible here is `vscode-socket-send`'s own
    ;; #f — the bytes reached no socket at all, which is what a stale
    ;; target produces — and it is logged inside the transport. Nothing
    ;; branches on it.
    (define (notify-part! target method)
      (vscode-notify (alist-ref target 'peer) method
                     (list (cons "token" (alist-ref target 'token)))))

    (define (focus-terminal! target)  (notify-part! target "focus-terminal"))
    (define (focus-editor-tab! target) (notify-part! target "focus-editor"))

    ;; Best effort, without waiting for the host's metadata check or close.
    ;; The snapshot filter is only an optimisation; the peer checks live state.
    (define (close-editor-if-missing! target)
      (unless (or (alist-ref target 'inert) (alist-ref target 'dirty))
        (guard (ex (else (log "vscode: missing-editor cleanup send failed")))
          (notify-part! target "close-editor-if-missing"))))

    ;; ─── The two providers ──────────────────────────────────────────

    ;; State ids. Free-form — a Terminal state deactivates before any
    ;; presentation code consults a state id's shape — so each needs
    ;; collision-freedom across live targets and nothing else. The
    ;; token supplies that WITHIN a window, and terminals and editors
    ;; draw from one counter, so a token is unique across both listings
    ;; of one reply; the literal prefixes namespace these against the
    ;; other jump listings that may be alive in the same Visit.
    ;;
    ;; Three namespaces were taken before these — vscode-project-target/,
    ;; paneru-strip-target/, herdr-jump-target/ — enumerated out of the
    ;; library tree rather than recalled. Enumerate them again before
    ;; adding a sixth: a collision here is silently last-wins in the
    ;; engine, which is precisely what jump-list-compose-providers now
    ;; refuses at the merge.
    ;;
    ;; Only ever called on a target whose action answered non-#f, so the
    ;; token is known to be a number here.
    (define (terminal-target-state-id target)
      (string-append "vscode-terminal-target/"
                     (number->string (alist-ref target 'token))))

    (define (editor-target-state-id target)
      (string-append "vscode-editor-target/"
                     (number->string (alist-ref target 'token))))

    ;; What pressing a part's label DOES — or #f when nothing does,
    ;; which is jump-list's own single test for whether the row earns an
    ;; edge at all. There is deliberately no separate focusability
    ;; predicate: the target with no action IS the target with no edge,
    ;; because it is the same call.
    ;;
    ;; An inert row still renders and still consumes its label. Dropping
    ;; it during ASSIGNMENT would renumber every label below it, and the
    ;; labels are muscle memory.
    (define (part-action target)
      (and (string? (alist-ref target 'peer))
           (number? (alist-ref target 'token))
           (if (eq? (alist-ref target 'kind) 'terminal)
               (lambda () (focus-terminal! target))
               (lambda () (focus-editor-tab! target)))))

    ;; The per-Visit snapshots, written by each provider at come-to-rest
    ;; and read once the overlay's show delay elapses. One cell per
    ;; panel, for the reason the Projects panel has one: the listing must
    ;; render the exact assignment the keypress dispatches through, never
    ;; a re-query — and here a re-query would be a second socket
    ;; round-trip against a window that may have changed.
    (define *current-terminals-assigned* '())
    (define *current-editors-assigned* '())

    ;; The block ids. TWO part listings can be alive on one screen, and a
    ;; panel's block reference resolves by `block-ref-id` — the block's
    ;; explicit 'id when it has one, its 'type otherwise. Both listings
    ;; are `part-list` blocks, so without distinct ids the reference is
    ;; ambiguous and resolve-display raises. These are machine
    ;; identifiers rather than labels: nothing the user reads (ADR-0021).
    (define terminal-block-id 'vscode-terminal-list)
    (define editor-block-id 'vscode-editor-list)

    ;; The shared body of both providers, differing only in the four
    ;; things that are actually per-panel: which join, which state-id
    ;; namespace, which snapshot cell and which block id. Written once
    ;; because this is machinery — and machinery duplicated between two
    ;; panels drifts silently, which is the whole reason
    ;; (modaliser jump-list) exists at all.
    ;;
    ;; **This runs on the dispatch path**, re-run at every come-to-rest,
    ;; and a screen carrying both panels does TWO `parts` round-trips per
    ;; press. That is the accepted shape — bounded rather than memoised.
    ;; What makes it safe is not the healthy-path number (a peer answers
    ;; in ~0.04 ms measured, against the 8-29 ms warm accessibility sweep
    ;; the Projects panel already runs on the same screen) but the 200 ms
    ;; per-request timeout, which puts the worst case at 400 ms of
    ;; blocked eval thread rather than at whatever a wedged extension
    ;; host feels like. A shared per-visit cache would need either a
    ;; visit generation the engine does not expose or a cell whose
    ;; invalidation nothing naturally drives; the `parts` reply already
    ;; carries both listings, so if a THIRD panel lands here the answer
    ;; is one shared read, not a shorter timeout (spec decision 5).
    ;;
    ;; The span is committed rather than a throwaway: k6's cost
    ;; conclusion had to be withdrawn because its instrument was a
    ;; standalone binary nobody kept, and the wire/parse split inside
    ;; `vscode-socket-request` is what makes a bad number here
    ;; diagnosable rather than merely bad.
    (define (part-provider span rows-fn state-id-fn cell-set! block-id . opts)
      (let* ((alist       (apply props->alist opts))
             (single      (alist-ref alist 'single-alphabet '()))
             (leaders     (alist-ref alist 'leader-alphabet '()))
             (seconds     (alist-ref alist 'second-alphabet '()))
             (panel-label (alist-ref alist 'panel-label ""))
             (enumerate   (alist-ref alist 'enumerate vscode-parts)))
        (lambda (owner-id)
          (instrument-span span
            (lambda ()
              (let* ((targets  (rows-fn (enumerate)))
                     (assigned (jump-labels-assign targets single leaders seconds)))
                (cell-set! assigned)
                (jump-list-provider-result assigned owner-id panel-label
                  'state-id state-id-fn
                  'action   part-action
                  'block    (lambda (pairs)
                              (make-part-list-block
                                'id          block-id
                                'assigned-fn (lambda () pairs))))))))))

    ;; (terminal-provider 'single-alphabet … 'leader-alphabet …
    ;;                    'second-alphabet … ['panel-label STRING]
    ;;                    ['enumerate THUNK])
    ;;   → a 1-arg procedure for a state's 'provider slot.
    ;;
    ;; All three alphabets come from the USER and NONE is defaulted:
    ;; jump labels are keys, and no library file may author a key
    ;; (ADR-0021). An omitted alphabet yields no labels rather than a
    ;; library-chosen one.
    ;;
    ;; 'enumerate is the test seam, a 0-arg thunk returning a parsed
    ;; `parts` result and defaulting to `vscode-parts` — so a test drives
    ;; the whole provider, label assignment and lowering and state ids
    ;; included, from a canned reply with no socket under it.
    ;;
    ;; OWNER-ID is the id of the state this provider was lowered onto,
    ;; handed over by the engine. It is the parent of every prefix state
    ;; minted below and their up-edge target.
    ;;
    ;; **A screen carrying more than one of these must compose them
    ;; through `jump-list-compose-providers`**, not by hand: a state has
    ;; one 'provider slot, and appending two results is silently wrong
    ;; when their keys or state ids collide.
    (define (terminal-provider . opts)
      (apply part-provider 'vscode-terminal-provider
             terminal-rows terminal-target-state-id
             (lambda (a) (set! *current-terminals-assigned* a))
             terminal-block-id opts))

    (define (editor-provider . opts)
      (apply part-provider 'vscode-editor-provider
             editor-rows editor-target-state-id
             (lambda (a) (set! *current-editors-assigned* a))
             editor-block-id opts))

    ;; The un-narrowed panels' blocks, each closed over the snapshot its
    ;; own provider took, so each ALWAYS renders the exact assignment
    ;; that provider took this Visit — never re-querying, which here
    ;; would mean a third and fourth socket round-trip against a window
    ;; that may have changed under them. The user drops each into a panel
    ;; of their VSCode screen.
    (define (terminal-listing)
      (make-part-list-block
        'id          terminal-block-id
        'assigned-fn (lambda () *current-terminals-assigned*)))

    (define (editor-listing)
      (make-part-list-block
        'id          editor-block-id
        'assigned-fn (lambda () *current-editors-assigned*)))

    ;; ─── Installing the companion (vscode-companion-install-k18) ────
    ;;
    ;; ADR-0028. The extension ships inside `Modaliser.app` and is copied
    ;; into `~/.vscode/extensions` only when the user presses a key and
    ;; confirms. Modaliser never writes there on its own initiative, in
    ;; any circumstance, and there is no opt-out to design because there
    ;; is nothing to opt out of.
    ;;
    ;; The op shape is `apps/kitty.sld`'s `configure!` — confirm,
    ;; provision through the portable shell seam, re-probe, tell the user
    ;; to relaunch the target app — and the shape is ALL that is
    ;; borrowed. kitty edits a text config and backs it up first; this
    ;; installs executable code into another application, where it
    ;; activates in every window that application opens and outlives
    ;; Modaliser's own uninstall. So the dialog says two things kitty's
    ;; has no need to, and they are not decoration: what is installed is
    ;; activating code, and a plain `brew uninstall` leaves it behind.
    ;;
    ;; WHERE THE PAYLOAD IS is host knowledge and cannot be named from
    ;; the portable tree, so it arrives as a parameter defaulting to #f —
    ;; the same quarantine as the socket pointer above, installed by
    ;; `root.scm` at boot. Un-configured, `companion-installed?` answers
    ;; *not installed* and `install-companion!` is a no-op that logs why:
    ;; a `swift run` never assembled a payload, and a bare
    ;; `SchemeEngine()` never runs `root.scm` at all, so `swift test`
    ;; reaches neither the bundle nor the extensions directory (ADR-0023).
    ;;
    ;; The EXISTENCE PROBE needs no seam of its own: it runs through
    ;; `run-shell`, which is already the inert-by-default seam and which
    ;; a test already installs a canned answer on. A second parameter
    ;; would be a second thing to keep inert and would buy no guarantee
    ;; the first does not already give.
    ;;
    ;; THREE PATHS, ONE PARAMETER. The bundle carries the payload
    ;; directory and two siblings derived from it by suffix — `.id`,
    ;; the `<publisher>.<name>-<version>` string this build ships, and
    ;; `.install.sh`, the single transcription of the sweep-and-copy
    ;; rule. The suffix derivation is why one parameter suffices and why
    ;; nothing here has to take a path apart: the portable tree has no
    ;; directory listing and does not index strings (ADR-0025, ADR-0027).
    ;;
    ;; WHY AN IDENTITY FILE AND NOT THE PAYLOAD'S OWN MANIFEST. The
    ;; predicate is read on every overlay render — a row gated on it is
    ;; re-evaluated each time the panel draws — so it must be cheap. One
    ;; `read-file-text` of a pre-computed line is; parsing a manifest is
    ;; not. `build-app.sh` stamps the file from that same manifest, so
    ;; there is still one source of truth.

    ;; A whole shell WORD: sq-escape handles the content, this adds the
    ;; quotes the content is escaped for. A bundle path is arbitrary text
    ;; the moment the .app is somewhere with a quote in its name.
    (define (sq-quote s)
      (string-append "'" (sq-escape s) "'"))

    (define current-vscode-companion-payload-dir (make-parameter #f))

    (define (companion-identity)
      (let ((dir (current-vscode-companion-payload-dir)))
        (and (string? dir)
             (let ((id (string-trim (read-file-text (string-append dir ".id")))))
               (and (not (string=? id "")) id)))))

    ;; Where an installed copy of THIS build's version would sit. The
    ;; only destination there is: VSCode Insiders and other variants keep
    ;; their extensions elsewhere and are out of scope (ADR-0028).
    (define (companion-install-dir)
      (let ((id (companion-identity)))
        (and id
             (string-append (or (get-environment-variable "HOME") "")
                            "/.vscode/extensions/" id))))

    ;; The command `install-companion!` would spawn. Pure, and exported
    ;; because it is where a test pins that the shipped sweep script is
    ;; what runs and that the payload is what it is pointed at.
    ;;
    ;; `2>&1` and the status echo are not decoration. `run-shell` hands
    ;; back STDOUT and nothing else — no exit code, no stderr — so
    ;; without these every way this can fail (a candidate directory the
    ;; sweep cannot remove, a full disk mid-copy, a tampered bundle with
    ;; no script in it) would be perfectly silent to a user who had just
    ;; confirmed a write. A user who consents to an act is owed the
    ;; outcome of it, so the status comes back on stdout where the one
    ;; seam this library has can see it.
    (define companion-status-prefix "modaliser-install-status=")

    (define (companion-install-command)
      (let ((dir (current-vscode-companion-payload-dir)))
        (and (string? dir)
             (string-append (sq-quote (string-append dir ".install.sh"))
                            " " (sq-quote dir)
                            " 2>&1; echo \"" companion-status-prefix "$?\""))))

    ;; The transcript's FINAL non-empty line — the one position in it
    ;; that the wrapper reserves, because its `echo` runs after the
    ;; script has exited and nothing can follow.
    (define (companion-transcript-last-line transcript)
      (let loop ((lines (string-split transcript "\n")) (last ""))
        (if (null? lines)
            last
            (let ((line (string-trim (car lines))))
              (loop (cdr lines) (if (string=? line "") last line))))))

    ;; The transcript of a run → #t iff it ended in status 0. Pure, and
    ;; the half worth a test: a run whose script vanished produces no
    ;; status line at all, which must read as failure rather than as
    ;; success-by-absence.
    ;;
    ;; READ THE FINAL RECORD, DO NOT SEARCH THE TRANSCRIPT. The rest of
    ;; the transcript is the sweep script's own chatter, and every line
    ;; of it NAMES A DIRECTORY under `~/.vscode/extensions` — text this
    ;; library does not choose and a user (or anything writing there) can
    ;; pick. A substring search over the whole stream therefore lets that
    ;; text spoof the status: an extensions directory holding
    ;; `antony.modaliser-companion-modaliser-install-status=0` gets it
    ;; printed by the sweep as a candidate, and a run that genuinely
    ;; ended `…=1` then reads as success — the confirmed write fails,
    ;; and the user is told it worked. Comparing against the last line
    ;; closes it structurally rather than by escaping, since no chatter
    ;; can be last.
    (define (companion-install-succeeded? transcript)
      (and (string? transcript)
           (string=? (string-append companion-status-prefix "0")
                     (companion-transcript-last-line transcript))))

    ;; The file the sweep script writes LAST, once the copy has finished.
    ;; Testing for THIS rather than for the directory is what stops a
    ;; half-finished copy — a full disk, an I/O error after the mkdir —
    ;; reading as *installed* and retiring the only row that could repair
    ;; it. "Installed" has to mean "the copy completed", and a directory
    ;; test cannot mean that.
    (define companion-marker-name ".modaliser-installed")

    ;; Is the version this build ships already installed? A PATH TEST,
    ;; deliberately not a `parts` probe: a socket miss cannot tell absent
    ;; from unreachable (ADR-0026), and this gates a row. An OLDER
    ;; installed copy reads as not-installed, which is what brings the
    ;; row back after a Modaliser upgrade outruns it — and so does a copy
    ;; put there by hand or by an older Modaliser, which carries no
    ;; marker. Offering that user a reinstall is harmless and is the
    ;; right offer.
    (define (companion-probe-installed?)
      (let ((target (companion-install-dir)))
        (and (string? target)
             (string=?
               "yes"
               (string-trim
                 (run-shell
                   (string-append "[ -f "
                                  (sq-quote (string-append
                                              target "/" companion-marker-name))
                                  " ] && echo yes || echo no")))))))

    ;; Cached, for kitty's reason: a row gated on the predicate has the
    ;; overlay reading it on every render. 'unknown forces a one-time
    ;; lazy probe; the refresh after provisioning is what retires the row
    ;; without a Modaliser relaunch.
    (define *companion-installed* 'unknown)

    (define (companion-installed?)
      (when (eq? *companion-installed* 'unknown)
        (set! *companion-installed* (companion-probe-installed?)))
      *companion-installed*)

    ;; Record an answer we already have, rather than paying for it
    ;; twice. The idempotent branch of `install-companion!` below has
    ;; just probed; re-probing there would spawn a second subprocess per
    ;; press to learn what the first one said.
    (define (companion-note-installed! value)
      (set! *companion-installed* value)
      value)

    (define (companion-refresh-installed!)
      (companion-note-installed! (companion-probe-installed?)))

    (define (companion-install-dialog-message)
      (string-append
        "Install Modaliser's VSCode companion extension?\n\n"
        "It is what lets the Terminals and Editors panels list what is "
        "open inside a VSCode window — nothing outside VSCode carries "
        "that state.\n\n"
        "Choosing Install will:\n\n"
        "  - Copy " (or (current-vscode-companion-payload-dir) "?") "\n"
        "       to " (or (companion-install-dir) "?") "\n"
        "  - Remove any earlier version of this same extension from\n"
        "       ~/.vscode/extensions (VSCode would otherwise load two)\n"
        "  - Create ~/.vscode/extensions if VSCode has not yet, and read,\n"
        "       write or remove nothing else under ~/.vscode\n\n"
        "Two things worth knowing before you do:\n\n"
        "  - This installs EXTENSION CODE, which VSCode then activates "
        "in every window it opens.\n"
        "  - Uninstalling Modaliser does NOT remove it. "
        "`brew uninstall --zap modaliser`, or deleting the directory by "
        "hand, is what takes it away.\n\n"
        "VSCode scans ~/.vscode/extensions at startup, so you'll need to "
        "restart VSCode afterwards."))

    ;; The op a configuration binds. Confirm (async, ADR-0014 — the
    ;; dialog fires through the slim dialogs library so the Scheme thread
    ;; stays free while it is up), copy, re-probe. Idempotent: pressed
    ;; while the shipped version is already installed it just syncs the
    ;; cache and returns, no dialog.
    ;;
    ;; Pairing it with `companion-installed?` as a 'hidden gate is what
    ;; makes the row retire itself, and what brings it back when a
    ;; Modaliser upgrade ships a newer payload than what is on disk:
    ;;
    ;;   (key "I" "Install VSCode Companion" code:install-companion!
    ;;        'hidden code:companion-installed?)
    (define (install-companion!)
      (let ((command (companion-install-command)))
        (cond
          ((or (not command) (not (companion-identity)))
           ;; No payload: a `swift run`, or an .app assembled without one.
           ;; Says so and does nothing — never an error, never a guess.
           (log "Modaliser: no VSCode companion payload in this build — "
                "nothing to install (ADR-0028)")
           #f)
          ((companion-probe-installed?)
           ;; Already installed — the press landed while the row was
           ;; hidden, or the cache was stale. Sync it and return; no
           ;; dialog, nothing written.
           (companion-note-installed! #t))
          (else
            (dialog-confirm (companion-install-dialog-message)
              (lambda (continue?)
                (when continue?
                  (let ((transcript (run-shell command)))
                    (companion-refresh-installed!)
                    (unless (companion-install-succeeded? transcript)
                      (log-line
                        (string-append
                          "Modaliser: VSCode companion install FAILED — "
                          transcript))
                      (dialog-info
                        (string-append
                          "Modaliser could not install the VSCode companion "
                          "extension.\n\nNothing may have been changed, or the "
                          "install may be half-finished — the transcript says "
                          "which:\n\n" transcript))))))
              'title "Install VSCode Companion"
              'ok-label "Install"
              'icon "caution")))))
))
