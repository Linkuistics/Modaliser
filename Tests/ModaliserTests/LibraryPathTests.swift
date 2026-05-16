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
}
