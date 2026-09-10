// When this window claims the pointer
// (docs/specs/vscode-window-parts.md, decision 3).
//
// This is four lines of policy that a review already caught once, so it lives
// in a module with a test rather than inline in `extension.ts` where nothing
// could reach it. Both halves are defects if omitted, and both are silent:
//
//   CLAIM AT ACTIVATION when the window is already focused.
//   `onDidChangeWindowState` fires on a CHANGE, so a window that is focused
//   when `onStartupFinished` runs has nothing to change and a
//   subscription-only design never writes a pointer for it. That is not an
//   edge case — it is the ordinary single-window case, every window after an
//   extension-host restart, and the first run after installing. Its symptom
//   is two empty panels until the human clicks away and back, with no error
//   anywhere.
//
//   CLAIM ON A FOCUS *GAIN*, not on every event. `WindowState` carries
//   `active` as well as `focused` — the recent-interaction flag, which
//   changes on its own schedule — so the same event fires for windows that
//   have not gained focus, and an unguarded handler would let an unfocused
//   window claim the pointer and send every read to the wrong peer.

export interface Disposable {
  dispose(): void;
}

export interface PointerClaimDeps {
  /** `window.state.focused`, read once at activation. */
  focusedNow(): boolean;
  /** `window.onDidChangeWindowState`, narrowed to the flag that matters. */
  onWindowState(handler: (focused: boolean) => void): Disposable;
  /** Write this instance's socket path into the pointer file. */
  claim(): void;
}

export function installPointerClaim(deps: PointerClaimDeps): Disposable {
  let wasFocused = deps.focusedNow();
  if (wasFocused) {
    deps.claim();
  }
  return deps.onWindowState((focused: boolean) => {
    if (focused && !wasFocused) {
      deps.claim();
    }
    wasFocused = focused;
  });
}
