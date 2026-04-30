import AppKit
import CoreGraphics
import LispKit

/// Native LispKit library providing macOS app lifecycle primitives.
/// Scheme name: (modaliser lifecycle)
///
/// Provides: set-activation-policy!, create-status-item!, update-status-item!,
/// remove-status-item!, ensure-permissions!, relaunch!, quit!, after-delay
///
/// Scheme calls these during initialization to set up the app — activation policy,
/// menu bar, permissions. This establishes the model for writing desktop apps in Scheme.
final class LifecycleLibrary: NativeLibrary {

    private var statusItems: [Int64: NSStatusItem] = [:]
    private var menuActionHandlers: [ObjectIdentifier: Expr] = [:]
    private var nextStatusItemId: Int64 = 1
    private var onboarding: PermissionOnboardingWindow?

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "lifecycle"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("set-activation-policy!", setActivationPolicyFunction))
        self.define(Procedure("create-status-item!", createStatusItemFunction))
        self.define(Procedure("update-status-item!", updateStatusItemFunction))
        self.define(Procedure("remove-status-item!", removeStatusItemFunction))
        self.define(Procedure("ensure-permissions!", ensurePermissionsFunction))
        self.define(Procedure("relaunch!", relaunchFunction))
        self.define(Procedure("quit!", quitFunction))
        self.define(Procedure("after-delay", afterDelayFunction))
    }

    // MARK: - Activation policy

    /// (set-activation-policy! 'accessory) → void
    /// Accepts: 'regular, 'accessory, 'prohibited
    private func setActivationPolicyFunction(_ policy: Expr) throws -> Expr {
        guard case .symbol(let sym) = policy else {
            throw RuntimeError.type(policy, expected: [.symbolType])
        }
        let appPolicy: NSApplication.ActivationPolicy
        switch sym.identifier {
        case "regular": appPolicy = .regular
        case "accessory": appPolicy = .accessory
        case "prohibited": appPolicy = .prohibited
        default:
            throw RuntimeError.custom(
                "eval",
                "Unknown activation policy: \(sym.identifier). Expected: regular, accessory, prohibited",
                []
            )
        }
        NSApp.setActivationPolicy(appPolicy)
        return .void
    }

    // MARK: - Status bar

    /// (create-status-item! title menu-items) → id
    /// menu-items is a list. Each element is either:
    ///   - an alist with keys: title, action, key-equivalent (optional)
    ///   - the symbol 'separator
    private func createStatusItemFunction(_ title: Expr, _ menuItems: Expr) throws -> Expr {
        let titleStr = try title.asString()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if titleStr == ":icon" {
            // Use the app icon as the status item image
            if let appIcon = NSApp.applicationIconImage {
                let size = NSSize(width: 18, height: 18)
                let resized = NSImage(size: size)
                resized.lockFocus()
                appIcon.draw(in: NSRect(origin: .zero, size: size))
                resized.unlockFocus()
                resized.isTemplate = true
                statusItem.button?.image = resized
            } else {
                statusItem.button?.title = "⌨"
            }
        } else {
            statusItem.button?.title = titleStr
        }

        let menu = try buildMenu(from: menuItems)
        statusItem.menu = menu

        let itemId = nextStatusItemId
        nextStatusItemId += 1
        statusItems[itemId] = statusItem
        return .fixnum(itemId)
    }

    /// (update-status-item! id title menu-items) → void
    private func updateStatusItemFunction(_ idExpr: Expr, _ title: Expr, _ menuItems: Expr) throws -> Expr {
        let itemId = try idExpr.asInt64()
        guard let statusItem = statusItems[itemId] else { return .void }
        statusItem.button?.title = try title.asString()
        statusItem.menu = try buildMenu(from: menuItems)
        return .void
    }

    /// (remove-status-item! id) → void
    private func removeStatusItemFunction(_ idExpr: Expr) throws -> Expr {
        let itemId = try idExpr.asInt64()
        if let statusItem = statusItems.removeValue(forKey: itemId) {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        return .void
    }

    // MARK: - Permissions

    /// (ensure-permissions! '(accessibility screen-recording)) → void
    ///
    /// Blocks until every listed permission has been surfaced to the user via the
    /// appropriate flow. Permissions split into two classes:
    ///
    ///   - **Pollable** (Accessibility, Input Monitoring): grant state updates live
    ///     in this process. Handled by our onboarding panel — shows status dots,
    ///     deep-link buttons, polls until all are granted, then auto-relaunches.
    ///
    ///   - **System-prompt** (Screen Recording): TCC state is cached per-process,
    ///     so we can't observe a grant in the running process. macOS provides its
    ///     own prompt with an "Open System Settings" CTA and handles the post-grant
    ///     "Quit & Reopen" flow. We just trigger the prompt and let the OS drive.
    ///
    /// On the already-granted path this returns immediately. When the panel runs,
    /// control typically does not come back to Scheme — the process either
    /// relaunches (all pollable granted) or terminates (user closed the panel).
    /// The OS Screen Recording prompt is fire-and-forget; we proceed regardless of
    /// the user's choice (a denial just means degraded window-switcher titles).
    private func ensurePermissionsFunction(_ list: Expr) throws -> Expr {
        var permissions: [RequiredPermission] = []
        var current = list
        while case .pair(let head, let tail) = current {
            guard case .symbol(let sym) = head else {
                throw RuntimeError.type(head, expected: [.symbolType])
            }
            guard let permission = RequiredPermission.parse(symbol: sym.identifier) else {
                throw RuntimeError.custom(
                    "eval",
                    "ensure-permissions!: unknown permission '\(sym.identifier)'. Expected: accessibility, screen-recording",
                    []
                )
            }
            permissions.append(permission)
            current = tail
        }

        // Step 1: pollable permissions (panel-driven).
        let pollable = permissions.filter { $0 != .screenRecording }
        let missingPollable = pollable.filter { !$0.isGranted }
        if !missingPollable.isEmpty {
            for permission in missingPollable {
                permission.registerWithTCC()
            }
            // Onboarding needs the app to be a foreground citizen so the window can
            // take focus and show up in Cmd-Tab. Restored to .accessory in root.scm
            // after the gate clears.
            NSApp.setActivationPolicy(.regular)
            let window = PermissionOnboardingWindow(permissions: missingPollable) {
                Self.performRelaunch()
            }
            self.onboarding = window
            window.runModal()
            // window.runModal returns only on programmatic stopModal (which we don't
            // call) or terminate. In practice the process is relaunching or quitting
            // by the time control reaches here.
            return .void
        }

        // Step 2: system-prompt permissions. Fire and forget — the OS owns the UI
        // and the post-grant restart flow. applicationShouldTerminate handles the
        // modal-unwind side of macOS's "Quit & Reopen" cleanly.
        for permission in permissions where permission == .screenRecording && !permission.isGranted {
            permission.registerWithTCC()
        }

        return .void
    }

    // MARK: - App lifecycle

    /// (relaunch!) → void
    private func relaunchFunction() -> Expr {
        Self.performRelaunch()
        return .void
    }

    /// Spawn a sibling process and terminate the current one. Used by both relaunch!
    /// and the permission-granted exit path inside the onboarding window.
    static func performRelaunch() {
        let bundlePath = Bundle.main.bundlePath
        let executable = ProcessInfo.processInfo.arguments[0]

        let command: String
        if bundlePath.hasSuffix(".app") {
            command = "sleep 0.3 && open -a \"\(bundlePath)\""
        } else {
            command = "sleep 0.3 && \"\(executable)\""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            NSLog("LifecycleLibrary: failed to spawn relaunch process: %@", "\(error)")
        }
        NSApp.terminate(nil)
    }

    /// (quit!) → void
    private func quitFunction() -> Expr {
        NSApp.terminate(nil)
        return .void
    }

    // MARK: - Timer

    /// (after-delay seconds callback) → void
    /// Calls (callback) on the main thread after the given delay in seconds.
    private func afterDelayFunction(_ delayExpr: Expr, _ callbackExpr: Expr) throws -> Expr {
        let seconds: Double
        if case .fixnum(let n) = delayExpr {
            seconds = Double(n)
        } else if case .flonum(let n) = delayExpr {
            seconds = n
        } else {
            throw RuntimeError.type(delayExpr, expected: [.floatType])
        }
        guard case .procedure = callbackExpr else {
            throw RuntimeError.custom("eval", "after-delay: second argument must be a procedure", [])
        }
        let context = self.context
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard let evaluator = context.evaluator else { return }
            _ = evaluator.execute { machine in
                try machine.apply(callbackExpr, to: .null)
            }
        }
        return .void
    }

    // MARK: - Menu building

    private func buildMenu(from menuItems: Expr) throws -> NSMenu {
        let menu = NSMenu()
        var current = menuItems
        while case .pair(let head, let tail) = current {
            if case .symbol(let sym) = head, sym.identifier == "separator" {
                menu.addItem(.separator())
            } else {
                let menuItem = try buildMenuItem(from: head)
                menu.addItem(menuItem)
            }
            current = tail
        }
        return menu
    }

    private func buildMenuItem(from alist: Expr) throws -> NSMenuItem {
        let title = SchemeAlistLookup.lookupString(alist, key: "title") ?? "?"
        let keyEquivalent = SchemeAlistLookup.lookupString(alist, key: "key-equivalent") ?? ""

        let menuItem = NSMenuItem(title: title, action: #selector(menuItemClicked(_:)), keyEquivalent: keyEquivalent)
        menuItem.target = self

        // Store the action handler keyed by this menu item's identity
        if let actionExpr = SchemeAlistLookup.lookupExpr(alist, key: "action") {
            menuActionHandlers[ObjectIdentifier(menuItem)] = actionExpr
        }

        return menuItem
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        let key = ObjectIdentifier(sender)
        guard let handler = menuActionHandlers[key] else { return }

        let result = self.context.evaluator.execute { machine in
            try machine.apply(handler, to: .null)
        }
        if case .error(let err) = result {
            NSLog("LifecycleLibrary: menu action error: %@", "\(err)")
        }
    }
}
