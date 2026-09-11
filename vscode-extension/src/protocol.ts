// The wire contract between this extension and Modaliser
// (docs/specs/vscode-window-parts.md, decision 2).
//
// Newline-delimited JSON over a Unix-domain stream socket, one message per
// connection — the envelope ADR-0020 established for herdr, reused unchanged
// because Modaliser's JSON handling is already shaped for it.
//
// Four methods and no more. `parts` is a query and is answered; the three action
// methods are NOTIFICATIONS and are answered with nothing at all — not an
// `{"ok": …}`, not an error envelope (ADR-0014: no caller consumes an
// acknowledgement, so waiting for one spends the eval thread's time, and the
// keyboard tap's, on a value that is discarded).
//
// There is deliberately no method that runs a workbench command. The set is
// enumerated and accepted in ADR-0026; growing it needs a reason recorded
// there, because a `commands.executeCommand` passthrough is one line and would
// turn this into a remote control for the workbench.

/** Bumped when a field changes meaning. Modaliser refuses a reply whose
 *  `protocol` is not the version it understands, because the two halves are
 *  installed separately and can skew (ADR-0026). */
export const PROTOCOL_VERSION = 1;

export const METHOD_PARTS = "parts";
export const METHOD_FOCUS_TERMINAL = "focus-terminal";
export const METHOD_FOCUS_EDITOR = "focus-editor";
export const METHOD_CLOSE_EDITOR_IF_MISSING = "close-editor-if-missing";

/** The methods that answer nothing. */
export const NOTIFICATION_METHODS: ReadonlySet<string> = new Set([
  METHOD_FOCUS_TERMINAL,
  METHOD_FOCUS_EDITOR,
  METHOD_CLOSE_EDITOR_IF_MISSING,
]);

export interface TerminalRow {
  /** Minted from the window's one never-reset counter. Every terminal is
   *  actionable, so this is never null — unlike an editor row's. */
  readonly token: number;
  /** `Terminal.name`. */
  readonly name: string;
  /** `Terminal.shellIntegration?.cwd?.fsPath` — null when shell integration is
   *  absent *or* has reported no cwd, which are two distinct optionals and one
   *  null. */
  readonly cwd: string | null;
  /** Identity against `window.activeTerminal`, which is the terminal that has
   *  focus **or most recently had focus** — so it is non-undefined even with
   *  the panel hidden, and it is not the same predicate as `Tab.isActive`. */
  readonly active: boolean;
}

export interface EditorRow {
  /** Current peers mint a token for every editor row. Null remains valid on
   *  protocol 1 for older peers that cannot activate resource-less tabs. */
  readonly token: number | null;
  /** `Tab.label`. */
  readonly label: string;
  /** The tab's single `uri.fsPath`, or null for the kinds that carry two URIs
   *  or none. */
  readonly path: string | null;
  readonly active: boolean;
  readonly dirty: boolean;
  /** `Tab.group.viewColumn`. A renderer may show it; nothing addresses a group
   *  by it. */
  readonly group: number;
}

export interface PartsResult {
  readonly protocol: number;
  /** `window.state.focused`. Modaliser discards a reply whose value is false,
   *  so a stale pointer yields an empty listing rather than a neighbouring
   *  project's terminals. */
  readonly focused: boolean;
  /** The socket path this extension instance is listening on. This is what
   *  binds every row of this reply to the window that minted it: an action
   *  goes back to *this* path, never to whatever the pointer file says by then
   *  (ADR-0027). */
  readonly peer: string;
  /** `workspace.workspaceFolders[0].uri.fsPath`, null in a window with no
   *  folder open. A folderless window is an ordinary peer, not a silent one. */
  readonly workspace: string | null;
  /** `window.terminals` order. */
  readonly terminals: readonly TerminalRow[];
  /** `window.tabGroups.all` order, and within each group its own `tabs` order.
   *  Exact within a group; between groups it is the API's own order, which
   *  carries no documented guarantee (decision 2). */
  readonly editors: readonly EditorRow[];
}

/** A request as it arrives: nothing about it is trusted until it is checked. */
export interface WireRequest {
  readonly id?: unknown;
  readonly method?: unknown;
  readonly params?: unknown;
}
