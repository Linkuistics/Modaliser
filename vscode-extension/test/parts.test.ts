// What the `parts` reply carries — decision 1's table and decision 2's
// envelope, exercised against fakes of the two API surfaces.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildParts } from "../src/parts";
import { PROTOCOL_VERSION } from "../src/protocol";
import { TokenRegistry } from "../src/registry";
import {
  FakeEnv,
  TabInputCustom,
  TabInputNotebook,
  TabInputNotebookDiff,
  TabInputTerminal,
  TabInputTextDiff,
  TabInputWebview,
  FakeTab,
  textTab,
} from "./fakes";

describe("parts", () => {
  it("names the peer that answered", () => {
    const env = new FakeEnv();
    env.peer = "/Users/someone/.config/modaliser/vscode/vs-abc.sock";
    const reply = buildParts(env, new TokenRegistry());
    // Without this field a row is not an address: window A's token 3 and
    // window B's token 3 are the same integer (ADR-0027).
    assert.equal(reply.peer, "/Users/someone/.config/modaliser/vscode/vs-abc.sock");
    assert.equal(reply.protocol, PROTOCOL_VERSION);
  });

  it("reports the window's focus rather than assuming it", () => {
    const env = new FakeEnv();
    env.isFocused = false;
    assert.equal(buildParts(env, new TokenRegistry()).focused, false);
  });

  it("lists terminals in window.terminals order, with cwd and active flags", () => {
    const env = new FakeEnv();
    const zsh = env.terminal("zsh", "/Users/someone/Project");
    // No shell integration at all: two distinct optionals, one null.
    env.terminal("build");
    env.activeTerminalRef = zsh;

    const reply = buildParts(env, new TokenRegistry());
    assert.deepEqual(
      reply.terminals.map((t) => [t.name, t.cwd, t.active]),
      [
        ["zsh", "/Users/someone/Project", true],
        ["build", null, false],
      ],
    );
  });

  it("mints a token for the three actionable kinds and null for the rest", () => {
    const env = new FakeEnv();
    const group = env.group(1);
    group.add(textTab("fsm.sld", "/p/fsm.sld"));
    group.add(new FakeTab("book.ipynb", new TabInputNotebook({ fsPath: "/p/book.ipynb" }, "jupyter")));
    group.add(new FakeTab("image.png", new TabInputCustom({ fsPath: "/p/image.png" }, "imagePreview")));
    group.add(new FakeTab("Release Notes", new TabInputWebview("releaseNotes")));
    group.add(
      new FakeTab(
        "a.txt ↔ b.txt",
        new TabInputTextDiff({ fsPath: "/p/a.txt" }, { fsPath: "/p/b.txt" }),
      ),
    );
    group.add(
      new FakeTab(
        "x.ipynb ↔ y.ipynb",
        new TabInputNotebookDiff({ fsPath: "/p/x.ipynb" }, { fsPath: "/p/y.ipynb" }, "jupyter"),
      ),
    );
    // An input kind this extension does not know: unknown by construction.
    group.add(new FakeTab("Something New", { someFutureField: 1 }));

    const reply = buildParts(env, new TokenRegistry());

    // Every one of them is LISTED. Omitting an unfocusable tab would make the
    // panel disagree with the tab strip the human is looking at, and would
    // renumber the labels below it.
    assert.deepEqual(
      reply.editors.map((e) => e.label),
      [
        "fsm.sld",
        "book.ipynb",
        "image.png",
        "Release Notes",
        "a.txt ↔ b.txt",
        "x.ipynb ↔ y.ipynb",
        "Something New",
      ],
    );
    assert.deepEqual(
      reply.editors.map((e) => e.token !== null),
      [true, true, true, false, false, false, false],
    );
    // `path` follows the URI: the diff kinds carry two and therefore report
    // none, and a webview has no resource of any kind.
    assert.deepEqual(
      reply.editors.map((e) => e.path),
      ["/p/fsm.sld", "/p/book.ipynb", "/p/image.png", null, null, null, null],
    );
  });

  it("excludes a terminal dragged into the editor grid from the editors", () => {
    const env = new FakeEnv();
    const group = env.group(1);
    group.add(textTab("fsm.sld", "/p/fsm.sld"));
    group.add(new FakeTab("zsh", new TabInputTerminal()));
    env.terminal("zsh");

    const reply = buildParts(env, new TokenRegistry());
    // One thing, one row, one label — it is already in the terminal listing,
    // where the action works.
    assert.deepEqual(reply.editors.map((e) => e.label), ["fsm.sld"]);
    assert.deepEqual(reply.terminals.map((t) => t.name), ["zsh"]);
  });

  it("walks the groups in order and carries each row's own group", () => {
    const env = new FakeEnv();
    const left = env.group(1);
    const right = env.group(2);
    left.add(textTab("one.txt", "/p/one.txt"));
    right.add(textTab("two.txt", "/p/two.txt"));
    right.add(textTab("three.txt", "/p/three.txt"));

    const reply = buildParts(env, new TokenRegistry());
    assert.deepEqual(
      reply.editors.map((e) => [e.label, e.group]),
      [
        ["one.txt", 1],
        ["two.txt", 2],
        ["three.txt", 2],
      ],
    );
  });

  it("answers a folderless window with a null workspace and its real parts", () => {
    const env = new FakeEnv();
    env.workspacePath = null;
    env.terminal("zsh", "/tmp");
    env.group(1).add(textTab("scratch.md", "/tmp/scratch.md"));

    const reply = buildParts(env, new TokenRegistry());
    // No folder is not a reason to be silent; it is a reason for one field to
    // be null.
    assert.equal(reply.workspace, null);
    assert.equal(reply.terminals.length, 1);
    assert.equal(reply.editors.length, 1);
    assert.notEqual(reply.editors[0]!.token, null);
  });

  it("carries an empty window without inventing rows", () => {
    const reply = buildParts(new FakeEnv(), new TokenRegistry());
    assert.deepEqual(reply.terminals, []);
    assert.deepEqual(reply.editors, []);
  });
});
