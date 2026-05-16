import Foundation
import Testing
@testable import Modaliser

@Suite("Library Path")
struct LibraryPathTests {

    @Test func prependLibraryPathIsExportedProcedure() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? prepend-library-path!)") == .true)
    }

    @Test func prependLibraryPathSilentlySkipsMissingDir() throws {
        let engine = try SchemeEngine()
        // Must not throw — LispKit's prependLibrarySearchPath returns false for
        // missing paths, and we surface that as a Scheme #f rather than an error.
        let result = try engine.evaluate(
            "(prepend-library-path! \"/definitely/does/not/exist/abc123\")"
        )
        #expect(result == .false)
    }

    @Test func userConfigRootResolvesUserLibrary() throws {
        // Build a tmp user-config root: <tmp>/foo/bar.sld
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-libpath-test-\(UUID().uuidString)",
                                   isDirectory: true)
        let fooDir = tmpRoot.appendingPathComponent("foo", isDirectory: true)
        try FileManager.default.createDirectory(at: fooDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        // Use (lispkit base) — LispKit's native-registered base — rather than
        // (scheme base), so the test doesn't depend on resolving
        // Libraries/scheme/base.sld via Bundle(identifier: "net.objecthub.LispKit"),
        // which is nil under swift test. (lispkit base) provides define and
        // string literals just like (scheme base) does.
        let libBody = """
        (define-library (foo bar)
          (export greet)
          (import (lispkit base))
          (begin
            (define (greet) "hello-from-foo-bar")))
        """
        try libBody.write(to: fooDir.appendingPathComponent("bar.sld"),
                          atomically: true, encoding: .utf8)

        let engine = try SchemeEngine(userConfigDir: tmpRoot.path)
        try engine.evaluate("(import (foo bar))")
        #expect(try engine.evaluate("(greet)").asString() == "hello-from-foo-bar")
    }
}
