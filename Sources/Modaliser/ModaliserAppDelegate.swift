import AppKit

final class ModaliserAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var keyboardCapture: KeyboardCapture?
    private var schemeEngine: SchemeEngine?
    private var keyEventDispatcher: KeyEventDispatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()
        loadSchemeConfig()
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

    // MARK: - Scheme config

    private func loadSchemeConfig() {
        do {
            let engine = try SchemeEngine()
            schemeEngine = engine

            if let path = ConfigPathResolver().resolve() {
                try engine.evaluateFile(path)
                NSLog("Config loaded from: %@", path)
            } else {
                NSLog("No config.scm found")
            }

            let executor = CommandExecutor(engine: engine)
            keyEventDispatcher = KeyEventDispatcher(
                registry: engine.registry,
                executor: executor
            )
        } catch {
            NSLog("Failed to load Scheme config: %@", "\(error)")
        }
    }

    // MARK: - Keyboard capture

    private func startKeyboardCapture() {
        guard let dispatcher = keyEventDispatcher else {
            NSLog("Cannot start keyboard capture: dispatcher not initialized")
            return
        }

        keyboardCapture = KeyboardCapture { event in
            dispatcher.handleKeyEvent(event)
        }

        do {
            try keyboardCapture?.start()
        } catch {
            NSLog("Failed to start keyboard capture: %@", "\(error)")
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
