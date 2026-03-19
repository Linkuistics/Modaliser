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

            // Load config.scm from the app bundle directory
            let configPath = findConfigPath()
            if let path = configPath {
                try engine.evaluateFile(path)
                NSLog("Config loaded from: %@", path)
            } else {
                NSLog("No config.scm found")
            }

            // Create the dispatcher that bridges keyboard events to the state machine
            let executor = CommandExecutor(engine: engine)
            keyEventDispatcher = KeyEventDispatcher(
                registry: engine.registry,
                executor: executor
            )
        } catch {
            NSLog("Failed to load Scheme config: %@", "\(error)")
        }
    }

    private func findConfigPath() -> String? {
        // Look for config.scm in these locations (first found wins):
        // 1. ~/.config/modaliser/config.scm
        // 2. Adjacent to the executable (for development)
        let homeConfig = NSHomeDirectory() + "/.config/modaliser/config.scm"
        if FileManager.default.fileExists(atPath: homeConfig) {
            return homeConfig
        }

        // Development: config.scm in the project root
        let devConfig = FileManager.default.currentDirectoryPath + "/config.scm"
        if FileManager.default.fileExists(atPath: devConfig) {
            return devConfig
        }

        return nil
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
