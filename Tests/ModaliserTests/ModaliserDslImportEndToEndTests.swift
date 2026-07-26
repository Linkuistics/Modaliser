import Foundation
import Testing
@testable import Modaliser

@Suite("End-to-end: user library imports (modaliser dsl)")
struct ModaliserDslImportEndToEndTests {
    @Test func userLibraryCanImportModaliserDslAndContributeScreen() throws {
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-dsl-e2e-\(UUID().uuidString)",
                                   isDirectory: true)
        let userDir = tmpRoot.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        // screen is PURE: the user library returns a tree contribution the
        // config composes into a configuration value and installs.
        let libBody = """
        (define-library (user bindings)
          (export global-screen)
          (import (scheme base)
                  (modaliser dsl))
          (begin
            (define (global-screen)
              (screen 'global
                (key "s" "Safari" (lambda () 'ok))))))
        """
        try libBody.write(to: userDir.appendingPathComponent("bindings.sld"),
                          atomically: true, encoding: .utf8)

        let engine = try SchemeEngine(userConfigDir: tmpRoot.path)
        try engine.evaluate("(import (user bindings))")
        try engine.evaluate("(import (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(fsm-install-graph! (lower-configuration (configuration (global-screen))))")
        #expect(try engine.evaluate("(fsm-state-ref \"global\")") != .false)
    }
}
