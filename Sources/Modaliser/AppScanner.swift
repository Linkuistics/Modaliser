import Foundation

/// Represents an installed macOS application.
struct InstalledApp {
    let name: String
    let directory: String
    let path: String
    let bundleId: String
}

/// Discovers installed .app bundles via Spotlight.
enum AppScanner {

    /// Query Spotlight for all application bundles.
    /// Returns apps sorted alphabetically by name, deduplicated.
    static func scanInstalledApps() -> [InstalledApp] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var apps: [InstalledApp] = []
        var seen: Set<String> = []

        for line in output.split(separator: "\n") {
            let path = String(line)
            guard path.hasSuffix(".app") else { continue }
            let url = URL(fileURLWithPath: path)
            let name = url.deletingPathExtension().lastPathComponent
            guard !seen.contains(name) else { continue }
            seen.insert(name)

            let directory = url.deletingLastPathComponent().path
            let bundleId = Bundle(path: path)?.bundleIdentifier ?? ""

            apps.append(InstalledApp(
                name: name,
                directory: directory,
                path: path,
                bundleId: bundleId
            ))
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }
}
