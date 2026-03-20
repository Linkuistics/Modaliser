import AppKit
import LispKit

/// Native LispKit library providing application management.
/// Scheme name: (modaliser app)
///
/// Provides: find-installed-apps, activate-app, reveal-in-finder, open-with, launch-app, open-url
final class AppLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "app"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define", "assoc", "cdr")
    }

    public override func declarations() {
        self.define(Procedure("find-installed-apps", findInstalledAppsFunction))
        self.define(Procedure("activate-app", activateAppFunction))
        self.define(Procedure("reveal-in-finder", revealInFinderFunction))
        self.define(Procedure("open-with", openWithFunction))
        self.define(Procedure("launch-app", launchAppFunction))
        self.define(Procedure("open-url", openUrlFunction))
    }

    // MARK: - Functions

    /// (find-installed-apps) → list of alists
    /// Scans /Applications and ~/Applications for .app bundles.
    /// Each entry has: text, subText, icon, iconType, bundleId, path
    private func findInstalledAppsFunction() -> Expr {
        let apps = AppScanner.scanInstalledApps()
        var result: Expr = .null
        for app in apps.reversed() {
            let alist = makeAppAlist(app)
            result = .pair(alist, result)
        }
        return result
    }

    /// (activate-app choice-alist) → void
    /// Launches or focuses an app from a chooser choice alist.
    private func activateAppFunction(_ choice: Expr) throws -> Expr {
        let bundleId = lookupString(choice, key: "bundleId")
        let path = lookupString(choice, key: "path")

        if let bundleId, !bundleId.isEmpty {
            NSWorkspace.shared.launchApplication(
                withBundleIdentifier: bundleId,
                options: [],
                additionalEventParamDescriptor: nil,
                launchIdentifier: nil
            )
        } else if let path {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        return .void
    }

    /// (reveal-in-finder choice-alist) → void
    /// Reveals the item at the path from a chooser choice alist in Finder.
    private func revealInFinderFunction(_ choice: Expr) throws -> Expr {
        guard let path = lookupString(choice, key: "path") else { return .void }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        return .void
    }

    /// (open-with app-name path) → void
    /// Opens a file with a specific application.
    private func openWithFunction(_ appName: Expr, _ path: Expr) throws -> Expr {
        let app = try appName.asString()
        let filePath = try path.asString()
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: filePath)],
            withApplicationAt: applicationURL(forName: app),
            configuration: NSWorkspace.OpenConfiguration()
        )
        return .void
    }

    /// (launch-app name) → void
    /// Launches or focuses an application by name.
    private func launchAppFunction(_ name: Expr) throws -> Expr {
        let appName = try name.asString()
        NSWorkspace.shared.launchApplication(appName)
        return .void
    }

    /// (open-url url-string) → void
    /// Opens a URL in the default handler.
    private func openUrlFunction(_ urlExpr: Expr) throws -> Expr {
        let urlString = try urlExpr.asString()
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        return .void
    }

    // MARK: - Helpers

    private func makeAppAlist(_ app: InstalledApp) -> Expr {
        let entries: [(String, Expr)] = [
            ("text", .makeString(app.name)),
            ("subText", .makeString(app.directory)),
            ("icon", .makeString(app.path)),
            ("iconType", .makeString("path")),
            ("bundleId", .makeString(app.bundleId)),
            ("path", .makeString(app.path)),
        ]
        var result: Expr = .null
        for (key, value) in entries.reversed() {
            let pair = Expr.pair(.symbol(self.context.symbols.intern(key)), value)
            result = .pair(pair, result)
        }
        return result
    }

    private func lookupString(_ alist: Expr, key: String) -> String? {
        var current = alist
        while case .pair(let entry, let tail) = current {
            if case .pair(.symbol(let s), let value) = entry, s.identifier == key {
                return try? value.asString()
            }
            current = tail
        }
        return nil
    }

    private func applicationURL(forName name: String) -> URL {
        // Try common locations
        let paths = [
            "/Applications/\(name).app",
            NSString(string: "~/Applications/\(name).app").expandingTildeInPath,
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/Applications/\(name).app")
    }
}
