import AppKit
import CoreGraphics
import LispKit

/// Native LispKit library providing macOS app lifecycle primitives.
/// Scheme name: (modaliser lifecycle)
///
/// Provides: set-activation-policy!, create-status-item!, update-status-item!,
/// remove-status-item!, request-accessibility!, request-screen-recording!,
/// relaunch!, quit!
///
/// Scheme calls these during initialization to set up the app — activation policy,
/// menu bar, permissions. This establishes the model for writing desktop apps in Scheme.
final class LifecycleLibrary: NativeLibrary {

    private var statusItems: [Int64: NSStatusItem] = [:]
    private var menuActionHandlers: [ObjectIdentifier: Expr] = [:]
    private var nextStatusItemId: Int64 = 1

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
        self.define(Procedure("request-accessibility!", requestAccessibilityFunction))
        self.define(Procedure("request-screen-recording!", requestScreenRecordingFunction))
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

    /// (request-accessibility!) → boolean
    private func requestAccessibilityFunction() -> Expr {
        AccessibilityPermission.requestIfNeeded() ? .true : .false
    }

    /// (request-screen-recording!) → boolean
    private func requestScreenRecordingFunction() -> Expr {
        if CGPreflightScreenCaptureAccess() {
            return .true
        }
        CGRequestScreenCaptureAccess()
        return CGPreflightScreenCaptureAccess() ? .true : .false
    }

    // MARK: - App lifecycle

    /// (relaunch!) → void
    private func relaunchFunction() throws -> Expr {
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
        try process.run()
        NSApp.terminate(nil)
        return .void
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
