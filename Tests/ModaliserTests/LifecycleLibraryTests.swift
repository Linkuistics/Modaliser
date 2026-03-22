import Testing
import LispKit
@testable import Modaliser

@Suite("Lifecycle Library")
struct LifecycleLibraryTests {

    // MARK: - Library registration

    @Test func lifecycleFunctionsExist() throws {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("set-activation-policy!")
        _ = try engine.evaluate("create-status-item!")
        _ = try engine.evaluate("update-status-item!")
        _ = try engine.evaluate("remove-status-item!")
        _ = try engine.evaluate("request-accessibility!")
        _ = try engine.evaluate("request-screen-recording!")
        _ = try engine.evaluate("relaunch!")
        _ = try engine.evaluate("quit!")
    }

    @Test func allFunctionsAreProcedures() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? set-activation-policy!)") == .true)
        #expect(try engine.evaluate("(procedure? create-status-item!)") == .true)
        #expect(try engine.evaluate("(procedure? update-status-item!)") == .true)
        #expect(try engine.evaluate("(procedure? remove-status-item!)") == .true)
        #expect(try engine.evaluate("(procedure? request-accessibility!)") == .true)
        #expect(try engine.evaluate("(procedure? request-screen-recording!)") == .true)
        #expect(try engine.evaluate("(procedure? relaunch!)") == .true)
        #expect(try engine.evaluate("(procedure? quit!)") == .true)
    }

    // MARK: - set-activation-policy!

    @Test func setActivationPolicyRejectsInvalidSymbol() throws {
        let engine = try SchemeEngine()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-activation-policy! 'invalid)")
        }
    }

    @Test func setActivationPolicyRejectsNonSymbol() throws {
        let engine = try SchemeEngine()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-activation-policy! \"accessory\")")
        }
    }

    // MARK: - request-accessibility!

    @Test func requestAccessibilityReturnsBoolean() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(request-accessibility!)")
        #expect(result == .true || result == .false)
    }

    // MARK: - request-screen-recording!

    @Test func requestScreenRecordingReturnsBoolean() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(request-screen-recording!)")
        #expect(result == .true || result == .false)
    }

    // MARK: - remove-status-item!

    @Test func removeStatusItemWithInvalidIdDoesNotThrow() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(remove-status-item! 9999)")
        #expect(result == .void)
    }

    // Note: create-status-item!, update-status-item!, set-activation-policy! with valid values,
    // relaunch!, and quit! have side effects requiring a running NSApplication GUI session.
    // They are tested via manual integration testing, not unit tests.
}
