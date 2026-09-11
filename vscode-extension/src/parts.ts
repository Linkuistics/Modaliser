// The `parts` reply: the whole window in one answer
// (docs/specs/vscode-window-parts.md, decisions 1 and 2).

import type { PeerEnv, TabLike, TerminalLike } from "./peerEnv";
import type { EditorRow, PartsResult, TerminalRow } from "./protocol";
import { PROTOCOL_VERSION } from "./protocol";
import type { TokenRegistry } from "./registry";
import { isTerminalTab, tabPath } from "./tabKind";

/** Every tab of every group, flattened in `tabGroups.all` order and, within
 *  each group, its own `tabs` order. */
function allTabs(groups: readonly { readonly tabs: readonly TabLike[] }[]): TabLike[] {
  const tabs: TabLike[] = [];
  for (const group of groups) {
    for (const tab of group.tabs) {
      tabs.push(tab);
    }
  }
  return tabs;
}

export function buildParts(env: PeerEnv, registry: TokenRegistry): PartsResult {
  const terminals = env.terminals();
  const tabs = allTabs(env.tabGroups());

  // Prune before minting. The map then holds only objects this window still
  // has — and, crucially, every OTHER live object keeps the token it already
  // had, so a second `parts` in the same come-to-rest cannot invalidate the
  // first panel's labels (decision 4).
  registry.prune([...terminals, ...tabs]);

  const active = env.activeTerminal();

  const terminalRows: TerminalRow[] = terminals.map(
    (terminal: TerminalLike): TerminalRow => ({
      token: registry.tokenFor(terminal, "terminal"),
      name: terminal.name,
      cwd: terminal.shellIntegration?.cwd?.fsPath ?? null,
      active: terminal === active,
    }),
  );

  const editorRows: EditorRow[] = [];
  for (const tab of tabs) {
    const kind = env.classify(tab.input);
    // A terminal in the editor grid is a terminal, not an editor: it is
    // already a row in the listing above, where the action works.
    if (isTerminalTab(kind)) {
      continue;
    }
    editorRows.push({
      // Resource-less tabs, including browsers, can be selected by their live
      // position. The token still names the Tab object, never a saved index.
      token: registry.tokenFor(tab, "editor"),
      label: tab.label,
      path: tabPath(kind, tab.input),
      active: tab.isActive,
      dirty: tab.isDirty,
      group: tab.group.viewColumn,
    });
  }

  return {
    protocol: PROTOCOL_VERSION,
    focused: env.focused(),
    peer: env.peer,
    workspace: env.workspace(),
    terminals: terminalRows,
    editors: editorRows,
  };
}
