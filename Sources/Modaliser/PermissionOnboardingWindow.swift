import AppKit

/// First-run permission gate for permissions whose grant state can be polled live
/// in the running process (Accessibility today; Input Monitoring etc. in future).
/// Screen Recording is intentionally NOT handled here — its TCC state is cached
/// per-process, so polling can't observe a grant. The caller hands SR to the OS
/// prompt instead. See ensurePermissionsFunction in LifecycleLibrary.
final class PermissionOnboardingWindow: NSObject, NSWindowDelegate {
    private struct RowControls {
        let indicator: NSImageView
        let button: NSButton
    }

    private let window: NSWindow
    private let permissions: [RequiredPermission]
    private let onAllGranted: () -> Void
    private var rows: [RequiredPermission: RowControls] = [:]
    private var pollTimer: Timer?
    private var footerLabel: NSTextField!
    private var didFinish = false

    init(permissions: [RequiredPermission], onAllGranted: @escaping () -> Void) {
        self.permissions = permissions
        self.onAllGranted = onAllGranted

        let contentRect = NSRect(x: 0, y: 0, width: 520, height: 0)  // height auto-sized
        self.window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.window.title = "Modaliser"
        self.window.isReleasedWhenClosed = false

        super.init()
        self.window.delegate = self
        self.buildContentView()
        self.window.center()
    }

    /// Block until all permissions granted (calls onAllGranted) or window closed (terminates).
    /// Must be called on the main thread.
    func runModal() {
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
        NSApp.runModal(for: window)
    }

    // MARK: - UI

    private func buildContentView() {
        let title = NSTextField(labelWithString: "Modaliser needs permission to run")
        title.font = NSFont.boldSystemFont(ofSize: 16)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Click Open Settings for each item below and toggle Modaliser on. " +
            "This window updates automatically once each permission is granted.")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 472

        let grid = NSGridView()
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        for permission in permissions {
            let indicator = NSImageView()
            indicator.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                indicator.widthAnchor.constraint(equalToConstant: 20),
                indicator.heightAnchor.constraint(equalToConstant: 20)
            ])

            let nameLabel = NSTextField(labelWithString: permission.displayName)
            nameLabel.font = NSFont.boldSystemFont(ofSize: 13)

            let rationaleLabel = NSTextField(labelWithString: permission.rationale)
            rationaleLabel.font = NSFont.systemFont(ofSize: 11)
            rationaleLabel.textColor = .secondaryLabelColor

            let textStack = NSStackView(views: [nameLabel, rationaleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2

            let button = NSButton(title: "Open Settings", target: self, action: #selector(openSettingsClicked(_:)))
            button.bezelStyle = .rounded

            grid.addRow(with: [indicator, textStack, button])
            rows[permission] = RowControls(indicator: indicator, button: button)
            updateIndicator(indicator, granted: false)
        }

        // Tabular alignment: NSGridView aligns columns across rows automatically,
        // so the buttons line up without forcing a fixed column width. Forcing
        // column 1 wider than the content area pushes the button column off-window.
        grid.column(at: 0).xPlacement = .center
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 2).xPlacement = .trailing

        footerLabel = NSTextField(labelWithString: " ")
        footerLabel.font = NSFont.systemFont(ofSize: 12)
        footerLabel.textColor = .secondaryLabelColor

        let outer = NSStackView(views: [title, subtitle, grid, footerLabel])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 14
        outer.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        outer.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            outer.topAnchor.constraint(equalTo: content.topAnchor),
            outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 520)
        ])

        window.contentView = content
    }

    @objc private func openSettingsClicked(_ sender: NSButton) {
        guard let permission = rows.first(where: { $0.value.button === sender })?.key else { return }
        NSWorkspace.shared.open(permission.settingsURL)
    }

    private func updateIndicator(_ view: NSImageView, granted: Bool) {
        let symbolName = granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        let color: NSColor = granted ? .systemGreen : .systemOrange
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: granted ? "Granted" : "Not granted"
        )?.withSymbolConfiguration(config)
        view.image = image
        view.contentTintColor = color
    }

    // MARK: - Polling

    private func startPolling() {
        refreshStatuses()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshStatuses()
        }
        // Add in both default and modal modes so the timer fires while runModal owns the loop.
        RunLoop.main.add(timer, forMode: .modalPanel)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func refreshStatuses() {
        for permission in permissions {
            if let controls = rows[permission] {
                updateIndicator(controls.indicator, granted: permission.isGranted)
            }
        }
        guard !didFinish, permissions.allSatisfy({ $0.isGranted }) else { return }
        didFinish = true
        pollTimer?.invalidate()
        pollTimer = nil
        footerLabel.stringValue = "All permissions granted — relaunching…"

        // Brief pause so the user sees the success state before the app bounces.
        // We deliberately do NOT call NSApp.stopModal — onAllGranted relaunches the
        // process, and tearing the modal down ourselves would let Scheme continue
        // executing root.scm (status bar, keyboard capture) in a process about to die.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.window.orderOut(nil)
            self?.onAllGranted()
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // User dismissed the gate without granting — quit. Same rationale as above:
        // we don't stopModal first; terminate tears everything down cleanly.
        NSApp.terminate(nil)
        return false
    }
}

