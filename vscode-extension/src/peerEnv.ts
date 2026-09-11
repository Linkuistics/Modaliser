// The whole of the VSCode API this extension reads, as one injected
// interface.
//
// Nothing under `src/` outside `extension.ts` imports the `vscode` module at
// runtime, and this interface is why: the peer's behaviour is written against
// these accessors, `extension.ts` binds them to the real namespace, and the
// tests bind them to fakes. That makes "the extension is tested against fakes
// of the two API surfaces it reads" a structural fact rather than a
// discipline — there is no path by which a test could reach a live editor,
// for the same reason and in the same shape as the `#f`-by-default parameters
// keep `swift test` off a live socket (ADR-0023).
//
// The accessors are FUNCTIONS, not fields, and that is load-bearing for the
// live-read rule: `terminals()` and `tabGroups()` are called again at act
// time, so an action can never be built from a snapshot taken when the rows
// were drawn.

import type { TabKind } from "./tabKind";

export interface TerminalLike {
  readonly name: string;
  readonly shellIntegration?:
    | { readonly cwd?: { readonly fsPath?: string } | undefined }
    | undefined;
  show(preserveFocus?: boolean): void;
}

export interface TabGroupLike {
  readonly viewColumn: number;
  readonly tabs: readonly TabLike[];
}

export interface TabLike {
  readonly label: string;
  readonly input: unknown;
  readonly isActive: boolean;
  readonly isDirty: boolean;
  readonly isPreview: boolean;
  /** A LIVE reference, not a recorded column. `group.viewColumn` is read
   *  through this at activation time; see `actions.ts` for why. */
  readonly group: TabGroupLike;
}

export interface PeerEnv {
  /** The socket path this instance is listening on — the `peer` field of
   *  every reply, and the address every action comes back to. */
  readonly peer: string;

  focused(): boolean;
  terminals(): readonly TerminalLike[];
  tabGroups(): readonly TabGroupLike[];
  activeTerminal(): TerminalLike | undefined;
  workspace(): string | null;

  /** `classifyTabInput` closed over the real `vscode` namespace. */
  classify(input: unknown): TabKind;

  statResource(uri: unknown): Promise<unknown>;
  isFileNotFound(error: unknown): boolean;
  closeTab(tab: TabLike, preserveFocus: boolean): Promise<boolean>;

  showTextDocument(
    uri: unknown,
    options: { viewColumn: number; preview: boolean },
  ): Promise<unknown>;
  openNotebookDocument(uri: unknown): Promise<unknown>;
  /** `vscode.openWith`, and NOT a general `executeCommand`. Narrowing the
   *  seam to the one operation is what keeps "no method runs a workbench
   *  command" structural rather than a promise: there is no shape here that
   *  another method could route an arbitrary command id through. */
  openWith(
    uri: unknown,
    viewType: string,
    options: { viewColumn: number; preview: boolean },
  ): Promise<unknown>;
  showNotebookDocument(
    document: unknown,
    options: { viewColumn: number },
  ): Promise<unknown>;

  /** A refusal is silent on the wire, so this log is the only trace a refused
   *  press leaves anywhere (ADR-0027). */
  log(message: string): void;
}
