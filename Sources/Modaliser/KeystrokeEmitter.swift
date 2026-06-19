import CoreGraphics

/// Emits synthetic keyboard events via CGEvent posting.
/// Used by the `(modaliser input)` library to send keystrokes to the focused application.
enum KeystrokeEmitter {

    /// Post a single keyboard event, tagged so Modaliser's own capture tap
    /// passes it through instead of the modal catch-all suppressing it.
    private static func post(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData,
                                   value: KeyboardCapture.reInjectionMagic)
        event.post(tap: .cghidEventTap)
    }

    /// Send a keystroke with optional modifier flags. Modifiers are posted as
    /// real keyDown events (accumulating flags) before the key and released as
    /// keyUp events after it, so the chord ends fully released — a down->up
    /// transition release-driven UIs (e.g. Dia's recent-tab switcher) require.
    static func sendKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let mods = modifierKeyCodes(in: flags)
        var acc: CGEventFlags = []
        for (code, bit) in mods {
            acc.insert(bit)
            post(code, keyDown: true, flags: acc)
        }
        post(keyCode, keyDown: true, flags: flags)
        post(keyCode, keyDown: false, flags: flags)
        for (code, bit) in mods.reversed() {
            acc.remove(bit)
            post(code, keyDown: false, flags: acc)
        }
    }

    /// Post a lone keyDown for `keyCode` with `flags` held. Pairs with
    /// `sendKeyUp` to hold a modifier across multiple taps.
    static func sendKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        post(keyCode, keyDown: true, flags: flags)
    }

    /// Post a lone keyUp for `keyCode`, releasing a hold started by `sendKeyDown`.
    static func sendKeyUp(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        post(keyCode, keyDown: false, flags: flags)
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

    /// Modifier (virtual keycode, flag) pairs present in `flags`, in a stable
    /// order (control, shift, option, command). A chord brackets the target key
    /// with these as real keyDown/keyUp events so release-driven consumers see a
    /// down->up modifier transition.
    static func modifierKeyCodes(in flags: CGEventFlags) -> [(CGKeyCode, CGEventFlags)] {
        let ordered: [(CGEventFlags, CGKeyCode)] = [
            (.maskControl, 59),
            (.maskShift, 56),
            (.maskAlternate, 58),
            (.maskCommand, 55),
        ]
        return ordered.compactMap { flag, code in flags.contains(flag) ? (code, flag) : nil }
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
        "control": 59, "ctrl": 59,
        "shift": 56,
        "command": 55, "cmd": 55,
        "option": 58, "alt": 58,
    ]
}
