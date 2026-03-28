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
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("find-installed-apps", findInstalledAppsFunction))
        self.define(Procedure("activate-app", activateAppFunction))
        self.define(Procedure("reveal-in-finder", revealInFinderFunction))
        self.define(Procedure("open-with", openWithFunction))
        self.define(Procedure("launch-app", launchAppFunction))
        self.define(Procedure("open-url", openUrlFunction))
        self.define(Procedure("focused-app-bundle-id", focusedAppBundleIdFunction))
        self.define(Procedure("index-files", indexFilesFunction))
    }

    // MARK: - Functions

    /// (focused-app-bundle-id) → string or #f
    /// Returns the bundle identifier of the frontmost application, or #f if unavailable.
    private func focusedAppBundleIdFunction() -> Expr {
        if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            return .makeString(bundleId)
        }
        return .false
    }

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
        let bundleId = SchemeAlistLookup.lookupString(choice, key: "bundleId")
        let path = SchemeAlistLookup.lookupString(choice, key: "path")

        if let bundleId, !bundleId.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if let path {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        return .void
    }

    /// (reveal-in-finder choice-alist) → void
    /// Reveals the item at the path from a chooser choice alist in Finder.
    private func revealInFinderFunction(_ choice: Expr) throws -> Expr {
        guard let path = SchemeAlistLookup.lookupString(choice, key: "path") else { return .void }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        return .void
    }

    /// (open-with app-name path) → void
    /// Opens a file with a specific application.
    private func openWithFunction(_ appName: Expr, _ path: Expr) throws -> Expr {
        let app = try appName.asString()
        let filePath = try path.asString()
        guard let appURL = resolveApplicationURL(app) else { return .void }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: filePath)],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
        return .void
    }

    /// (launch-app name-or-bundle-id) → void
    /// Launches or focuses an application by display name or bundle identifier.
    /// Resolves via Launch Services (bundle ID) or Spotlight (display name).
    private func launchAppFunction(_ name: Expr) throws -> Expr {
        let appName = try name.asString()
        guard let appURL = resolveApplicationURL(appName) else { return .void }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
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

    // MARK: - File indexing

    /// (index-files root-paths-list) → list of alists with 'text, 'path, and 'kind keys
    /// Scans directories using FileManager.enumerator on a concurrent queue.
    /// Each root is scanned in parallel, results are merged.
    /// Includes both files and directories (directories use their name as search text
    /// for better fuzzy match scoring against directory names).
    private func indexFilesFunction(_ rootsExpr: Expr) throws -> Expr {
        var roots: [String] = []
        var current = rootsExpr
        while case .pair(let head, let tail) = current {
            var path = try head.asString()
            if path.hasPrefix("~") {
                path = NSString(string: path).expandingTildeInPath
            }
            roots.append(path)
            current = tail
        }

        let maxResults = 2000
        let maxDepth = 4
        let skipDirs: Set<String> = [
            ".git", ".svn", "node_modules", ".build", ".cache",
            "DerivedData", "__pycache__", ".Trash", "Library",
        ]

        struct IndexEntry {
            let name: String
            let path: String
            let isDirectory: Bool
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var allEntries: [IndexEntry] = []

        for root in roots {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let rootURL = URL(fileURLWithPath: root)
                let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
                guard let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                ) else { return }

                var localEntries: [IndexEntry] = []
                for case let url as URL in enumerator {
                    let depth = url.pathComponents.count - rootURL.pathComponents.count
                    if depth > maxDepth {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                        continue
                    }
                    let isDir = values.isDirectory ?? false
                    if isDir && skipDirs.contains(url.lastPathComponent) {
                        enumerator.skipDescendants()
                        continue
                    }
                    // Include both files and directories
                    if isDir || (values.isRegularFile ?? false) {
                        localEntries.append(IndexEntry(
                            name: url.lastPathComponent,
                            path: url.path,
                            isDirectory: isDir
                        ))
                        if localEntries.count >= maxResults { break }
                    }
                }
                lock.lock()
                allEntries.append(contentsOf: localEntries)
                lock.unlock()
            }
        }

        group.wait()

        let symbols = self.context.symbols
        var result: Expr = .null
        for entry in allEntries.prefix(maxResults).reversed() {
            let alist = SchemeAlistLookup.makeAlist([
                ("text", .makeString(entry.name)),
                ("path", .makeString(entry.path)),
                ("kind", .makeString(entry.isDirectory ? "directory" : "file")),
            ], symbols: symbols)
            result = .pair(alist, result)
        }
        return result
    }

    // MARK: - Helpers

    private func makeAppAlist(_ app: InstalledApp) -> Expr {
        SchemeAlistLookup.makeAlist([
            ("text", .makeString(app.name)),
            ("subText", .makeString(app.directory)),
            ("icon", .makeString(app.path)),
            ("iconType", .makeString("path")),
            ("bundleId", .makeString(app.bundleId)),
            ("path", .makeString(app.path)),
        ], symbols: self.context.symbols)
    }

    /// Resolves an application name or bundle identifier to a Launch Services URL.
    /// Tries bundle ID lookup first, then Spotlight query by display name.
    private func resolveApplicationURL(_ nameOrId: String) -> URL? {
        // Try as bundle identifier first
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: nameOrId) {
            return url
        }

        // Query Spotlight for the app by filesystem name
        let escaped = nameOrId.replacingOccurrences(of: "'", with: "'\\''")
        let query = "kMDItemContentType == 'com.apple.application-bundle' && kMDItemFSName == '\(escaped).app'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let appPath = output.components(separatedBy: "\n").first,
              !appPath.isEmpty else { return nil }

        // Resolve path → bundle ID → canonical Launch Services URL
        if let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
           let bundleId = bundle.bundleIdentifier,
           let resolvedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return resolvedURL
        }
        return URL(fileURLWithPath: appPath)
    }
}
