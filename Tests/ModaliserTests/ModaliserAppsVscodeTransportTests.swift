import Foundation
import Testing

@testable import Modaliser

// Unit tests for the companion extension's transport in (modaliser apps
// vscode) — `vscode-parts`, its two seams, and the two gates it puts between
// a reply and a caller (vscode-companion-extension-k12).
//
// Nothing here reaches a socket. `current-vscode-socket-pointer-path`
// defaults to #f, which a bare SchemeEngine() never overrides — only
// root.scm does, and no test runs root.scm — and every transport takes its
// peer as an argument rather than resolving one, so there is no path by which
// this suite could dial a live editor (ADR-0023). The seams below are
// installed canned, exactly as the herdr suites install theirs.
//
// What CANNOT be asserted here, stated so a green run is not mistaken for a
// working panel: every seam asserts the CALL — which bytes went to which peer
// — and none asserts the EFFECT, because the effect is VSCode's. The
// per-kind activation table lives in the extension and is tested in the
// extension's own project (`vscode-extension/test/`), against fakes of the
// two API surfaces it reads.
@Suite("(modaliser apps vscode) companion transport")
struct ModaliserAppsVscodeTransportTests {

    /// A reply in the extension's own shape, captured against the real peer.
    /// The awkward rows are present on purpose: an inert tab kind, a terminal
    /// with no cwd, and two groups. A fixture of nothing but happy rows
    /// leaves decision 1's rules untested.
    private static let partsReply = """
      {"id":"modaliser",
       "result":{"protocol":1,
                 "focused":true,
                 "peer":"/Users/someone/.config/modaliser/vscode/vs-abc.sock",
                 "workspace":"/Users/someone/Project",
                 "terminals":[{"token":1,"name":"zsh","cwd":"/Users/someone/Project","active":true},
                              {"token":2,"name":"build","cwd":null,"active":false}],
                 "editors":[{"token":3,"label":"fsm.sld","path":"/Users/someone/Project/fsm.sld",
                             "active":true,"dirty":false,"group":1},
                            {"token":null,"label":"Release Notes","path":null,
                             "active":false,"dirty":false,"group":2}]}}
      """

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (prefix (modaliser apps vscode) code:))")
        try engine.evaluate("(import (only (modaliser json) json-parse json-ref))")
        return engine
    }

    /// A real pointer file in a temp directory, naming PEER.
    ///
    /// The pointer read is a genuine `read-file-text`, so a test that wants
    /// to get past it has to supply a file — there is no seam between the
    /// parameter and the read, and there should not be: the read IS the
    /// addressing decision (ADR-0027), and a seam over it would leave the one
    /// thing this library does about window identity untested. A temp file
    /// this test wrote itself is inside the process's own world; what
    /// ADR-0023 excludes is reaching the developer's live editor, and no
    /// socket is dialled here at all.
    private func pointerFile(naming peer: String) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-vscode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let pointer = directory.appendingPathComponent("focused")
        try "\(peer)\n".write(to: pointer, atomically: true, encoding: .utf8)
        return pointer.path
    }

    /// Installs a query runner answering REPLY (a JSON string) and a pointer
    /// path, then evaluates BODY. `record` collects the peer/method the
    /// runner was called with.
    @discardableResult
    private func withCannedReply(_ engine: SchemeEngine, _ reply: String) throws -> String {
        try engine.evaluate("(define recorded '())")
        let peer = "/Users/someone/.config/modaliser/vscode/vs-abc.sock"
        let pointer = try pointerFile(naming: peer)
        try engine.evaluate("""
          (code:current-vscode-socket-pointer-path \(schemeString(pointer)))
          """)
        try engine.evaluate("""
          (code:current-vscode-query-runner
            (lambda (peer method params)
              (set! recorded (list peer method params))
              (json-parse \(schemeString(reply)))))
          """)
        return peer
    }

    /// A Scheme string literal for TEXT.
    private func schemeString(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    // ── The surface resolves ────────────────────────────────────────

    @Test func exportsResolveAsProcedures() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("(procedure? code:vscode-parts)") == .true)
        #expect(try engine.evaluate("(procedure? code:vscode-query)") == .true)
        #expect(try engine.evaluate("(procedure? code:vscode-notify)") == .true)
        #expect(try engine.evaluate("(procedure? code:vscode-socket-request)") == .true)
        #expect(try engine.evaluate("(procedure? code:vscode-socket-send)") == .true)
        #expect(
            try engine.evaluate("(procedure? code:vscode-default-socket-pointer-path)") == .true)
        #expect(try engine.evaluate("(= code:vscode-protocol-version 1)") == .true)
    }

    // ── The quarantine (ADR-0023) ───────────────────────────────────

    @Test func thePointerPathIsUnconfiguredUntilTheHostInstallsIt() throws {
        let engine = try loaded()
        // The whole of what keeps this suite off a live editor: no pointer,
        // no peer, and every transport below takes its peer as an argument.
        // root.scm installs the real path; no test runs root.scm.
        #expect(try engine.evaluate("(code:current-vscode-socket-pointer-path)") == .false)
    }

    @Test func vscodePartsAnswersNothingWithNoPointerInstalled() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define dialled #f)
          (code:current-vscode-query-runner
            (lambda (peer method params) (set! dialled #t) #f))
          """)
        #expect(try engine.evaluate("(code:vscode-parts)") == .false)
        // Not merely "returned #f": the runner was never reached at all.
        #expect(try engine.evaluate("dialled") == .false)
    }

    @Test func theDefaultPointerPathIsUnderModalisersConfigRoot() throws {
        let engine = try loaded()
        // The extension hard-codes the same directory. Both halves hard-code
        // it rather than honouring $XDG_CONFIG_HOME, which SchemeEngine does
        // not honour either — one side honouring it would put the two in
        // different directories.
        let path = try engine.evaluate("(code:vscode-default-socket-pointer-path)")
        #expect(path.description.hasSuffix("/.config/modaliser/vscode/focused\""))
    }

    // ── vscode-parts: the happy path ────────────────────────────────

    @Test func vscodePartsReturnsTheResultObject() throws {
        let engine = try loaded()
        try withCannedReply(engine, Self.partsReply)
        // The RESULT, not the envelope: every reason to reject a reply is
        // already spent by the time one comes back, so handing callers the
        // envelope would buy them a `json-ref` each and nothing else.
        #expect(
            try engine.evaluate("""
              (json-ref (code:vscode-parts) "workspace")
              """) == .makeString("/Users/someone/Project"))
        #expect(
            try engine.evaluate("""
              (json-ref (code:vscode-parts) "peer")
              """) == .makeString("/Users/someone/.config/modaliser/vscode/vs-abc.sock"))
    }

    @Test func vscodePartsDialsThePointerWithTheOneQueryMethod() throws {
        let engine = try loaded()
        let peer = try withCannedReply(engine, Self.partsReply)
        _ = try engine.evaluate("(code:vscode-parts)")
        // The peer dialled is the one the POINTER FILE named, trimmed of the
        // newline the extension writes with it.
        #expect(try engine.evaluate("(car recorded)") == .makeString(peer))
        #expect(try engine.evaluate("(cadr recorded)") == .makeString("parts"))
        // Params is the empty OBJECT, which json-write renders as `{}`.
        #expect(try engine.evaluate("(null? (caddr recorded))") == .true)
    }

    @Test func vscodePartsCarriesBothListingsInOneReply() throws {
        let engine = try loaded()
        try withCannedReply(engine, Self.partsReply)
        try engine.evaluate("(define parts (code:vscode-parts))")
        // One round-trip answers both panels. That is what makes the
        // un-memoised two-panel shape a bounded cost rather than a doubled
        // protocol.
        #expect(try engine.evaluate("(vector-length (json-ref parts \"terminals\"))") == .fixnum(2))
        #expect(try engine.evaluate("(vector-length (json-ref parts \"editors\"))") == .fixnum(2))
    }

    // ── vscode-parts: the three ways to get #f ──────────────────────

    @Test func vscodePartsDiscardsAReplyFromAnUnfocusedWindow() throws {
        let engine = try loaded()
        try withCannedReply(
            engine, Self.partsReply.replacingOccurrences(of: "\"focused\":true", with: "\"focused\":false"))
        // The one fixture whose correct handling is to produce NOTHING, and
        // therefore the one most likely to be left out. A stale pointer — a
        // window that closed, a race — must yield an empty listing rather
        // than a neighbouring project's terminals.
        #expect(try engine.evaluate("(code:vscode-parts)") == .false)
    }

    @Test func vscodePartsRefusesAProtocolItDoesNotUnderstand() throws {
        let engine = try loaded()
        try withCannedReply(
            engine, Self.partsReply.replacingOccurrences(of: "\"protocol\":1", with: "\"protocol\":2"))
        // Modaliser and the extension are installed separately and can skew.
        // Interpreting fields whose meaning is not agreed is how a skew
        // becomes a wrong jump instead of an empty panel.
        #expect(try engine.evaluate("(code:vscode-parts)") == .false)
    }

    @Test func vscodePartsRefusesAReplyWithNoProtocolAtAll() throws {
        let engine = try loaded()
        try withCannedReply(
            engine, Self.partsReply.replacingOccurrences(of: "\"protocol\":1,", with: ""))
        #expect(try engine.evaluate("(code:vscode-parts)") == .false)
    }

    @Test func vscodePartsAnswersNothingForAnUnreachablePeer() throws {
        let engine = try loaded()
        let pointer = try pointerFile(naming: "/tmp/no-such-peer.sock")
        try engine.evaluate("""
          (code:current-vscode-socket-pointer-path \(schemeString(pointer)))
          (code:current-vscode-query-runner (lambda (peer method params) #f))
          """)
        // #f, never a raise: a leader press must not raise.
        #expect(try engine.evaluate("(code:vscode-parts)") == .false)
    }

    @Test func vscodePartsAnswersNothingForAnErrorEnvelope() throws {
        let engine = try loaded()
        try withCannedReply(engine, #"{"id":"modaliser","error":{"message":"nope"}}"#)
        // An error envelope has no `result`, and `json-ref` is total — so it
        // degrades to the same #f every other miss produces.
        #expect(try engine.evaluate("(code:vscode-parts)") == .false)
    }

    // ── The notify seam ─────────────────────────────────────────────

    @Test func vscodeNotifyGoesToThePeerItIsGivenAndNoOther() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define sent '())
          (code:current-vscode-notify-runner
            (lambda (peer method params) (set! sent (cons (list peer method params) sent)) #t))
          (code:current-vscode-socket-pointer-path "/tmp/a-pointer-nothing-reads")
          (code:vscode-notify "/tmp/the-peer-that-answered.sock" "focus-editor"
                              (list (cons "token" 3)))
          """)
        // The whole of ADR-0027 in one assertion: the address came out of the
        // read, not out of a pointer consulted a second time. Every window's
        // counter starts at the same place, so a token delivered to the wrong
        // peer RESOLVES — to a different tab.
        #expect(
            try engine.evaluate("(car (car sent))")
                == .makeString("/tmp/the-peer-that-answered.sock"))
        #expect(try engine.evaluate("(cadr (car sent))") == .makeString("focus-editor"))
        #expect(try engine.evaluate("(cdr (assoc \"token\" (caddr (car sent))))") == .fixnum(3))
    }

    @Test func theTwoSeamsAreSeparate() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define reads 0)
          (define writes 0)
          (code:current-vscode-query-runner (lambda (p m x) (set! reads (+ reads 1)) #f))
          (code:current-vscode-notify-runner (lambda (p m x) (set! writes (+ writes 1)) #t))
          (code:vscode-notify "/tmp/peer.sock" "focus-terminal" (list (cons "token" 1)))
          """)
        // Two seams rather than one, for the reason (modaliser unix-socket)
        // has two primitives: a deliberately abandoned reply must not be
        // indistinguishable from a timeout.
        #expect(try engine.evaluate("reads") == .fixnum(0))
        #expect(try engine.evaluate("writes") == .fixnum(1))
    }

    // ── The real transport, over a real socket ─────────────────────
    //
    // The two tests above the seams exercise canned runners; these two
    // exercise `unix-socket-request` / `unix-socket-send` themselves against a
    // throwaway responder — the same harness the herdr transport's tests use,
    // and the reason `current-vscode-socket-pointer-path` is a parameter
    // rather than a constant. Nothing here is a VSCode: the responder is a few
    // dozen lines of `sockaddr_un` in this suite.

    @Test func theRealRequestPutsTheAgreedEnvelopeOnTheWire() throws {
        let responder = try LineResponderSocket(
            behaviour: .canned(#"{"id":"modaliser","result":{"protocol":1,"focused":true}}"#))
        defer { responder.stop() }

        let engine = try loaded()
        let protocolVersion = try engine.evaluate("""
          (json-ref (json-ref (code:vscode-socket-request
                                \(schemeString(responder.path)) "parts" '())
                              "result")
                    "protocol")
          """)
        #expect(protocolVersion == .fixnum(1))
        // The request format is a contract with a peer written in another
        // language, so the exact bytes are worth pinning.
        #expect(
            responder.lastRequest
                == #"{"id":"modaliser","method":"parts","params":{}}"#)
    }

    @Test func theRealNotifyPutsTheTokenOnTheWireAndReadsNothingBack() throws {
        // A responder that DOES reply, so the assertion is that the send half
        // returns without consuming a reply that was there for the taking —
        // not merely that it survives a peer with nothing to say.
        let responder = try LineResponderSocket(
            behaviour: .canned(#"{"id":"modaliser","result":"ignored"}"#))
        defer { responder.stop() }

        let engine = try loaded()
        let started = Date()
        #expect(
            try engine.evaluate("""
              (code:vscode-socket-send \(schemeString(responder.path))
                                       "focus-editor" '(("token" . 3)))
              """) == .true)
        // The point of the send half: a peer that answers nothing costs the
        // connect and no more. Waiting would spend the whole 200 ms timeout
        // on every action as a matter of routine (ADR-0014's stalled tap).
        #expect(Date().timeIntervalSince(started) < 0.1)

        // And the bytes still arrive. Not waiting for the reply is exactly
        // what makes this a poll rather than a read: the call returned before
        // the peer had necessarily been scheduled, which is the property
        // under test.
        let deadline = Date().addingTimeInterval(2)
        while responder.lastRequest == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(
            responder.lastRequest
                == #"{"id":"modaliser","method":"focus-editor","params":{"token":3}}"#)
    }

    @Test func theRealRequestGivesUpRatherThanBlockingOnAWedgedPeer() throws {
        let responder = try LineResponderSocket(behaviour: .silent)
        defer { responder.stop() }

        let engine = try loaded()
        let started = Date()
        #expect(
            try engine.evaluate("""
              (code:vscode-socket-request \(schemeString(responder.path)) "parts" '())
              """) == .false)
        let elapsed = Date().timeIntervalSince(started)
        // 200 ms, not herdr's 1000: a screen reads once per panel and a
        // blocked eval thread is a blocked keyboard tap. The bound is what
        // makes the un-memoised two-panel shape safe; a healthy-path
        // measurement could never have established it.
        #expect(elapsed >= 0.2)
        #expect(elapsed < 0.6)
    }

    @Test func theRealTransportsRefuseANonStringPeer() throws {
        let engine = try loaded()
        // A target whose peer never arrived is a #f, and reaching the
        // transport with one must be a logged non-event rather than a raise.
        #expect(try engine.evaluate("(code:vscode-socket-request #f \"parts\" '())") == .false)
        #expect(try engine.evaluate("(code:vscode-socket-send #f \"focus-editor\" '())") == .false)
    }
}
