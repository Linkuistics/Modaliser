import Foundation
import Testing
@testable import Modaliser

@Suite("SysSync")
struct SysSyncTests {
    private func makeBundleDir() throws -> String {
        let tmp = NSTemporaryDirectory() + "modaliser-syssync-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmp + "/lib/modaliser", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tmp + "/ui", withIntermediateDirectories: true)
        try "base.css contents".write(toFile: tmp + "/base.css", atomically: true, encoding: .utf8)
        try "(library)".write(toFile: tmp + "/lib/modaliser/foo.sld", atomically: true, encoding: .utf8)
        try "window.x = 1".write(toFile: tmp + "/ui/overlay.js", atomically: true, encoding: .utf8)
        return tmp
    }

    private func makeUserConfigDir() -> String {
        let tmp = NSTemporaryDirectory() + "modaliser-userconfig-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test func syncMirrorsEntireSchemeTreeIntoSysScheme() throws {
        let bundle = try makeBundleDir()
        let userConfig = makeUserConfigDir()
        let result = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        #expect(result != nil)
        let sysScheme = userConfig + "/sys/scheme"
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: sysScheme + "/base.css"))
        #expect(fm.fileExists(atPath: sysScheme + "/lib/modaliser/foo.sld"))
        #expect(fm.fileExists(atPath: sysScheme + "/ui/overlay.js"))
        let base = try String(contentsOfFile: sysScheme + "/base.css", encoding: .utf8)
        #expect(base == "base.css contents")
    }

    @Test func syncReturnsSysRootForLibraryPath() throws {
        let bundle = try makeBundleDir()
        let userConfig = makeUserConfigDir()
        let result = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        // sysRoot is the parent of sys/scheme/lib so prependLibrarySearchPath(sysRoot + "/scheme/lib")
        // resolves (modaliser foo) → sys/scheme/lib/modaliser/foo.sld.
        // Returned value points at userConfig/sys/scheme so the caller can compose paths from it.
        #expect(result == userConfig + "/sys/scheme")
    }

    @Test func unchangedFingerprintSkipsRecopy() throws {
        let bundle = try makeBundleDir()
        let userConfig = makeUserConfigDir()
        _ = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        // Touch the synced file to detect whether sync re-copies on second call
        let copiedPath = userConfig + "/sys/scheme/base.css"
        try "modified after sync".write(toFile: copiedPath, atomically: true, encoding: .utf8)
        _ = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        let after = try String(contentsOfFile: copiedPath, encoding: .utf8)
        #expect(after == "modified after sync")  // unchanged — sync was a no-op
    }

    @Test func emptyBundleTreeFailsTheSync() throws {
        let fm = FileManager.default
        let bundle = NSTemporaryDirectory() + "modaliser-syssync-\(UUID().uuidString)"
        try fm.createDirectory(atPath: bundle + "/lib", withIntermediateDirectories: true)
        let userConfig = makeUserConfigDir()
        let result = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        #expect(result == nil)
        #expect(!fm.fileExists(atPath: userConfig + "/sys/scheme"))
        #expect(!fm.fileExists(atPath: userConfig + "/sys/.bundle-fingerprint"))
    }

    @Test func emptyBundleDoesNotReadAsAlreadySynced() throws {
        let fm = FileManager.default
        let bundle = try makeBundleDir()
        let userConfig = makeUserConfigDir()
        _ = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        // Empty fingerprint file + file-less bundle tree used to compare
        // "" == "" and report the stale mirror as already synced.
        try fm.removeItem(atPath: userConfig + "/sys/.bundle-fingerprint")
        let emptyBundle = NSTemporaryDirectory() + "modaliser-syssync-\(UUID().uuidString)"
        try fm.createDirectory(atPath: emptyBundle + "/lib", withIntermediateDirectories: true)
        let result = SysSync.sync(bundleSchemeDir: emptyBundle, userConfigDir: userConfig)
        #expect(result == nil)
    }

    @Test func syncWritesGeneratedReadmeAtSysRoot() throws {
        let bundle = try makeBundleDir()
        let userConfig = makeUserConfigDir()
        _ = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        let readme = try String(contentsOfFile: userConfig + "/sys/README.md", encoding: .utf8)
        #expect(readme.contains("do not edit"))
        #expect(readme.contains("sys/scheme/default-config.scm"))
    }

    @Test func resyncRestoresEditedReadme() throws {
        let bundle = try makeBundleDir()
        let userConfig = makeUserConfigDir()
        _ = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        let readmePath = userConfig + "/sys/README.md"
        try "user edits".write(toFile: readmePath, atomically: true, encoding: .utf8)
        // A new bundle file changes the fingerprint, forcing a real re-sync.
        try "(bar)".write(toFile: bundle + "/lib/modaliser/bar.sld", atomically: true, encoding: .utf8)
        _ = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        let readme = try String(contentsOfFile: readmePath, encoding: .utf8)
        #expect(readme.contains("do not edit"))
    }

    @Test func unremovableStaleMirrorFailsTheSync() throws {
        // Pins the failure contract around the remove step: a mirror that
        // cannot be wiped must fail the sync (nil), never cache success.
        let fm = FileManager.default
        let bundle = try makeBundleDir()
        let userConfig = makeUserConfigDir()
        _ = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        let sysRoot = userConfig + "/sys"
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sysRoot)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sysRoot) }
        try "(bar)".write(toFile: bundle + "/lib/modaliser/bar.sld", atomically: true, encoding: .utf8)
        let result = SysSync.sync(bundleSchemeDir: bundle, userConfigDir: userConfig)
        #expect(result == nil)
    }
}
