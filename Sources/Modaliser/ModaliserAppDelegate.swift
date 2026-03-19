import AppKit

final class ModaliserAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var keyboardCapture: KeyboardCapture?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()
        startKeyboardCapture()
        NSLog("Modaliser launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardCapture?.stop()
        NSLog("Modaliser shutting down")
    }

    // MARK: - Status bar

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "⌨"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Modaliser", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Keyboard capture

    private func startKeyboardCapture() {
        keyboardCapture = KeyboardCapture { event in
            guard event.isKeyDown else { return }
            switch event.keyCode {
            case KeyCode.f18:
                NSLog("F18 pressed — global leader")
            case KeyCode.f17:
                NSLog("F17 pressed — local leader")
            default:
                break
            }
        }

        do {
            try keyboardCapture?.start()
        } catch {
            NSLog("Failed to start keyboard capture: \(error)")
            showAccessibilityPermissionAlert()
        }
    }

    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Modaliser needs Accessibility access to capture global keyboard events. Please grant access in System Settings > Privacy & Security > Accessibility, then relaunch."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        NSApp.terminate(nil)
    }
}
