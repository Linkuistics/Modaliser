import CoreGraphics

/// Emits synthetic keyboard events via CGEvent posting.
/// Used by the `(modaliser input)` library to send keystrokes to the focused application.
enum KeystrokeEmitter {

    /// Send a keystroke with optional modifier flags to the system.
    /// - Parameters:
    ///   - keyCode: The HID key code to press
    ///   - flags: Modifier flags (cmd, alt, shift, ctrl)
    static func sendKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Look up the CGKeyCode for a character string (US ANSI layout).
    /// Returns nil for characters without a known key code.
    static func keyCode(for character: String) -> CGKeyCode? {
        characterToKeyCode[character.lowercased()]
    }

    /// Map of named keys to key codes for the DSL.
    static func keyCode(forNamedKey name: String) -> CGKeyCode? {
        namedKeyToKeyCode[name.lowercased()]
    }

    // MARK: - Key code tables

    private static let characterToKeyCode: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25, "0": 29,
        "=": 24, "-": 27, "]": 30, "[": 33,
        "'": 39, ";": 41, "\\": 42, ",": 43, "/": 44,
        ".": 47, "`": 50,
        " ": 49,
    ]

    private static let namedKeyToKeyCode: [String: CGKeyCode] = [
        "return": 36, "enter": 36,
        "tab": 48,
        "space": 49,
        "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
