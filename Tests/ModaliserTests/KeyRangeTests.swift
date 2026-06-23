import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

private enum KeyRangeTestError: Error {
    case noSchemeDir
}

@Suite("Key Range (key-range DSL + dispatch + overlay render)")
struct KeyRangeTests {

    private func loadStack() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw KeyRangeTestError.noSchemeDir
        }
        try engine.evaluate("""
            (define webview-create-calls '())
            (define webview-close-calls '())
            (define webview-set-html-calls '())
            (define webview-on-message-calls '())
            (define webview-eval-calls '())
            (define (webview-create id opts)
              (set! webview-create-calls (cons (cons id opts) webview-create-calls)) id)
            (define (webview-close id)
              (set! webview-close-calls (cons id webview-close-calls)))
            (define (webview-set-html! id html)
              (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
            (define (webview-on-message id handler)
              (set! webview-on-message-calls (cons (cons id handler) webview-on-message-calls)))
            (define (webview-eval id js)
              (set! webview-eval-calls (cons (cons id js) webview-eval-calls)))
            """)
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser dom))")
        let files = [
            "ui/css.scm",
            "ui/overlay.scm",
            "ui/chooser.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    // MARK: - Constructor shape

    @Test func keyRangeProducesRangeCommandNode() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define n (key-range "1..9" "Space <n>"
                        '("1" "2" "3") (lambda (k) k)))
            """)
        #expect(try engine.evaluate("(range-command? n)") == .true)
        #expect(try engine.evaluate("(command? n)") == .false)
        #expect(try engine.evaluate("(group? n)") == .false)
        #expect(try engine.evaluate("(node-key n)").asString() == "1..9")
        #expect(try engine.evaluate("(node-label n)").asString() == "Space <n>")
        #expect(try engine.evaluate("(length (node-range-keys n))").asInt64() == 3)
    }

    // MARK: - find-child dispatch

    @Test func findChildMatchesAnyKeyInRange() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (register-tree! 'global
              (key-range "1..9" "Space <n>"
                '("1" "2" "3" "4" "5" "6" "7" "8" "9")
                (lambda (k) k)))
            """)
        // Every digit in the range resolves to the same range node.
        for digit in ["1", "5", "9"] {
            let found = try engine.evaluate("""
                (range-command? (find-child (lookup-tree "global") "\(digit)"))
                """)
            #expect(found == .true)
        }
        // A digit outside the range list does not match.
        #expect(try engine.evaluate("""
            (find-child (lookup-tree "global") "0")
            """) == .false)
    }

    @Test func literalKeyWinsOverOverlappingRange() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (register-tree! 'global
              (key-range "1..9" "Space <n>"
                '("1" "2" "3" "4" "5" "6" "7" "8" "9")
                (lambda (k) 'range))
              (key "5" "Special Five" (lambda () 'literal)))
            """)
        // The literal binding for "5" carves a slot out of the range.
        #expect(try engine.evaluate("""
            (command? (find-child (lookup-tree "global") "5"))
            """) == .true)
        #expect(try engine.evaluate("""
            (node-label (find-child (lookup-tree "global") "5"))
            """).asString() == "Special Five")
        // Other digits still resolve to the range.
        #expect(try engine.evaluate("""
            (range-command? (find-child (lookup-tree "global") "3"))
            """) == .true)
    }

    // MARK: - modal-handle-key dispatch

    @Test func modalHandleKeyInvokesActionWithMatchedKey() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define received '())
            (register-tree! 'global
              (key-range "1..9" "Space <n>"
                '("1" "2" "3" "4" "5" "6" "7" "8" "9")
                (lambda (k) (set! received (cons k received)))))
            """)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"3\")")
        #expect(try engine.evaluate("(car received)").asString() == "3")
        // Transient: after firing a leaf the modal exits.
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func unmatchedKeyDoesNotFireRange() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define received '())
            (register-tree! 'global
              (key-range "1..9" "Space <n>"
                '("1" "2" "3") (lambda (k) (set! received (cons k received)))))
            """)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"9\")")
        #expect(try engine.evaluate("(length received)").asInt64() == 0)
    }

    // MARK: - keys (3-arg surface form)

    @Test func keysProducesRangeForContiguousDigits() throws {
        let engine = try loadStack()
        // Contiguous digit run, not ending at "9" → "<first>..<last>".
        try engine.evaluate("""
            (define n (keys '("1" "2" "3") "Goto Space <n>"
                        (lambda (k i ks) k)))
            """)
        #expect(try engine.evaluate("(range-command? n)") == .true)
        #expect(try engine.evaluate("(node-key n)").asString() == "1..3")
        #expect(try engine.evaluate("(node-label n)").asString() == "Goto Space <n>")
        #expect(try engine.evaluate("(length (node-range-keys n))").asInt64() == 3)
    }

    @Test func keysOpenEndedForDigitRangeEndingAtNine() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define n (keys '("1" "2" "3" "4" "5" "6" "7" "8" "9") "Space"
                        (lambda (k i ks) k)))
            """)
        #expect(try engine.evaluate("(node-key n)").asString() == "1..")
    }

    @Test func keysContiguousLettersRenderAsRange() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define n (keys '("a" "b" "c") "Letters"
                        (lambda (k i ks) k)))
            """)
        #expect(try engine.evaluate("(node-key n)").asString() == "a..c")
    }

    @Test func keysNonContiguousRendersAsSlashJoined() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define n (keys '("a" "c" "e") "Skip"
                        (lambda (k i ks) k)))
            """)
        #expect(try engine.evaluate("(node-key n)").asString() == "a/c/e")
    }

    @Test func keysExpandsDotDotShorthand() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define n (keys '("a" .. "e") "Letters"
                        (lambda (k i ks) k)))
            """)
        #expect(try engine.evaluate("(length (node-range-keys n))").asInt64() == 5)
        #expect(try engine.evaluate("(car (node-range-keys n))").asString() == "a")
        #expect(try engine.evaluate("(node-key n)").asString() == "a..e")
    }

    @Test func keysExpandsTrailingDotDotForDigit() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define n (keys '("1" ..) "Space"
                        (lambda (k i ks) k)))
            """)
        #expect(try engine.evaluate("(length (node-range-keys n))").asInt64() == 9)
        #expect(try engine.evaluate("(car (node-range-keys n))").asString() == "1")
        #expect(try engine.evaluate("(node-key n)").asString() == "1..")
    }

    @Test func keysActionReceivesKeyIndexAndKeylist() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define received #f)
            (register-tree! 'global
              (keys '("1" "2" "3" "4" "5") "Space <n>"
                (lambda (k i ks)
                  (set! received (list k i (length ks))))))
            """)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"4\")")
        #expect(try engine.evaluate("(car received)").asString() == "4")
        #expect(try engine.evaluate("(cadr received)").asInt64() == 3)
        #expect(try engine.evaluate("(caddr received)").asInt64() == 5)
    }

    @Test func keysAcceptsExplicitDisplayKey() throws {
        let engine = try loadStack()
        try engine.evaluate("""
            (define n (keys '("1" "2" "3") "Space <n>"
                        (lambda (k i ks) k)
                        'display-key "1..3"))
            """)
        #expect(try engine.evaluate("(node-key n)").asString() == "1..3")
    }

    // MARK: - Overlay rendering

    @Test func overlayRendersRangeAsSingleEntry() throws {
        let engine = try loadStack()
        // Use a bare (group …) so the test exercises the default list renderer
        // directly.
        try engine.evaluate("""
            (define test-node (group "g" "G"
              (key-range "1..9" "Space <n>"
                '("1" "2" "3" "4" "5" "6" "7" "8" "9")
                (lambda (k) 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html test-node '("Global") '())
            """).asString()
        // The display-key appears literally as a single key cell.
        #expect(html.contains("1..9"))
        // The label is shown as-is, with <n> escaped (not a group ellipsis).
        #expect(html.contains("Space &lt;n&gt;"))
        // Only one entry was produced — the count of <li class="overlay-entry">
        // markers in the rendered body equals 1 even though nine keys are
        // bound. We scope to <body>…</body> so the literal `<li …>` string
        // bundled inside the inlined overlay.js doesn't get counted.
        let body = html.range(of: "<body>").map {
            String(html[$0.upperBound ..< html.range(of: "</body>")!.lowerBound])
        } ?? ""
        let liCount = body.components(separatedBy: "<li class=\"overlay-entry\"").count - 1
        #expect(liCount == 1)
    }
}
