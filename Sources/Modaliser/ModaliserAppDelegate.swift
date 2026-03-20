import AppKit

final class ModaliserAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var keyboardCapture: KeyboardCapture?
    private var schemeEngine: SchemeEngine?
    private var keyEventDispatcher: KeyEventDispatcher?
    private var overlayPanel: OverlayPanel?
    private var overlayCoordinator: OverlayCoordinator?
    private var chooserWindowController: ChooserWindowController?
    private var chooserCoordinator: ChooserCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ConfigSetup.ensureConfigExists()
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
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Reveal Config in Finder", action: #selector(revealConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Relaunch", action: #selector(relaunch), keyEquivalent: ""))
        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Modaliser", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.toggle()
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let executable = ProcessInfo.processInfo.arguments[0]

        // Use `open -a` for .app bundles to preserve Accessibility TCC permissions.
        // For bare binaries (swift build), re-exec directly — inherits the process's TCC grants.
        let command: String
        if bundlePath.hasSuffix(".app") {
            command = "sleep 0.3 && open -a \"\(bundlePath)\""
        } else {
            command = "sleep 0.3 && \"\(executable)\""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func revealConfig() {
        ConfigSetup.revealInFinder()
    }

    @objc private func reloadConfig() {
        NSLog("Reloading config…")
        overlayCoordinator?.modalDidDeactivate()
        loadSchemeConfig()
        // Re-wire the keyboard capture to the new dispatcher
        if let dispatcher = keyEventDispatcher {
            keyboardCapture?.updateHandler { event in
                dispatcher.handleKeyEvent(event)
            }
        }
        NSLog("Config reloaded")
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

            let theme = engine.registry.theme ?? .default
            let panel = OverlayPanel()
            overlayPanel = panel
            let coordinator = OverlayCoordinator(
                presenter: panel,
                showDelay: theme.showDelay,
                theme: theme
            )
            overlayCoordinator = coordinator

            let executor = CommandExecutor(engine: engine)

            let chooserController = ChooserWindowController(theme: theme)
            chooserWindowController = chooserController
            let chooser = ChooserCoordinator(
                presenter: chooserController,
                sourceInvoker: SelectorSourceInvoker(engine: engine),
                executor: executor,
                theme: theme,
                searchMemory: SearchMemory()
            )
            chooserCoordinator = chooser

            keyEventDispatcher = KeyEventDispatcher(
                registry: engine.registry,
                executor: executor,
                overlayCoordinator: coordinator,
                chooserCoordinator: chooser
            )
        } catch {
            NSLog("Failed to load Scheme config: %@", "\(error)")
            ConfigErrorAlert.show(error: error)
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
            AccessibilityPermissionAlert.showAndTerminate()
        }
    }
}
