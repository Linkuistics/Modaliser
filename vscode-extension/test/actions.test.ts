// The four checks a notification makes before it acts.
//
// Three of these pin properties no Swift test can see, because they are
// refusals and a refusal is silent on the wire: from Modaliser's side a
// refused press and a delivered one are the same nothing.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { focusEditor, focusTerminal } from "../src/actions";
import { buildParts } from "../src/parts";
import { TokenRegistry } from "../src/registry";
import {
  FakeEnv,
  FakeTab,
  TabInputCustom,
  TabInputNotebook,
  TabInputTerminal,
  textTab,
} from "./fakes";

describe("focus-terminal", () => {
  it("shows the terminal its token names, without stealing focus twice", () => {
    const env = new FakeEnv();
    const zsh = env.terminal("zsh");
    const build = env.terminal("build");
    const registry = new TokenRegistry();
    const reply = buildParts(env, registry);

    focusTerminal(env, registry, reply.terminals[1]!.token);
    assert.equal(build.shown, 1);
    assert.equal(build.lastPreserveFocus, false);
    assert.equal(zsh.shown, 0);
  });

  it("refuses while the window is not focused", () => {
    const env = new FakeEnv();
    const zsh = env.terminal("zsh");
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).terminals[0]!.token;

    // The human moved to another window between the read and the press.
    env.isFocused = false;
    focusTerminal(env, registry, token);

    assert.equal(zsh.shown, 0);
    assert.match(env.logs.join("\n"), /not focused/);
  });

  it("refuses an editor's token", () => {
    const env = new FakeEnv();
    env.terminal("zsh");
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));
    const registry = new TokenRegistry();
    const reply = buildParts(env, registry);

    focusTerminal(env, registry, reply.editors[0]!.token);
    assert.equal(env.terminalList[0]!.shown, 0);
  });

  it("refuses a terminal that has been closed since the read", () => {
    const env = new FakeEnv();
    const zsh = env.terminal("zsh");
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).terminals[0]!.token;

    // Closed with no `parts` in between, so the token is STILL MAPPED — this
    // is the membership check, not the lookup, and `show()` on a disposed
    // terminal is unspecified behaviour rather than a contract to rest on.
    env.closeTerminal(zsh);
    focusTerminal(env, registry, token);

    assert.equal(zsh.shown, 0);
    assert.match(env.logs.join("\n"), /no longer open/);
  });

  it("refuses a token nothing ever minted", () => {
    const env = new FakeEnv();
    env.terminal("zsh");
    const registry = new TokenRegistry();
    buildParts(env, registry);
    focusTerminal(env, registry, 9999);
    assert.equal(env.terminalList[0]!.shown, 0);
  });
});

describe("focus-editor", () => {
  it("activates a text tab in its own group, preserving its preview state", async () => {
    const env = new FakeEnv();
    const group = env.group(2);
    const tab = textTab("fsm.sld", "/p/fsm.sld");
    tab.isPreview = true;
    group.add(tab);
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    await focusEditor(env, registry, token);

    assert.equal(env.showTextCalls.length, 1);
    // A hard `preview: false` would PIN the tab, so pressing the label of a
    // row that is already active would change the workbench.
    assert.deepEqual(env.showTextCalls[0], {
      uri: { fsPath: "/p/fsm.sld" },
      viewColumn: 2,
      preview: true,
    });
  });

  it("reads the view column off the LIVE tab, not off the snapshot", async () => {
    const env = new FakeEnv();
    const group = env.group(3);
    group.add(textTab("fsm.sld", "/p/fsm.sld"));
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    // A group to the left was closed after the rows were drawn, so every
    // column renumbered. `ViewColumn` is an ordinal position, not a group's
    // identity: an activation built from the recorded 3 would now reveal the
    // file in whatever group is third — or, if none is, CREATE one.
    group.viewColumn = 1;
    await focusEditor(env, registry, token);

    assert.equal(env.showTextCalls[0]!.viewColumn, 1);
  });

  it("sends the same file in two groups to the group its own row came from", async () => {
    const env = new FakeEnv();
    const left = env.group(1);
    const right = env.group(2);
    left.add(textTab("fsm.sld", "/p/fsm.sld"));
    right.add(textTab("fsm.sld", "/p/fsm.sld"));
    const registry = new TokenRegistry();
    const reply = buildParts(env, registry);

    // Reordered between the read and the press, which is what makes a
    // recorded column name the wrong group.
    left.viewColumn = 2;
    right.viewColumn = 1;

    await focusEditor(env, registry, reply.editors[0]!.token);
    await focusEditor(env, registry, reply.editors[1]!.token);

    assert.deepEqual(env.showTextCalls.map((c) => c.viewColumn), [2, 1]);
  });

  it("opens a notebook through the notebook pair", async () => {
    const env = new FakeEnv();
    env.group(1).add(
      new FakeTab("book.ipynb", new TabInputNotebook({ fsPath: "/p/book.ipynb" }, "jupyter")),
    );
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    await focusEditor(env, registry, token);

    assert.deepEqual(env.openNotebookCalls, [{ fsPath: "/p/book.ipynb" }]);
    assert.equal(env.showNotebookCalls.length, 1);
    assert.equal(env.showNotebookCalls[0]!.viewColumn, 1);
    assert.equal(env.showTextCalls.length, 0);
  });

  it("activates a custom editor through vscode.openWith, live column and all", async () => {
    const env = new FakeEnv();
    const group = env.group(2);
    const tab = group.add(
      new FakeTab(
        "notes.md",
        new TabInputCustom({ fsPath: "/p/notes.md" }, "vscode.markdown.preview.editor"),
      ),
    );
    tab.isPreview = true;
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    // The human's own settings map `*.md` to a custom editor, so this is not
    // an exotic case — it is every grove task file the editor panel exists to
    // reach. The column is read live for the same reason a text tab's is.
    group.viewColumn = 1;
    await focusEditor(env, registry, token);

    assert.deepEqual(env.openWithCalls, [
      {
        uri: { fsPath: "/p/notes.md" },
        viewType: "vscode.markdown.preview.editor",
        viewColumn: 1,
        preview: true,
      },
    ]);
    assert.equal(env.showTextCalls.length, 0);
  });

  it("refuses an editor token whose tab has become a terminal", async () => {
    const env = new FakeEnv();
    const registry = new TokenRegistry();
    const tab = env.group(1).add(new FakeTab("Terminal", new TabInputTerminal()));
    // `parts` mints no token for it, so the only way to reach the refusal is
    // to hold a token whose tab has since changed kind — which the branch
    // exists for. Mint one directly.
    const token = registry.tokenFor(tab, "editor");

    await focusEditor(env, registry, token);

    assert.equal(env.showTextCalls.length, 0);
    assert.equal(env.openWithCalls.length, 0);
    assert.match(env.logs.join("\n"), /now a terminal/);
  });

  it("refuses while the window is not focused", async () => {
    const env = new FakeEnv();
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    env.isFocused = false;
    await focusEditor(env, registry, token);

    assert.equal(env.showTextCalls.length, 0);
    assert.match(env.logs.join("\n"), /not focused/);
  });

  it("refuses a terminal's token", async () => {
    const env = new FakeEnv();
    env.terminal("zsh");
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));
    const registry = new TokenRegistry();
    const reply = buildParts(env, registry);

    // The token RESOLVES — one counter, one map — and the kind tag refuses
    // it. Implemented as a bare lookup this would hand a `Terminal` to
    // `showTextDocument`.
    await focusEditor(env, registry, reply.terminals[0]!.token);

    assert.equal(env.showTextCalls.length, 0);
    assert.equal(env.openNotebookCalls.length, 0);
  });

  it("refuses a tab that has been closed since the read", async () => {
    const env = new FakeEnv();
    const group = env.group(1);
    const tab = group.add(textTab("fsm.sld", "/p/fsm.sld"));
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    // No `parts` in between, so the token is still mapped.
    group.remove(tab);
    await focusEditor(env, registry, token);

    assert.equal(env.showTextCalls.length, 0);
    assert.match(env.logs.join("\n"), /no longer open/);
  });
});
