// When a window claims the pointer, and — the half that matters — when it
// does not.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { installPointerClaim, type Disposable } from "../src/focusPointer";

function harness(focusedAtActivation: boolean) {
  let handler: ((focused: boolean) => void) | undefined;
  let claims = 0;
  let disposed = false;
  const subscription: Disposable = installPointerClaim({
    focusedNow: () => focusedAtActivation,
    onWindowState: (h) => {
      handler = h;
      return { dispose: () => (disposed = true) };
    },
    claim: () => {
      claims++;
    },
  });
  return {
    fire: (focused: boolean) => handler?.(focused),
    get claims() {
      return claims;
    },
    get disposed() {
      return disposed;
    },
    subscription,
  };
}

describe("claiming the focus pointer", () => {
  it("claims at activation when the window is already focused", () => {
    // The ordinary single-window case, every extension-host restart, and
    // every fresh install. A subscription-only design writes no pointer for
    // any of them, and the symptom is empty panels with no error anywhere.
    assert.equal(harness(true).claims, 1);
  });

  it("does not claim at activation when the window is not focused", () => {
    assert.equal(harness(false).claims, 0);
  });

  it("claims when an unfocused window gains focus", () => {
    const h = harness(false);
    h.fire(true);
    assert.equal(h.claims, 1);
  });

  it("does not re-claim on an event that is not a focus gain", () => {
    const h = harness(true);
    assert.equal(h.claims, 1);
    // `WindowState` also carries `active`, the recent-interaction flag, which
    // changes on its own schedule — so this event fires with `focused`
    // unchanged. An unguarded handler would let an unfocused window claim the
    // pointer and send every read to the wrong peer.
    h.fire(true);
    h.fire(true);
    assert.equal(h.claims, 1);
  });

  it("never claims while unfocused, however often the event fires", () => {
    const h = harness(false);
    h.fire(false);
    h.fire(false);
    assert.equal(h.claims, 0);
  });

  it("claims again after losing and regaining focus", () => {
    const h = harness(true);
    h.fire(false);
    h.fire(true);
    assert.equal(h.claims, 2);
  });

  it("hands back the subscription so the host can dispose it", () => {
    const h = harness(false);
    h.subscription.dispose();
    assert.equal(h.disposed, true);
  });
});
