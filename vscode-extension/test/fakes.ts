// Fakes of the two API surfaces this extension reads.
//
// They are hand-written rather than derived from `vscode.d.ts` on purpose:
// what is being pinned is this extension's behaviour against a surface that
// BEHAVES the way the shipped declarations say — a live `Tab.group`, a
// `Terminal` that can be closed, an input object of a real class — and a
// mechanically-derived stub would reproduce the shape without the behaviour.
//
// The tab-input classes below carry the names the real namespace uses, which
// is the whole trick: `classifyTabInput` takes the namespace as an argument,
// so handing it `FakeVscode` exercises the real classification table against
// fake classes.

import type { TabGroupLike, TabLike, TerminalLike } from "../src/peerEnv";
import type { PeerEnv } from "../src/peerEnv";
import { classifyTabInput } from "../src/tabKind";

export class TabInputText {
  constructor(readonly uri: { fsPath: string; scheme?: string }) {}
}
export class TabInputTextDiff {
  constructor(
    readonly original: { fsPath: string },
    readonly modified: { fsPath: string },
  ) {}
}
export class TabInputCustom {
  constructor(
    readonly uri: { fsPath: string },
    readonly viewType: string,
  ) {}
}
export class TabInputWebview {
  constructor(readonly viewType: string) {}
}
export class TabInputNotebook {
  constructor(
    readonly uri: { fsPath: string },
    readonly notebookType: string,
  ) {}
}
export class TabInputNotebookDiff {
  constructor(
    readonly original: { fsPath: string },
    readonly modified: { fsPath: string },
    readonly notebookType: string,
  ) {}
}
export class TabInputTerminal {}

/** The slice of the namespace `classifyTabInput` reads. */
export const FakeVscode = {
  TabInputText,
  TabInputTextDiff,
  TabInputCustom,
  TabInputWebview,
  TabInputNotebook,
  TabInputNotebookDiff,
  TabInputTerminal,
};

export class FakeTerminal implements TerminalLike {
  shown = 0;
  lastPreserveFocus: boolean | undefined;
  constructor(
    readonly name: string,
    readonly shellIntegration?: { cwd?: { fsPath: string } },
  ) {}
  show(preserveFocus?: boolean): void {
    this.shown++;
    this.lastPreserveFocus = preserveFocus;
  }
}

/** A group whose `viewColumn` is MUTABLE, because that is the property the
 *  live-read rule exists for: a test moves a group after the rows are drawn
 *  and asserts the activation followed it. */
export class FakeTabGroup implements TabGroupLike {
  readonly tabs: FakeTab[] = [];
  constructor(public viewColumn: number) {}
  add(tab: FakeTab): FakeTab {
    tab.group = this;
    this.tabs.push(tab);
    return tab;
  }
  remove(tab: FakeTab): void {
    const at = this.tabs.indexOf(tab);
    if (at >= 0) {
      this.tabs.splice(at, 1);
    }
  }
}

export class FakeTab implements TabLike {
  group!: FakeTabGroup;
  isPinned = true;
  constructor(
    readonly label: string,
    public input: unknown,
    public isActive = false,
    public isDirty = false,
    public isPreview = false,
  ) {}
}

export interface ShowTextCall {
  uri: unknown;
  viewColumn: number;
  preview: boolean;
}

/** A `PeerEnv` over mutable fakes, recording every activation. */
export class FakeEnv implements PeerEnv {
  peer = "/tmp/modaliser-test/vs-aaa.sock";
  isFocused = true;
  terminalList: FakeTerminal[] = [];
  groups: FakeTabGroup[] = [];
  activeTerminalRef: FakeTerminal | undefined;
  workspacePath: string | null = "/Users/someone/Project";

  readonly showTextCalls: ShowTextCall[] = [];
  readonly openNotebookCalls: unknown[] = [];
  readonly openWithCalls: {
    uri: unknown;
    viewType: string;
    viewColumn: number;
    preview: boolean;
  }[] = [];
  readonly showNotebookCalls: { document: unknown; viewColumn: number }[] = [];
  readonly logs: string[] = [];

  focused(): boolean {
    return this.isFocused;
  }
  terminals(): readonly TerminalLike[] {
    return this.terminalList;
  }
  tabGroups(): readonly TabGroupLike[] {
    return this.groups;
  }
  activeTerminal(): TerminalLike | undefined {
    return this.activeTerminalRef;
  }
  workspace(): string | null {
    return this.workspacePath;
  }
  classify(input: unknown) {
    return classifyTabInput(FakeVscode, input);
  }
  async showTextDocument(
    uri: unknown,
    options: { viewColumn: number; preview: boolean },
  ): Promise<unknown> {
    this.showTextCalls.push({ uri, ...options });
    return {};
  }
  async openNotebookDocument(uri: unknown): Promise<unknown> {
    this.openNotebookCalls.push(uri);
    return { notebook: uri };
  }
  async openWith(
    uri: unknown,
    viewType: string,
    options: { viewColumn: number; preview: boolean },
  ): Promise<unknown> {
    this.openWithCalls.push({ uri, viewType, ...options });
    return {};
  }
  async showNotebookDocument(
    document: unknown,
    options: { viewColumn: number },
  ): Promise<unknown> {
    this.showNotebookCalls.push({ document, ...options });
    return {};
  }
  log(message: string): void {
    this.logs.push(message);
  }

  async statResource(_uri: unknown): Promise<unknown> { return {}; }
  isFileNotFound(_error: unknown): boolean { return false; }
  async closeTab(_tab: TabLike, _preserveFocus: boolean): Promise<boolean> { return false; }

  group(viewColumn: number): FakeTabGroup {
    const group = new FakeTabGroup(viewColumn);
    this.groups.push(group);
    return group;
  }
  terminal(name: string, cwd?: string): FakeTerminal {
    const terminal = new FakeTerminal(
      name,
      cwd === undefined ? undefined : { cwd: { fsPath: cwd } },
    );
    this.terminalList.push(terminal);
    return terminal;
  }
  closeTerminal(terminal: FakeTerminal): void {
    const at = this.terminalList.indexOf(terminal);
    if (at >= 0) {
      this.terminalList.splice(at, 1);
    }
  }
}

export function textTab(label: string, path: string): FakeTab {
  return new FakeTab(label, new TabInputText({ fsPath: path }));
}
