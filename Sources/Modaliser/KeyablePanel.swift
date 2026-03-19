import AppKit

/// NSPanel subclass that can become the key window.
/// Required for the chooser to receive keyboard events in the search field.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
