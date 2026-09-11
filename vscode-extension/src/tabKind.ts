// Which kind of thing a tab holds, and what may be done about it
// (docs/specs/vscode-window-parts.md, decision 1's table).
//
// `TabGroups` offers `close` and nothing else: there is **no reveal-this-Tab
// call**. So activating a tab means naming a per-kind API operation, and "the
// input carries a URI" is not the test. Three kinds have resource-based
// activation; the rest use the existing tab's live group and position.
//
// The classifier takes the `vscode` namespace as an ARGUMENT rather than
// importing it. The kinds are runtime classes and `instanceof` is the only way
// to tell them apart, so importing the module here would make the table — the
// part of this design most likely to be wrong, and the part a review already
// caught once — the one part no test could reach. Handed the namespace, the
// production call passes the real classes and a test passes fakes with the
// same names, and the table itself is exercised either way.

/** The kinds this extension knows. Unknown inputs, including the built-in
 * browser, can still be selected through their live tab position. */
export type TabKind =
  | "text"
  | "notebook"
  | "custom"
  | "webview"
  | "text-diff"
  | "notebook-diff"
  | "terminal"
  | "unknown";

/** The slice of the `vscode` namespace the classifier reads. Every member is
 *  optional: a VSCode that has not got one of these constructors classifies
 *  its tabs as `unknown` rather than throwing. */
export interface TabInputConstructors {
  readonly TabInputText?: unknown;
  readonly TabInputTextDiff?: unknown;
  readonly TabInputCustom?: unknown;
  readonly TabInputWebview?: unknown;
  readonly TabInputNotebook?: unknown;
  readonly TabInputNotebookDiff?: unknown;
  readonly TabInputTerminal?: unknown;
}

/** Constructor name → kind. The classes are unrelated, so the order this is
 *  walked in cannot change an answer. */
const KIND_OF_CONSTRUCTOR: ReadonlyArray<
  readonly [keyof TabInputConstructors, TabKind]
> = [
  ["TabInputText", "text"],
  ["TabInputNotebook", "notebook"],
  ["TabInputCustom", "custom"],
  ["TabInputWebview", "webview"],
  ["TabInputTextDiff", "text-diff"],
  ["TabInputNotebookDiff", "notebook-diff"],
  ["TabInputTerminal", "terminal"],
];

export function classifyTabInput(
  ctors: TabInputConstructors,
  input: unknown,
): TabKind {
  for (const [name, kind] of KIND_OF_CONSTRUCTOR) {
    const ctor = ctors[name];
    if (typeof ctor === "function" && input instanceof (ctor as Function)) {
      return kind;
    }
  }
  return "unknown";
}

/** A terminal dragged into the editor grid appears both in `window.terminals`
 *  and as a tab. Listed naively it would take two rows and two jump labels for
 *  one thing, so it is excluded from the editor listing — it is already in the
 *  terminal listing, where the action works. */
export function isTerminalTab(kind: TabKind): boolean {
  return kind === "terminal";
}

/** The tab's single resource path, or null. The diff kinds carry `original`
 *  and `modified` and no single `uri` at all; a webview carries no resource of
 *  any kind. */
export function tabPath(kind: TabKind, input: unknown): string | null {
  switch (kind) {
    case "text":
    case "notebook":
    case "custom": {
      const uri = (input as { uri?: { fsPath?: unknown } } | null)?.uri;
      return typeof uri?.fsPath === "string" ? uri.fsPath : null;
    }
    default:
      return null;
  }
}

/** The `uri` an activation is built from. */
export function tabUri(input: unknown): unknown {
  return (input as { uri?: unknown } | null)?.uri;
}

/** A custom editor's `viewType`, which is half of what names its tab. */
export function tabViewType(input: unknown): string | undefined {
  const viewType = (input as { viewType?: unknown } | null)?.viewType;
  return typeof viewType === "string" ? viewType : undefined;
}
