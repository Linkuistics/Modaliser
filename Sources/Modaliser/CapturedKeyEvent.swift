import CoreGraphics

/// Represents a captured keyboard event with parsed fields.
struct CapturedKeyEvent {
    let keyCode: CGKeyCode
    let isKeyDown: Bool
    let modifiers: CGEventFlags

    var isKeyUp: Bool { !isKeyDown }
}
