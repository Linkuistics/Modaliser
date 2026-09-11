import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { focusEditor } from "../src/actions";
import { buildParts } from "../src/parts";
import { TokenRegistry } from "../src/registry";
import { FakeEnv, FakeTab, TabInputWebview, textTab } from "./fakes";

describe("existing browser tab selection", () => {
  for (const input of [new TabInputWebview("simpleBrowser.view"), {}]) {
    it(`selects an existing ${input instanceof TabInputWebview ? "webview" : "unclassified browser"} tab`, async () => {
      const env = new FakeEnv();
      const group = env.group(1);
      env.activeGroup = group;
      group.add(new FakeTab("Browser", {}));
      const target = group.add(new FakeTab("Browser", input, false, false, true));
      const registry = new TokenRegistry();
      const token = buildParts(env, registry).editors[1]!.token;

      assert.equal(typeof token, "number");
      await focusEditor(env, registry, token);

      assert.equal(env.selectedTab, target);
      assert.equal(target.isPreview, true);
      assert.equal(group.tabs.length, 2);
      assert.equal(env.openWithCalls.length + env.showTextCalls.length, 0);
    });
  }

  it("follows the live tab after reordering, across more than nine groups", async () => {
    const env = new FakeEnv();
    const first = env.group(1);
    env.activeGroup = first;
    for (let i = 2; i <= 11; i++) env.group(i);
    const targetGroup = env.groups[10]!;
    const target = targetGroup.add(new FakeTab("Browser", {}));
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;
    targetGroup.add(textTab("notes.txt", "/p/notes.txt"));
    targetGroup.tabs.reverse();

    await focusEditor(env, registry, token);

    assert.equal(env.selectedTab, target);
    assert.equal(env.activeGroup, targetGroup);
    assert.equal(env.groups.length, 11);
  });

  for (const change of ["close", "blur", "move"] as const) {
    it(`rechecks the target when it can ${change} during group focus`, async () => {
      const env = new FakeEnv();
      env.activeGroup = env.group(1);
      const group = env.group(2);
      const target = group.add(new FakeTab("Browser", {}));
      const destination = env.group(3);
      const registry = new TokenRegistry();
      const token = buildParts(env, registry).editors[0]!.token;
      env.afterFocus = () => {
        env.afterFocus = () => {};
        if (change === "blur") env.isFocused = false;
        else {
          group.remove(target);
          if (change === "move") destination.add(target);
        }
      };

      await focusEditor(env, registry, token);

      assert.equal(env.selectedTab, change === "move" ? target : undefined);
      assert.ok(env.focusSteps >= 1);
    });
  }

  it("stops when a group-focus command makes no progress", async () => {
    const env = new FakeEnv();
    const first = env.group(1);
    env.activeGroup = first;
    env.group(2).add(new FakeTab("Browser", {}));
    env.afterFocus = () => { env.activeGroup = first; };
    const registry = new TokenRegistry();
    const token = buildParts(env, registry).editors[0]!.token;

    await focusEditor(env, registry, token);

    assert.equal(env.selectedTab, undefined);
    assert.equal(env.focusSteps, 1);
    assert.match(env.logs.join("\n"), /group/);
  });
});
