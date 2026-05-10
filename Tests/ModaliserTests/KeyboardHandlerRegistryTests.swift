import CoreGraphics
import Foundation
import Testing
@testable import Modaliser

@Suite("KeyboardHandlerRegistry dispatch")
struct KeyboardHandlerRegistryTests {

    /// Build a registry with a stubbed frontmost lookup and a recording
    /// Escape-poster that does NOT actually send a CGEvent. Skipping the
    /// real synthesis is essential — the test runner machine has a real
    /// CGEvent tap, and posting Escape from a unit test would land in
    /// whatever app happens to be focused when tests run.
    private func makeRegistry(frontmost: String?,
                              escapeRecorder: EscapeRecorder = EscapeRecorder())
        -> (KeyboardHandlerRegistry, EscapeRecorder)
    {
        let registry = KeyboardHandlerRegistry()
        registry.frontmostBundleId = { frontmost }
        registry.postEscapeKeystroke = { escapeRecorder.callCount += 1 }
        return (registry, escapeRecorder)
    }

    private func makeEntry(armBundleIds: [String] = [],
                           onFire: @escaping () -> Void = {}) -> HotkeyEntry {
        HotkeyEntry(handler: onFire, armBundleIds: armBundleIds)
    }

    /// Reference-typed counter so closures can mutate without `inout`.
    final class EscapeRecorder {
        var callCount: Int = 0
    }

    // MARK: - Plain hotkey dispatch

    @Test func plainHotkeyFiresAndSuppresses() {
        var fired = false
        let (registry, _) = makeRegistry(frontmost: "com.apple.Safari")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry { fired = true }

        let result = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)

        #expect(fired)
        #expect(result == .suppress)
    }

    @Test func keyUpPassesThroughWithoutFiring() {
        var fired = false
        let (registry, _) = makeRegistry(frontmost: nil)
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry { fired = true }

        let result = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: false)

        #expect(!fired)
        #expect(result == .passThrough)
    }

    // MARK: - Arm transition (idle → armed)

    @Test func armBundleMatchedDoesNotFireHandlerYet() {
        var fired = false
        let (registry, _) = makeRegistry(frontmost: "com.p5sys.jump.mac.viewer")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: ["com.p5sys.jump.mac.viewer"]) { fired = true }

        let result = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)

        #expect(!fired, "Handler must not fire on first trigger over arm-bundle — only on second")
        #expect(result == .passThrough, "First trigger flows to remote viewer")
        #expect(registry.armState == .armed(leaderKey: HotkeyKey(keyCode: 79, modifiers: [])))
    }

    @Test func armBundleEmptyFiresHandlerAndSuppresses() {
        var fired = false
        let (registry, _) = makeRegistry(frontmost: "com.apple.Safari")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: []) { fired = true }

        let result = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)

        #expect(fired)
        #expect(result == .suppress)
        #expect(registry.armState == .idle)
    }

    @Test func armBundleNonMatchFrontmostFiresAndSuppresses() {
        var fired = false
        let (registry, _) = makeRegistry(frontmost: "com.apple.Safari")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: ["com.p5sys.jump.mac.viewer"]) { fired = true }

        let result = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)

        #expect(fired)
        #expect(result == .suppress)
        #expect(registry.armState == .idle)
    }

    // MARK: - Armed → second trigger

    @Test func secondTriggerPostsEscapeFiresHandlerAndSuppresses() {
        var fired = false
        let (registry, recorder) = makeRegistry(frontmost: "com.p5sys.jump.mac.viewer")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: ["com.p5sys.jump.mac.viewer"]) { fired = true }

        // First press: arm.
        _ = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)
        // Second press: cancel remote, enter local modal.
        let result = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)

        #expect(fired, "Handler fires on the second trigger to enter local modal")
        #expect(recorder.callCount == 1, "Escape must be posted exactly once to cancel remote")
        #expect(result == .suppress, "Second trigger never reaches the remote")
        #expect(registry.armState == .idle)
    }

    // MARK: - Armed → other key

    @Test func otherKeyWhileArmedDisarmsAndPassesThrough() {
        var fired = false
        let (registry, recorder) = makeRegistry(frontmost: "com.p5sys.jump.mac.viewer")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: ["com.p5sys.jump.mac.viewer"]) { fired = true }

        _ = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)

        // Some non-trigger keycode (e.g. 's' = 1) arrives.
        let result = registry.dispatch(keyCode: 1, modifiers: [], isKeyDown: true)

        #expect(!fired, "Handler must not fire when a non-trigger interrupts the arm")
        #expect(recorder.callCount == 0, "Escape only on second trigger, not on stray keys")
        #expect(result == .passThrough, "Stray key flows to the focused window")
        #expect(registry.armState == .idle)
    }

    @Test func keyUpWhileArmedPassesThroughAndStaysArmed() {
        let (registry, _) = makeRegistry(frontmost: "com.p5sys.jump.mac.viewer")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: ["com.p5sys.jump.mac.viewer"])

        _ = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)

        // The trigger key-up arrives shortly after — it should not consume
        // the arm; the arm is awaiting another key-down.
        let result = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: false)

        #expect(result == .passThrough)
        #expect(registry.armState == .armed(leaderKey: HotkeyKey(keyCode: 79, modifiers: [])))
    }

    // MARK: - Disarm via timer

    @Test @MainActor func timerExpiresWithinArmWindow() async throws {
        let (registry, _) = makeRegistry(frontmost: "com.p5sys.jump.mac.viewer")
        registry.armWindow = 0.1  // 100ms — short enough for tests, long enough not to race
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: ["com.p5sys.jump.mac.viewer"])

        _ = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)
        #expect(registry.armState != .idle)

        // Yield the main actor so the dispatch source timer (also on main)
        // can fire its event handler.
        try await Task.sleep(nanoseconds: 300_000_000)  // 300ms

        #expect(registry.armState == .idle)
    }

    // MARK: - Re-arm cancels prior timer

    @Test func reArmReplacesPriorState() {
        let (registry, _) = makeRegistry(frontmost: "com.p5sys.jump.mac.viewer")
        registry.hotkeyHandlers[HotkeyKey(keyCode: 79, modifiers: [])] =
            makeEntry(armBundleIds: ["com.p5sys.jump.mac.viewer"])

        _ = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)
        _ = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: false)
        // Same key pressed again with the registry already armed should be
        // treated as the second trigger (cancel + handler) — not as a fresh
        // arm. The Test secondTriggerPostsEscape... covers that. Here we
        // verify a *different* arm path: arm, then disarm manually, then
        // arm again — the new state must replace the old.
        registry.disarm()
        #expect(registry.armState == .idle)

        _ = registry.dispatch(keyCode: 79, modifiers: [], isKeyDown: true)
        #expect(registry.armState == .armed(leaderKey: HotkeyKey(keyCode: 79, modifiers: [])))
    }
}
