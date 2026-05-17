import Foundation

/// Mirror the bundled `(modaliser …)` libraries into
/// `~/.config/modaliser/sys/modaliser/` so users can read them in place
/// (forking is a `cp` into the user-config root, which already shadows
/// `sys/` on the library search path).
///
/// Sync trigger: a fingerprint over the bundle's `lib/modaliser/` tree
/// (relative path + mtime per file). Cheap to compute (~14 stats) and
/// always correct — catches both upgrades and dev rebuilds. Stored in
/// `sys/.bundle-fingerprint`; mismatch (or missing) → wipe + re-copy.
///
/// Edits to files under `sys/` are NOT preserved across syncs — the
/// design surfaces them as "obviously not yours" by being silently
/// overwritten. The recommended workflow for a local patch is to copy
/// the file to `~/.config/modaliser/modaliser/<name>.sld`, which takes
/// precedence on the search path.
enum SysSync {
    /// Sync the bundle's `lib/modaliser/` directory into the user
    /// config's `sys/modaliser/`. Returns the path to use as the sys
    /// search root if the sync succeeded (or was already current), or
    /// nil on failure — callers should fall through to the bundle.
    static func sync(bundleLibModaliserDir: String, userConfigDir: String) -> String? {
        let fm = FileManager.default
        let sysRoot = (userConfigDir as NSString).appendingPathComponent("sys")
        let sysLibDir = (sysRoot as NSString).appendingPathComponent("modaliser")
        let fingerprintPath = (sysRoot as NSString).appendingPathComponent(".bundle-fingerprint")

        guard let fingerprint = fingerprint(of: bundleLibModaliserDir) else {
            NSLog("SysSync: bundle modaliser libs dir missing at %@", bundleLibModaliserDir)
            return nil
        }

        let cached = (try? String(contentsOfFile: fingerprintPath, encoding: .utf8)) ?? ""
        if cached == fingerprint && fm.fileExists(atPath: sysLibDir) {
            return sysRoot
        }

        do {
            try? fm.removeItem(atPath: sysLibDir)
            try fm.createDirectory(atPath: sysRoot, withIntermediateDirectories: true)
            try fm.copyItem(atPath: bundleLibModaliserDir, toPath: sysLibDir)
            try fingerprint.write(toFile: fingerprintPath, atomically: true, encoding: .utf8)
            NSLog("SysSync: synced %@ -> %@", bundleLibModaliserDir, sysLibDir)
            return sysRoot
        } catch {
            NSLog("SysSync: copy failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// Fingerprint = sorted "<relpath>:<mtime>" lines over the directory
    /// tree. Single sorted string so any add/remove/touch changes it.
    private static func fingerprint(of dir: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return nil }
        var lines: [String] = []
        while let rel = enumerator.nextObject() as? String {
            let full = (dir as NSString).appendingPathComponent(rel)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let type = attrs[.type] as? FileAttributeType,
                  type == .typeRegular,
                  let mtime = attrs[.modificationDate] as? Date else { continue }
            lines.append("\(rel):\(mtime.timeIntervalSince1970)")
        }
        lines.sort()
        return lines.joined(separator: "\n")
    }
}
