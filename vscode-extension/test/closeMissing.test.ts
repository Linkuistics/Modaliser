import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { dispatch } from "../src/dispatch";
import { buildParts } from "../src/parts";
import type { TabLike } from "../src/peerEnv";
import { TokenRegistry } from "../src/registry";
import { FakeEnv, FakeTab, TabInputCustom, TabInputNotebook, TabInputText, TabInputTextDiff } from "./fakes";

class FsError extends Error {
  constructor(readonly code: string) { super(code); }
}

class CleanupEnv extends FakeEnv {
  readonly stats: unknown[] = [];
  readonly closes: { tab: TabLike; preserveFocus: boolean }[] = [];
  statResult: () => Promise<unknown> = async () => { throw new FsError("FileNotFound"); };
  override async statResource(uri: unknown): Promise<unknown> {
    this.stats.push(uri);
    return this.statResult();
  }
  override isFileNotFound(error: unknown): boolean {
    return error instanceof FsError && error.code === "FileNotFound";
  }
  override async closeTab(tab: TabLike, preserveFocus: boolean): Promise<boolean> {
    this.closes.push({ tab, preserveFocus });
    return true;
  }
}

const resource = { scheme: "file", fsPath: "/p/.grove/02-impl--task-k2.md" };
function setup(input: unknown = new TabInputText(resource)) {
  const env = new CleanupEnv();
  const tab = env.group(1).add(new FakeTab("task (Deleted)", input));
  const registry = new TokenRegistry();
  const token = buildParts(env, registry).editors[0]!.token;
  const send = (value: unknown = token) => dispatch(env, registry,
    JSON.stringify({ method: "close-editor-if-missing", params: { token: value } }));
  return { env, tab, registry, send };
}

describe("close-editor-if-missing through dispatch", () => {
  for (const input of [new TabInputText(resource), new TabInputCustom(resource, "vscode.markdown.preview.editor")]) {
    it(`closes clean missing ${input.constructor.name} tabs in every group, preserving focus`, async () => {
      const { env, tab, registry, send } = setup(input);
      const second = env.group(2).add(new FakeTab("same task", input));
      const rows = buildParts(env, registry).editors;
      assert.equal(await send(), null);
      assert.equal(await send(rows[1]!.token), null);
      assert.deepEqual(env.stats, [resource, resource]);
      assert.deepEqual(env.closes, [{ tab, preserveFocus: true }, { tab: second, preserveFocus: true }]);
    });
  }

  for (const code of ["exists", "NoPermissions", "Unavailable", "FileNotADirectory", "plain error"]) {
    it(`leaves a resource open for ${code}`, async () => {
      const { env, send } = setup();
      env.statResult = async () => {
        if (code === "exists") return {};
        if (code === "plain error") throw new Error("FileNotFound");
        throw new FsError(code);
      };
      assert.equal(await send(), null);
      assert.equal(env.closes.length, 0);
      assert.ok(env.logs.length > 0);
    });
  }

  for (const input of [new TabInputText({ ...resource, scheme: "untitled" }),
    new TabInputText({ ...resource, scheme: "git" }),
    new TabInputText({ ...resource, scheme: "vscode-remote" }),
    new TabInputTextDiff(resource, resource), new TabInputNotebook(resource, "jupyter")]) {
    it(`refuses unsupported input ${JSON.stringify(input)}`, async () => {
      const { env, send } = setup(input);
      assert.equal(await send(), null);
      assert.equal(env.stats.length, 0);
      assert.equal(env.closes.length, 0);
    });
  }

  it("refuses dirty, stale, wrong-kind and malformed tokens before stat", async () => {
    const { env, tab, registry, send } = setup();
    tab.isDirty = true;
    await send();
    tab.isDirty = false;
    env.terminal("zsh");
    const terminal = buildParts(env, registry).terminals[0]!.token;
    for (const token of [terminal, 999, null, "1", {}]) assert.equal(await send(token), null);
    tab.group.remove(tab);
    await send();
    assert.equal(env.stats.length, 0);
    assert.equal(env.closes.length, 0);
  });

  for (const change of ["dirty", "closed", "replaced", "input", "focus"]) {
    it(`rechecks ${change} after the asynchronous metadata lookup`, async () => {
      const { env, tab, send } = setup();
      let rejectStat!: (reason: unknown) => void;
      env.statResult = () => new Promise((_, reject) => { rejectStat = reject; });
      const pending = send();
      assert.equal(env.stats.length, 1);
      assert.equal(env.closes.length, 0);
      if (change === "dirty") tab.isDirty = true;
      if (change === "focus") env.isFocused = false;
      if (change === "input") tab.input = new TabInputText({ ...resource, fsPath: "/p/new.md" });
      if (change === "closed" || change === "replaced") {
        tab.group.remove(tab);
        if (change === "replaced") tab.group.add(new FakeTab(tab.label, tab.input));
      }
      rejectStat(new FsError("FileNotFound"));
      assert.equal(await pending, null);
      assert.equal(env.closes.length, 0);
      assert.ok(env.logs.length > 0);
    });
  }

  it("refuses an unfocused window before lookup", async () => {
    const { env, send } = setup();
    env.isFocused = false;
    assert.equal(await send(), null);
    assert.equal(env.stats.length, 0);
  });

  it("logs close refusal or failure and keeps the wire silent", async () => {
    for (const failure of [false, true]) {
      const { env, send } = setup();
      env.closeTab = async () => {
        if (failure) throw new Error("host failure");
        return false;
      };
      assert.equal(await send(), null);
      assert.ok(env.logs.length > 0);
    }
  });
});
