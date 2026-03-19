import AppKit

/// Keyboard event monitoring and dispatch for the chooser window.
extension ChooserWindowController {

    func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Returns true if the event was consumed.
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        if actionPanel.isActive {
            return handleActionPanelKey(keyCode: keyCode, flags: flags, event: event)
        }

        // Escape
        if keyCode == 53 {
            cancel()
            return true
        }

        // Arrow up
        if keyCode == 126 && flags.isSubset(of: [.function, .numericPad]) {
            moveSelection(by: -1)
            return true
        }

        // Arrow down
        if keyCode == 125 && flags.isSubset(of: [.function, .numericPad]) {
            moveSelection(by: 1)
            return true
        }

        // Return — select
        if keyCode == 36 && !flags.contains(.command) {
            confirmSelection()
            return true
        }

        // Cmd+Return — secondary action
        if keyCode == 36 && flags.contains(.command) {
            triggerSecondaryAction()
            return true
        }

        // Cmd+K — open action panel
        if keyCode == 40 && flags.contains(.command) {
            openActionPanel()
            return true
        }

        // Cmd+? (Cmd+Shift+/) — toggle help
        if keyCode == 44 && flags.contains(.command) && flags.contains(.shift) {
            toggleHelp()
            return true
        }

        // Cmd+1 through Cmd+9
        if flags.contains(.command),
           let chars = event.charactersIgnoringModifiers, let ch = chars.first,
           ch >= "1" && ch <= "9" {
            let index = Int(String(ch))! - 1
            confirmSelectionByIndex(index)
            return true
        }

        return false
    }

    private func handleActionPanelKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, event: NSEvent) -> Bool {
        // Escape — cancel everything
        if keyCode == 53 {
            cancel()
            return true
        }

        // Delete — go back to choices
        if keyCode == 51 {
            closeActionPanel()
            return true
        }

        // Arrow up
        if keyCode == 126 && flags.isSubset(of: [.function, .numericPad]) {
            moveSelection(by: -1)
            return true
        }

        // Arrow down
        if keyCode == 125 && flags.isSubset(of: [.function, .numericPad]) {
            moveSelection(by: 1)
            return true
        }

        // Return — run selected action
        if keyCode == 36 {
            confirmActionSelection()
            return true
        }

        // Digit keys 1-9
        if let chars = event.charactersIgnoringModifiers, let ch = chars.first,
           ch >= "1" && ch <= "9" && !flags.contains(.command) {
            confirmActionByDigit(Int(String(ch))!)
            return true
        }

        // Consume all keys while action panel is active
        return true
    }
}
