import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Block-list renderer scaffolding")
struct BlockListRendererTests {

    private func loadOverlay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    @Test func blocksRendererEmitsTypedPayloadWithBlocksArray() throws {
        let engine = try loadOverlay()
        // Two stub block specs in declaration order: 'foo then 'bar.
        try engine.evaluate("""
          (define foo (list (cons 'type 'foo) (cons 'note "F")))
          (define bar (list (cons 'type 'bar) (cons 'note "B")))
          (define grp (group "w" "Win" 'renderer 'blocks 'blocks (list foo bar)
                        (key "x" "X" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("data-renderer=\"blocks\""))
        // Extract data-payload
        guard let payloadStart = html.range(of: "data-payload='") else {
            Issue.record("data-payload absent: \(html)"); return
        }
        let after = html[payloadStart.upperBound...]
        guard let payloadEnd = after.firstIndex(of: "'") else {
            Issue.record("data-payload not terminated"); return
        }
        let payload = String(after[..<payloadEnd])
        #expect(payload.contains("\"type\":\"blocks\""))
        // 'foo' must precede 'bar' in the blocks array (order preserved).
        guard let fooIdx = payload.range(of: "\"type\":\"foo\""),
              let barIdx = payload.range(of: "\"type\":\"bar\"") else {
            Issue.record("block types missing in payload: \(payload)"); return
        }
        #expect(fooIdx.lowerBound < barIdx.lowerBound)
        // Each block's spec fields are emitted
        #expect(payload.contains("\"note\":\"F\""))
        #expect(payload.contains("\"note\":\"B\""))
    }

    @Test func overlayJsExposesBlockRendererRegistry() throws {
        let engine = try loadOverlay()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); return
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        #expect(js.contains("window.overlayBlockRenderers"))
        #expect(js.contains("overlayRenderers.blocks"))
    }

    @Test func blockOnRenderFnFiresWhenPayloadIsBuilt() throws {
        let engine = try loadOverlay()
        // A block spec with an 'on-render-fn that bumps a counter when fired.
        try engine.evaluate("""
          (define counter 0)
          (define stub-block
            (list (cons 'type 'stub)
                  (cons 'on-render-fn (lambda () (set! counter (+ counter 1))))))
          (define grp (group "w" "Win" 'renderer 'blocks 'blocks (list stub-block)))
          ;; Building the JSON payload runs the block's effects.
          (define payload (block-list-payload-json grp))
        """)
        #expect(try engine.evaluate("(>= counter 1)") == .true)
        // The effect MUST NOT appear in the serialized JSON (it's a Scheme
        // procedure, not a value the JS side cares about).
        let payload = try engine.evaluate("payload").asString()
        #expect(!payload.contains("on-render-fn"))
    }
}
