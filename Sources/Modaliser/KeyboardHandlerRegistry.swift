import CoreGraphics
import Foundation

/// Stores registered keyboard handlers and dispatches key events to them.
/// Separates the dispatch logic from the CGEvent tap and the Scheme bridge,
/// making it independently testable.
///
/// Dispatch priority:
/// 1. Catch-all handler (if registered) — receives all keys, returns suppress/pass
/// 2. Specific hotkey handler (if registered for this keycode) — always suppresses
/// 3. Pass through
final class KeyboardHandlerRegistry {

    /// Handler for all keys (used during modal mode).
    /// Receives (keyCode, modifiers). Returns true to suppress, false to pass through.
    var catchAllHandler: ((_ keyCode: CGKeyCode, _ modifiers: CGEventFlags) -> Bool)?

    /// Handlers for specific key codes (used for leader keys).
    /// Each handler is a zero-argument closure that fires on keydown.
    var hotkeyHandlers: [CGKeyCode: () -> Void] = [:]

    /// Dispatch a key event. Returns whether to suppress or pass through.
    func dispatch(keyCode: CGKeyCode, modifiers: CGEventFlags) -> KeyboardDispatchResult {
        if let catchAll = catchAllHandler {
            NSLog("KeyboardDispatch: catch-all handling keycode %d", keyCode)
            let shouldSuppress = catchAll(keyCode, modifiers)
            NSLog("KeyboardDispatch: catch-all returned %@", shouldSuppress ? "suppress" : "passThrough")
            return shouldSuppress ? .suppress : .passThrough
        }

        if let hotkeyHandler = hotkeyHandlers[keyCode] {
            hotkeyHandler()
            return .suppress
        }

        return .passThrough
    }
}

/// Result of keyboard dispatch — tells the CGEvent tap what to do.
enum KeyboardDispatchResult {
    case suppress
    case passThrough
}
