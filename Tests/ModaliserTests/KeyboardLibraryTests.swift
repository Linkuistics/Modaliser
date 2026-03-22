import Testing
import LispKit
@testable import Modaliser

@Suite("Keyboard Library")
struct KeyboardLibraryTests {

    // MARK: - Library registration

    @Test func keyboardFunctionsExist() throws {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("start-keyboard-capture!")
        _ = try engine.evaluate("stop-keyboard-capture!")
        _ = try engine.evaluate("register-hotkey!")
        _ = try engine.evaluate("unregister-hotkey!")
        _ = try engine.evaluate("register-all-keys!")
        _ = try engine.evaluate("unregister-all-keys!")
        _ = try engine.evaluate("keycode->char")
    }

    @Test func allFunctionsAreProcedures() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? start-keyboard-capture!)") == .true)
        #expect(try engine.evaluate("(procedure? stop-keyboard-capture!)") == .true)
        #expect(try engine.evaluate("(procedure? register-hotkey!)") == .true)
        #expect(try engine.evaluate("(procedure? unregister-hotkey!)") == .true)
        #expect(try engine.evaluate("(procedure? register-all-keys!)") == .true)
        #expect(try engine.evaluate("(procedure? unregister-all-keys!)") == .true)
        #expect(try engine.evaluate("(procedure? keycode->char)") == .true)
    }

    // MARK: - Key code constants

    @Test func keyCodeConstantsExist() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("F17") == .fixnum(Int64(KeyCode.f17)))
        #expect(try engine.evaluate("F18") == .fixnum(Int64(KeyCode.f18)))
        #expect(try engine.evaluate("F19") == .fixnum(Int64(KeyCode.f19)))
        #expect(try engine.evaluate("F20") == .fixnum(Int64(KeyCode.f20)))
        #expect(try engine.evaluate("ESCAPE") == .fixnum(Int64(KeyCode.escape)))
        #expect(try engine.evaluate("DELETE") == .fixnum(Int64(KeyCode.delete)))
        #expect(try engine.evaluate("RETURN") == .fixnum(Int64(KeyCode.returnKey)))
        #expect(try engine.evaluate("TAB") == .fixnum(Int64(KeyCode.tab)))
        #expect(try engine.evaluate("SPACE") == .fixnum(Int64(KeyCode.space)))
    }

    @Test func modifierConstantsExist() throws {
        let engine = try SchemeEngine()
        // Modifier constants should be fixnums
        let modCmd = try engine.evaluate("MOD-CMD")
        let modShift = try engine.evaluate("MOD-SHIFT")
        let modAlt = try engine.evaluate("MOD-ALT")
        let modCtrl = try engine.evaluate("MOD-CTRL")
        if case .fixnum = modCmd { } else { Issue.record("MOD-CMD should be fixnum") }
        if case .fixnum = modShift { } else { Issue.record("MOD-SHIFT should be fixnum") }
        if case .fixnum = modAlt { } else { Issue.record("MOD-ALT should be fixnum") }
        if case .fixnum = modCtrl { } else { Issue.record("MOD-CTRL should be fixnum") }
    }

    // MARK: - keycode->char

    @Test func keycodeToCharReturnsStringForKnownKey() throws {
        let engine = try SchemeEngine()
        // Key code 0 is 'a' on US keyboard
        let result = try engine.evaluate("(keycode->char 0)")
        #expect(result == .makeString("a"))
    }

    @Test func keycodeToCharReturnsFalseForUnknownKey() throws {
        let engine = try SchemeEngine()
        // Very high key code — should be unmapped
        let result = try engine.evaluate("(keycode->char 255)")
        #expect(result == .false)
    }

    @Test func keycodeToCharMapsCommonKeys() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(keycode->char 1)") == .makeString("s"))
        #expect(try engine.evaluate("(keycode->char 2)") == .makeString("d"))
        #expect(try engine.evaluate("(keycode->char 3)") == .makeString("f"))
    }

    // MARK: - register-hotkey! / unregister-hotkey!

    @Test func registerHotkeyAcceptsKeycodeAndHandler() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(register-hotkey! F18 (lambda () #t))")
        #expect(result == .void)
    }

    @Test func unregisterHotkeyAcceptsKeycode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(register-hotkey! F18 (lambda () #t))")
        let result = try engine.evaluate("(unregister-hotkey! F18)")
        #expect(result == .void)
    }

    @Test func unregisterHotkeyForUnregisteredKeyDoesNotThrow() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(unregister-hotkey! F18)")
        #expect(result == .void)
    }

    // MARK: - register-all-keys! / unregister-all-keys!

    @Test func registerAllKeysAcceptsHandler() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(register-all-keys! (lambda (keycode mods) #t))")
        #expect(result == .void)
        // Clean up
        try engine.evaluate("(unregister-all-keys!)")
    }

    @Test func unregisterAllKeysWhenNoneRegistered() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate("(unregister-all-keys!)")
        #expect(result == .void)
    }

    // MARK: - Dispatch logic (tested via KeyboardHandlerRegistry)

    @Test func registryDispatchesCatchAllFirst() throws {
        let registry = KeyboardHandlerRegistry()
        var catchAllCalled = false
        var hotkeyCalled = false

        registry.catchAllHandler = { _, _ in catchAllCalled = true; return true }
        registry.hotkeyHandlers[64] = { hotkeyCalled = true }  // F17

        let result = registry.dispatch(keyCode: 64, modifiers: [])
        #expect(result == .suppress)
        #expect(catchAllCalled)
        #expect(!hotkeyCalled)
    }

    @Test func registryDispatchesHotkeyWhenNoCatchAll() throws {
        let registry = KeyboardHandlerRegistry()
        var hotkeyCalled = false

        registry.hotkeyHandlers[64] = { hotkeyCalled = true }

        let result = registry.dispatch(keyCode: 64, modifiers: [])
        #expect(result == .suppress)
        #expect(hotkeyCalled)
    }

    @Test func registryPassesThroughWhenNoHandlers() throws {
        let registry = KeyboardHandlerRegistry()

        let result = registry.dispatch(keyCode: 42, modifiers: [])
        #expect(result == .passThrough)
    }

    @Test func registryCatchAllReturnFalsePassesThrough() throws {
        let registry = KeyboardHandlerRegistry()
        registry.catchAllHandler = { _, _ in return false }

        let result = registry.dispatch(keyCode: 42, modifiers: [])
        #expect(result == .passThrough)
    }
}
