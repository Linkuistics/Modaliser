import Foundation

/// Represents an installed macOS application.
struct InstalledApp {
    let name: String
    let directory: String
    let path: String
    let bundleId: String
}

/// Scans the filesystem for installed .app bundles.
enum AppScanner {

    private static let searchDirectories = [
        "/Applications",
        NSString("~/Applications").expandingTildeInPath,
    ]

    /// Scan /Applications and ~/Applications for .app bundles.
    /// Returns apps sorted alphabetically by name, deduplicated.
    static func scanInstalledApps() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen: Set<String> = []

        for directory in searchDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".app") {
                let name = String(entry.dropLast(4))  // Remove .app
                guard !seen.contains(name) else { continue }
                seen.insert(name)

                let path = "\(directory)/\(entry)"
                let bundleId = Bundle(path: path)?.bundleIdentifier ?? ""

                apps.append(InstalledApp(
                    name: name,
                    directory: directory,
                    path: path,
                    bundleId: bundleId
                ))
            }
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }
}
