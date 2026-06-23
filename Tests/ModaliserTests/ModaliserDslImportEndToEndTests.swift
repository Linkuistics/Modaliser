import Foundation
import Testing
@testable import Modaliser

@Suite("End-to-end: user library imports (modaliser dsl)")
struct ModaliserDslImportEndToEndTests {
    @Test func userLibraryCanImportModaliserDslAndRegisterScreen() throws {
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-dsl-e2e-\(UUID().uuidString)",
                                   isDirectory: true)
        let userDir = tmpRoot.appendingPathComponent("user", isDirectory: true)
        try FileManager.default.createDirectory(at: userDir,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let libBody = """
        (define-library (user bindings)
          (export register!)
          (import (scheme base)
                  (modaliser dsl)
                  (modaliser state-machine))
          (begin
            (define (register!)
              (screen 'global
                (key "s" "Safari" (lambda () 'ok))))))
        """
        try libBody.write(to: userDir.appendingPathComponent("bindings.sld"),
                          atomically: true, encoding: .utf8)

        let engine = try SchemeEngine(userConfigDir: tmpRoot.path)
        try engine.evaluate("(import (user bindings))")
        try engine.evaluate("(register!)")
        try engine.evaluate("(import (modaliser state-machine))")
        #expect(try engine.evaluate("(lookup-tree \"global\")") != .false)
    }
}
