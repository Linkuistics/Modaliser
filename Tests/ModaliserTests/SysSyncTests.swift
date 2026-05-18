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
}
