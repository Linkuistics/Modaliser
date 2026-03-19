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
                theme: theme
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
