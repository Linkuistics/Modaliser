import CoreGraphics

/// Maps CGKeyCode values to their character representations.
/// Used by the key event dispatcher to convert raw key codes into modal key lookups.
/// Based on the US ANSI keyboard layout (macOS HID key codes).
/// HID key codes are physical positions, not characters — so key code 0 is the "A" position
/// regardless of layout (AZERTY, Dvorak, etc.). This is intentional: modal shortcuts bind to
/// physical key positions, matching the labels shown in the overlay.
enum KeyCodeMapping {

    /// Convert a CGKeyCode to its character string, or nil if not a modal key.
    static func character(for keyCode: CGKeyCode) -> String? {
        keyCodeToCharacter[keyCode]
    }

    private static let keyCodeToCharacter: [CGKeyCode: String] = [
        // Letters (QWERTY layout, HID key codes)
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g",
        6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 40: "k",
        45: "n", 46: "m",

        // Digits
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0",

        // Punctuation
        24: "=", 27: "-", 30: "]", 33: "[",
        39: "'", 41: ";", 42: "\\", 43: ",", 44: "/",
        47: ".", 50: "`",

        // Space
        49: " ",
    ]
}
