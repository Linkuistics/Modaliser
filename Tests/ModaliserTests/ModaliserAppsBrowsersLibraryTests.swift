import Foundation
import Testing
@testable import Modaliser

// The `(modaliser apps safari)` and `(modaliser apps chrome)` suites are
// GONE, with their libraries (apps-own-their-bindings-k47). Both shipped
// nothing but a stock tree — keys, labels, groups — which is preference,
// not facility (ADR-0021), so there was no facility half left to keep.
// Safari's screen is authored inline in `default-config.scm` and rides
// `ConfigDslTests.defaultConfigSchemeLoadsWithoutErrors`; Chrome's ships
// as `Scheme/examples/chrome.scm` and rides
// `ConfigDslTests.exampleConfigsLoadWithoutErrors`. Asserting here that
// "t" is Tabs would have asserted preference.

@Suite("(modaliser apps dia) library")
struct ModaliserAppsDiaLibraryTests {
    /// Utilities-layer library (ADR-0019): machinery exports only, no
    /// fragment — the Dia SCREEN is preference, authored inline in user
    /// config. Assertions stay structural: tab-source / focus-tab! shell
    /// out to osascript and tab-step posts keystrokes, so none may fire
    /// in tests.
    @Test func exportsResolveAsProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (prefix (modaliser apps dia) dia:))")
        #expect(try engine.evaluate("(procedure? dia:tab-source)") == .true)
        #expect(try engine.evaluate("(procedure? dia:focus-tab!)") == .true)
        #expect(try engine.evaluate("(procedure? dia:tab-step)") == .true)
        #expect(try engine.evaluate("(procedure? dia:tab-step-back)") == .true)
    }
}
