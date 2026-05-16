import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser terminal) library")
struct ModaliserTerminalLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        // Each exported name must be bound (no exception on evaluation).
        // modaliser-tool-path is a string, the rest are procedures.
        for name in [
            "focused-iterm-tty",
            "tty-foreground-command",
            "focused-terminal-foreground-command",
            "list-nvim-sockets",
            "nvim-server-focused?",
            "focused-nvim-socket",
            "nvim-remote-send",
            "nvim-remote-expr",
            "modaliser-tool-path"
        ] {
            _ = try engine.evaluate(name)
        }
    }
}
