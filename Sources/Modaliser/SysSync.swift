import Foundation

/// Mirror the bundle's `Sources/Modaliser/Scheme/` tree into
/// `~/.config/modaliser/sys/scheme/` so users can read every bundled
/// `.scm`, `.sld`, `.css`, `.js`, `.svg` etc. in place. The user's
/// config root shadows `sys/` on the library search path and on any
/// `read-file-text` that resolves via `*scheme-directory*`, so the
/// user can fork any bundled file by copying it to a non-`sys/`
/// location under `~/.config/modaliser/`.
///
/// Sync trigger: a fingerprint over the bundle's `Scheme/` tree
/// (relative path + mtime per file). Stored in
/// `sys/.bundle-fingerprint`; mismatch (or missing) → wipe + re-copy.
///
/// Edits to files under `sys/` are NOT preserved across syncs —
/// silently overwritten. Recommended fork workflow: copy
/// `sys/scheme/lib/modaliser/foo.sld` to
/// `~/.config/modaliser/modaliser/foo.sld`, which takes precedence
/// on the library search path.
enum SysSync {
    /// Sync the bundle's `Scheme/` directory into the user config's
    /// `sys/scheme/`. Returns the path to `sys/scheme` (the new
    /// `*scheme-directory*` target) on success, or nil on failure —
    /// callers fall through to reading directly from the bundle.
    static func sync(bundleSchemeDir: String, userConfigDir: String) -> String? {
        let fm = FileManager.default
        let sysRoot = (userConfigDir as NSString).appendingPathComponent("sys")
        let sysSchemeDir = (sysRoot as NSString).appendingPathComponent("scheme")
        let fingerprintPath = (sysRoot as NSString).appendingPathComponent(".bundle-fingerprint")

        guard let fingerprint = fingerprint(of: bundleSchemeDir) else {
            NSLog("SysSync: bundle Scheme dir missing at %@", bundleSchemeDir)
            return nil
        }

        let cached = (try? String(contentsOfFile: fingerprintPath, encoding: .utf8)) ?? ""
        if cached == fingerprint && fm.fileExists(atPath: sysSchemeDir) {
            return sysSchemeDir
        }

        do {
            try? fm.removeItem(atPath: sysSchemeDir)
            try fm.createDirectory(atPath: sysRoot, withIntermediateDirectories: true)
            try fm.copyItem(atPath: bundleSchemeDir, toPath: sysSchemeDir)
            try fingerprint.write(toFile: fingerprintPath, atomically: true, encoding: .utf8)
            NSLog("SysSync: synced %@ -> %@", bundleSchemeDir, sysSchemeDir)
            return sysSchemeDir
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
