// The token bookkeeping decision 4's contract rests on.
//
// Every claim in that decision that is a PROPERTY rather than a description is
// asserted here, because every one of them is invisible from Modaliser's side:
// Modaliser sees integers and cannot tell a shared counter from two, or a
// pruned map from a replaced one, until a label silently does nothing.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildParts } from "../src/parts";
import { TokenRegistry } from "../src/registry";
import { FakeEnv, textTab } from "./fakes";

describe("the token registry", () => {
  it("allocates terminals and editors from one counter", () => {
    const env = new FakeEnv();
    env.terminal("zsh");
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));
    env.terminal("build");

    const reply = buildParts(env, new TokenRegistry());
    const tokens = [
      ...reply.terminals.map((t) => t.token),
      ...reply.editors.map((e) => e.token),
    ];
    // Two spaces would both hand out the same integers, and a kind confusion
    // would then land on a real object of the other kind instead of being
    // refused.
    assert.equal(new Set(tokens).size, tokens.length);
  });

  it("never reuses a token, even after the object it named is gone", () => {
    const env = new FakeEnv();
    const registry = new TokenRegistry();
    const doomed = env.terminal("zsh");
    const first = buildParts(env, registry).terminals[0]!.token;

    env.closeTerminal(doomed);
    buildParts(env, registry); // the prune happens here

    env.terminal("replacement");
    const second = buildParts(env, registry).terminals[0]!.token;
    assert.notEqual(second, first);
  });

  it("keeps a live object's token across repeated parts calls", () => {
    const env = new FakeEnv();
    const registry = new TokenRegistry();
    env.terminal("zsh");
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));

    const first = buildParts(env, registry);
    const second = buildParts(env, registry);

    // The screen's two panels each call `parts`. A map replaced rather than
    // pruned would invalidate the first panel's labels on the second call,
    // and every one of them would silently do nothing.
    assert.deepEqual(
      second.terminals.map((t) => t.token),
      first.terminals.map((t) => t.token),
    );
    assert.deepEqual(
      second.editors.map((e) => e.token),
      first.editors.map((e) => e.token),
    );
  });

  it("keys on object identity, so a moved tab keeps its token", () => {
    const env = new FakeEnv();
    const registry = new TokenRegistry();
    const left = env.group(1);
    const right = env.group(2);
    const tab = left.add(textTab("fsm.sld", "/p/fsm.sld"));

    const before = buildParts(env, registry).editors[0]!.token;
    left.remove(tab);
    right.add(tab);
    const after = buildParts(env, registry).editors[0]!.token;

    // This is the stated assumption in registry.ts's header made visible: the
    // host memoises each API `Tab` and reuses the wrapper across a structural
    // change. If a future VSCode re-materialises them, THIS is the test that
    // fails, rather than a label quietly going inert in the second panel.
    assert.equal(after, before);
    assert.equal(registry.size, 1);
  });

  it("prunes only what is gone", () => {
    const env = new FakeEnv();
    const registry = new TokenRegistry();
    const doomed = env.terminal("zsh");
    env.group(1).add(textTab("fsm.sld", "/p/fsm.sld"));
    buildParts(env, registry);
    assert.equal(registry.size, 2);

    env.closeTerminal(doomed);
    buildParts(env, registry);
    assert.equal(registry.size, 1);
  });

  it("refuses a lookup of the other kind", () => {
    const registry = new TokenRegistry();
    const terminal = {};
    const token = registry.tokenFor(terminal, "terminal");
    // The token RESOLVES — one map — and the kind tag is what refuses it.
    assert.equal(registry.lookup(token, "terminal"), terminal);
    assert.equal(registry.lookup(token, "editor"), undefined);
  });

  it("refuses a token that is not an integer", () => {
    const registry = new TokenRegistry();
    for (const bad of [undefined, null, "3", 3.5, NaN, {}]) {
      assert.equal(registry.lookup(bad, "terminal"), undefined);
    }
  });
});
