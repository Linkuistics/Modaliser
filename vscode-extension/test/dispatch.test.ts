// What goes on the wire, and — for two of the three methods — what does not.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { dispatch } from "../src/dispatch";
import { buildParts } from "../src/parts";
import { PROTOCOL_VERSION } from "../src/protocol";
import { TokenRegistry } from "../src/registry";
import { FakeEnv, textTab } from "./fakes";

function line(method: string, params?: unknown, id: unknown = 7): string {
  return JSON.stringify({ id, method, params: params ?? {} });
}

describe("dispatch", () => {
  it("answers parts with the whole window in one envelope", async () => {
    const env = new FakeEnv();
    env.terminal("zsh", "/p");
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));

    const reply = await dispatch(env, new TokenRegistry(), line("parts"));
    assert.notEqual(reply, null);
    const parsed = JSON.parse(reply!) as { id: unknown; result: Record<string, unknown> };
    assert.equal(parsed.id, 7);
    assert.equal(parsed.result.protocol, PROTOCOL_VERSION);
    assert.equal(parsed.result.peer, env.peer);
    assert.equal((parsed.result.terminals as unknown[]).length, 1);
  });

  it("answers focus-terminal with nothing at all", async () => {
    const env = new FakeEnv();
    const zsh = env.terminal("zsh");
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).terminals[0]!.token;

    // Not `{"ok": true}`, not an error envelope — nothing. No caller consumes
    // an acknowledgement, so producing one spends the eval thread's time on a
    // value that is discarded (ADR-0014).
    assert.equal(await dispatch(env, registry, line("focus-terminal", { token })), null);
    assert.equal(zsh.shown, 1);
  });

  it("answers focus-editor with nothing at all", async () => {
    const env = new FakeEnv();
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    assert.equal(await dispatch(env, registry, line("focus-editor", { token })), null);
    assert.equal(env.showTextCalls.length, 1);
  });

  it("stays silent on a refused notification too", async () => {
    const env = new FakeEnv();
    env.isFocused = false;
    const registry = new TokenRegistry();
    assert.equal(await dispatch(env, registry, line("focus-terminal", { token: 1 })), null);
    assert.equal(await dispatch(env, registry, line("focus-editor", { token: 1 })), null);
  });

  it("tolerates a notification with no params at all", async () => {
    const env = new FakeEnv();
    const registry = new TokenRegistry();
    assert.equal(await dispatch(env, registry, JSON.stringify({ id: 1, method: "focus-editor" })), null);
    assert.equal(env.showTextCalls.length, 0);
  });

  it("answers an unknown method with an error rather than a timeout", async () => {
    const env = new FakeEnv();
    const reply = await dispatch(env, new TokenRegistry(), line("execute-command", { id: "x" }));
    const parsed = JSON.parse(reply!) as { error: { message: string } };
    assert.match(parsed.error.message, /unknown method/);
  });

  it("ignores an unparseable line instead of throwing out of the callback", async () => {
    const env = new FakeEnv();
    assert.equal(await dispatch(env, new TokenRegistry(), "{not json"), null);
    assert.match(env.logs.join("\n"), /unparseable/);
  });
});
