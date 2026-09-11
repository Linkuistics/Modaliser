import Foundation
import Testing

@testable import Modaliser

@Suite("VSCode Grove Leaf composition")
struct ModaliserVscodeGroveCleanupTests {
    private static let partsReply = #"""
        {"result":{"protocol":1,"focused":true,"peer":"/tmp/initiating.sock","workspace":"/p",
          "editors":[
            {"token":1,"path":"/p/.grove/01-impl--old-k1.md"},
            {"token":2,"path":"/p/.grove/nested/02-DONE-impl--old-k2.md"},
            {"token":3,"path":"/p-other/.grove/01-impl--old-k1.md"},
            {"token":4,"path":"/p/.grove/BRIEF.md"},
            {"token":5,"path":"/p/.grove/01-impl--dirty-k5.md","dirty":true},
            {"token":null,"path":null},
            {"token":6,"path":"/p/.grove/01-impl--old-k1.md"}]}}
        """#

    @Test(arguments: [true, false], [true, false])
    func cleanupUsesTheSnapshotPeerAndRevealRemainsAsynchronous(hasLeaf: Bool, sendThrows: Bool) throws {
        let engine = try SchemeEngine()
        let schemePath = try #require(engine.schemeDirectoryPath)
        try engine.evaluateFile(schemePath + "/examples/vscode.scm")
        let pointer = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pointer) }
        try "/tmp/initiating.sock".write(to: pointer, atomically: true, encoding: .utf8)
        try engine.evaluate(
            """
            (import (modaliser shell) (modaliser json) (modaliser util))
            (code:current-vscode-socket-pointer-path "\(pointer.path)")
            (define events '())
            (define callback #f)
            (current-dialog-runner (lambda (cmd cb . opts)
              (if (string-contains? cmd "No live grove leaf for this window.")
                  (set! events (cons 'no-leaf events))
                  (error "unexpected dialog"))))
            (current-shell-runner (lambda (cmd)
              (set! events (cons 'pick events))
              "\(hasLeaf ? "/p/.grove/04-impl--live-k4.md" : "")"))
            (current-shell-async-runner (lambda (cmd cb . opts)
              (set! events (cons 'reveal events)) (set! callback cb)))
            (code:current-vscode-query-runner (lambda (peer method params)
              (json-parse \(schemeString(Self.partsReply)))))
            (code:current-vscode-notify-runner (lambda (peer method params)
              (set! events (cons (list peer method (cdr (assoc "token" params))) events))
              ;; A pointer switch cannot redirect later rows of this snapshot.
              (code:current-vscode-socket-pointer-path #f)
              \(sendThrows ? "(error \"send failed\")" : "#f")))
            (vscode-show-grove-leaf! (lambda () (set! events (cons 'follow-up events))))
            """)
        #expect(
            try engine.evaluate(
                """
                (equal? (reverse events)
                  '(("/tmp/initiating.sock" "close-editor-if-missing" 1)
                    ("/tmp/initiating.sock" "close-editor-if-missing" 2)
                    ("/tmp/initiating.sock" "close-editor-if-missing" 6)
                    pick \(hasLeaf ? "reveal" : "no-leaf")))
                """) == .true)
        if hasLeaf {
            #expect(try engine.evaluate("(procedure? callback)") == .true)
            try engine.evaluate(#"(callback 0 "" "")"#)
            #expect(try engine.evaluate("(eq? (car events) 'follow-up)") == .true)
        } else {
            #expect(try engine.evaluate("callback") == .false)
        }
    }

    private func schemeString(_ text: String) -> String {
        "\""
            + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}
