import AppKit
import CoreGraphics

/// Stores registered keyboard handlers and dispatches key events to them.
/// Separates the dispatch logic from the CGEvent tap and the Scheme bridge,
/// making it independently testable.
///
/// Dispatch priority:
/// 1. Catch-all handler (if registered) — receives all keys, returns suppress/pass
/// 2. Specific hotkey handler (if registered for this keycode+modifiers) — captures
///    or passes through depending on the entry's passthrough rule
/// 3. Pass through
final class KeyboardHandlerRegistry {

    /// Handler for all keys (used during modal mode).
    /// Receives (keyCode, modifiers). Returns true to suppress, false to pass through.
    var catchAllHandler: ((_ keyCode: CGKeyCode, _ modifiers: CGEventFlags) -> Bool)?

    /// Handlers for specific (keycode, modifiers) combinations.
    /// Each entry carries the handler closure and an optional passthrough rule.
    var hotkeyHandlers: [HotkeyKey: HotkeyEntry] = [:]

    /// Frontmost-app bundle ID lookup. Injectable for tests.
    var frontmostBundleId: () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Dispatch a key event. Returns whether to suppress or pass through.
    func dispatch(keyCode: CGKeyCode, modifiers: CGEventFlags) -> KeyboardDispatchResult {
        if let catchAll = catchAllHandler {
            let shouldSuppress = catchAll(keyCode, modifiers)
            return shouldSuppress ? .suppress : .passThrough
        }

        if let entry = findEntry(keyCode: keyCode, modifiers: modifiers) {
            if !entry.passthroughBundleIds.isEmpty,
               let bundleId = frontmostBundleId(),
               entry.passthroughBundleIds.contains(bundleId)
            {
                return .passThrough
            }
            entry.handler()
            return .suppress
        }

        return .passThrough
    }

    /// Exact-key lookup. Modifiers are normalized to the four primary bits
    /// (cmd/shift/alt/ctrl) before lookup, so Caps Lock and friends don't
    /// affect matching.
    private func findEntry(keyCode: CGKeyCode, modifiers: CGEventFlags) -> HotkeyEntry? {
        let normalized = modifiers.intersection(KeyboardHandlerRegistry.primaryModifiers)
        return hotkeyHandlers[HotkeyKey(keyCode: keyCode, modifiers: normalized)]
    }

    static let primaryModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]
}

/// Composite key for hotkey lookup: a keycode plus a normalized modifier mask.
/// Modifiers are restricted to [.maskShift, .maskControl, .maskAlternate, .maskCommand]
/// (Caps Lock, function-key, numpad bits are stripped before lookup).
struct HotkeyKey: Hashable {
    let keyCode: CGKeyCode
    /// Stored as raw value because CGEventFlags isn't Hashable directly.
    let modifiers: UInt64

    init(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }
}

/// A registered hotkey: handler plus passthrough rule.
struct HotkeyEntry {
    let handler: () -> Void
    /// Bundle IDs of frontmost apps where this hotkey should pass through to
    /// the OS instead of firing. Empty list means always capture.
    let passthroughBundleIds: [String]
}

/// Result of keyboard dispatch — tells the CGEvent tap what to do.
enum KeyboardDispatchResult {
    case suppress
    case passThrough
}
