import CoreGraphics

/// Emits synthetic keyboard events via CGEvent posting.
/// Used by the `(modaliser input)` library to send keystrokes to the focused application.
enum KeystrokeEmitter {

    /// Post a single keyboard event, tagged with `reInjectionMagic` so
    /// KeyboardCapture's tap recognises it as our own re-injection and passes
    /// it through, instead of letting the modal catch-all suppress it on the
    /// way back (e.g. Ctrl+1 for space switch posted from inside the modal
    /// action that's still tearing down).
    private static func post(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(keyboardEventSource: source,
                                  virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData,
                                   value: KeyboardCapture.reInjectionMagic)
        event.post(tap: .cghidEventTap)
    }

    /// Modifiers currently held via `sendKeyDown` of a modifier key, mirroring
    /// the real OS-level hold those posts create. Every subsequent event ORs
    /// these in, so a tap posted while control is held is seen as control+key
    /// without the caller restating the modifier. Cleared by the matching
    /// `sendKeyUp`. (A leaked hold corrupts later shortcuts — but the leak is
    /// the OS-level control-down, not this mirror; `sendKeyUp '() "ctrl"`
    /// clears both.)
    private static var heldModifiers: CGEventFlags = []

    /// The modifier flag a virtual keycode represents, or [] if it is not a
    /// modifier key. Lets `sendKeyDown "ctrl"` assert and track control with
    /// no separate `'(ctrl)` argument.
    static func modifierFlag(forKeyCode keyCode: CGKeyCode) -> CGEventFlags {
        switch keyCode {
        case 59: return .maskControl
        case 56: return .maskShift
        case 55: return .maskCommand
        case 58: return .maskAlternate
        default: return []
        }
    }

    /// Send a keystroke with optional modifier flags. Modifiers are posted as
    /// real keyDown events (accumulating flags) before the key and released as
    /// keyUp events after it, so the chord ends fully released — a down->up
    /// transition release-driven UIs (e.g. Dia's recent-tab switcher) require.
    /// Any modifiers currently held via `sendKeyDown` are ORed onto every event
    /// but left held (not bracketed), so taps during a hold need not restate
    /// the held modifier.
    static func sendKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let base = heldModifiers
        // Bracket only the explicit modifiers that aren't already held — a held
        // modifier must not be released by this chord's closing up-pass.
        let mods = modifierKeyCodes(in: flags.subtracting(base))
        var acc = base
        for (code, bit) in mods {
            acc.insert(bit)
            post(code, keyDown: true, flags: acc)
        }
        post(keyCode, keyDown: true, flags: flags.union(base))
        post(keyCode, keyDown: false, flags: flags.union(base))
        for (code, bit) in mods.reversed() {
            acc.remove(bit)
            post(code, keyDown: false, flags: acc)
        }
    }

    /// Post a lone keyDown for `keyCode`. If `keyCode` is a modifier, its flag
    /// is asserted and recorded as held (so `(send-key-down '() "ctrl")` holds
    /// control); otherwise the event carries any currently-held modifiers.
    static func sendKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        heldModifiers.formUnion(modifierFlag(forKeyCode: keyCode))
        post(keyCode, keyDown: true, flags: flags.union(heldModifiers))
    }

    /// Post a lone keyUp for `keyCode`, releasing a hold started by `sendKeyDown`.
    /// If `keyCode` is a modifier, its flag is dropped from the held set and the
    /// event reflects the post-release state.
    static func sendKeyUp(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        heldModifiers.subtract(modifierFlag(forKeyCode: keyCode))
        post(keyCode, keyDown: false, flags: flags.union(heldModifiers))
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
