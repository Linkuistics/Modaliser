// The two notifications, and the four checks each one makes before acting
// (docs/specs/vscode-window-parts.md, decisions 1, 2 and 4; ADR-0027).
//
// Nothing here returns anything to the caller. A refusal is silent on the
// wire by construction, so `env.log` is the only trace a refused press leaves
// anywhere.
//
// THE FOUR CHECKS, and why each is here rather than in Modaliser:
//
//  1. FOCUS. `window.state.focused` false at the moment the notification is
//     handled ⇒ do nothing. This check is the peer's because only the peer
//     can read the window's own focus state at all; Modaliser cannot make
//     check-and-use atomic from outside. It NARROWS the read→act race and
//     does not close it — the host reads a replica of `window.state`, this is
//     a callback on a shared event loop, and the activation itself is
//     asynchronous — but it eliminates the systematic case, a modal held open
//     across a deliberate window switch.
//
//  2. KIND. The token map is one space with a kind tag, so a terminal's token
//     handed to `focus-editor` resolves; the refusal is the tag check inside
//     `lookup`, not a failed lookup. Written as "one lookup" without the
//     kind, this would hand a `Terminal` to `showTextDocument`.
//
//  3. MEMBERSHIP. The map is pruned only when `parts` is called, and a press
//     arrives with no `parts` in between — so between the read and the press
//     a closed part is still mapped, and "not in the map" is not yet the same
//     thing as "gone". The shipped API promises nothing about `show()` on a
//     disposed terminal, so resting the "a closed part activates nothing"
//     requirement on it would be resting on unspecified behaviour.
//
//  4. LIVE READS. Both activations reveal *a resource in a column* rather
//     than a tab, and `ViewColumn` is an ordinal position, not a group's
//     identity: reorder or close a group and a recorded column now names a
//     different group. With the same file open in two groups the pressed
//     row's column can hold the other group — activating the other row's tab
//     — and with the recorded column gone entirely, `showTextDocument`
//     *creates* one. So the column is read off the live `Tab` the token
//     resolved to, which costs a property read because `Tab.group` is a live
//     reference. `preview` is the same discipline on a smaller thing: a hard
//     `false` would PIN a preview tab, so pressing the label of a row that is
//     already active would change the workbench, which the requirements
//     forbid.
//
// WHY A CUSTOM EDITOR IS ACTIONABLE, WHEN THE SPEC'S TABLE SAID IT WAS NOT.
// The spec ruled `TabInputCustom` out because `vscode.openWith` "opens by
// resource and view type rather than revealing the pressed tab", and named
// the condition that would reopen it: a custom editor being something the
// human keeps on screen and wants a label for. That condition was already
// met when this was built and the spec's author could not have known —
// the human's own settings carry `"*.md": "vscode.markdown.preview.editor"`,
// so EVERY markdown file, including every grove task file the editor panel
// exists to reach, is a `TabInputCustom`. Without this branch the panel's
// headline case is a panel of inert rows.
//
// And the objection does not survive contact with the shipped command
// registration, read out of the bundle rather than from documentation
// (1.136.2, `extensionHostProcess.js`): `vscode.openWith(resource, viewId,
// columnOrOptions)` takes the same `TextDocumentShowOptions` object
// `showTextDocument` does. So it is identity-preserving by exactly the
// argument that admitted text tabs — one (resource, viewType) pair cannot be
// open twice in one group, so *(resource, viewType, current group)* names the
// pressed tab — and it preserves `isPreview` the same way. It is also the
// bounded internal call to one named command per kind that the spec itself
// contemplated, not the prohibited generic passthrough: the seam on `PeerEnv`
// is `openWith`, not `executeCommand`.

import type { PeerEnv, TabLike, TerminalLike } from "./peerEnv";
import type { TokenRegistry } from "./registry";
import { tabUri, tabViewType } from "./tabKind";

function refuse(env: PeerEnv, method: string, token: unknown, why: string): void {
  env.log(`${method} token=${String(token)} refused: ${why}`);
}

export function focusTerminal(
  env: PeerEnv,
  registry: TokenRegistry,
  token: unknown,
): void {
  if (!env.focused()) {
    refuse(env, "focus-terminal", token, "this window is not focused");
    return;
  }
  const resolved = registry.lookup(token, "terminal");
  if (resolved === undefined) {
    refuse(env, "focus-terminal", token, "no terminal of this window has that token");
    return;
  }
  const live = env.terminals().find((t: TerminalLike) => t === resolved);
  if (live === undefined) {
    refuse(env, "focus-terminal", token, "that terminal is no longer open");
    return;
  }
  live.show(false);
}

/** The live `Tab` identical to RESOLVED, or undefined if the window no longer
 *  holds it. Identity, not equality: a value-shaped match would accept a
 *  different tab on the same resource. */
function liveTab(
  groups: readonly { readonly tabs: readonly TabLike[] }[],
  resolved: object,
): TabLike | undefined {
  for (const group of groups) {
    for (const tab of group.tabs) {
      if (tab === resolved) {
        return tab;
      }
    }
  }
  return undefined;
}

export async function focusEditor(
  env: PeerEnv,
  registry: TokenRegistry,
  token: unknown,
): Promise<void> {
  if (!env.focused()) {
    refuse(env, "focus-editor", token, "this window is not focused");
    return;
  }
  const resolved = registry.lookup(token, "editor");
  if (resolved === undefined) {
    refuse(env, "focus-editor", token, "no editor tab of this window has that token");
    return;
  }
  const live = liveTab(env.tabGroups(), resolved);
  if (live === undefined) {
    refuse(env, "focus-editor", token, "that tab is no longer open");
    return;
  }

  // Read through the live tab, at act time. See check 4 in the header.
  const viewColumn = live.group.viewColumn;
  const kind = env.classify(live.input);
  const uri = tabUri(live.input);

  if (kind === "text") {
    await env.showTextDocument(uri, { viewColumn, preview: live.isPreview });
    return;
  }
  if (kind === "notebook") {
    const document = await env.openNotebookDocument(uri);
    await env.showNotebookDocument(document, { viewColumn });
    return;
  }
  if (kind === "custom") {
    const viewType = tabViewType(live.input);
    if (viewType === undefined) {
      refuse(env, "focus-editor", token, "a custom tab with no view type");
      return;
    }
    await env.openWith(uri, viewType, { viewColumn, preview: live.isPreview });
    return;
  }
  // Unreachable through a token minted by `parts`, which mints only for the
  // three kinds above — but a tab can change kind under a live token no more
  // safely than it can be closed, and the refusal costs one branch.
  refuse(env, "focus-editor", token, `a ${kind} tab has no specified activation`);
}
