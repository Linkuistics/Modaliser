import Testing
@testable import Modaliser

@Suite("WindowManipulator — window resolution")
struct WindowManipulatorTests {

    // MARK: - resolveWindowIndex(candidates:windowId:title:)
    // Reproduces the reported bug: two same-app windows sharing a title must
    // still resolve to the one the caller actually chose, via windowId.

    @Test func idMatchWinsOverFirstSameTitleCandidate() {
        let candidates = [
            WindowManipulator.WindowCandidate(windowId: 100, title: "iTerm2"),
            WindowManipulator.WindowCandidate(windowId: 200, title: "iTerm2"),
        ]
        // Ask for the *second* same-titled window by id — must not settle
        // for the first title match.
        let idx = WindowManipulator.resolveWindowIndex(
            candidates: candidates, windowId: 200, title: "iTerm2")
        #expect(idx == 1)
    }

    @Test func zeroIdFallsBackToTitleMatch() {
        let candidates = [
            WindowManipulator.WindowCandidate(windowId: 100, title: "Alpha"),
            WindowManipulator.WindowCandidate(windowId: 200, title: "Beta"),
        ]
        let idx = WindowManipulator.resolveWindowIndex(
            candidates: candidates, windowId: 0, title: "Beta")
        #expect(idx == 1)
    }

    @Test func unresolvedIdFallsBackToTitleMatch() {
        // windowId doesn't match any candidate (the AX id SPI is occasionally
        // unreliable) — still resolve via title rather than giving up.
        let candidates = [
            WindowManipulator.WindowCandidate(windowId: 100, title: "Alpha"),
            WindowManipulator.WindowCandidate(windowId: 200, title: "Beta"),
        ]
        let idx = WindowManipulator.resolveWindowIndex(
            candidates: candidates, windowId: 999, title: "Beta")
        #expect(idx == 1)
    }

    @Test func noMatchReturnsNil() {
        let candidates = [
            WindowManipulator.WindowCandidate(windowId: 100, title: "Alpha"),
        ]
        let idx = WindowManipulator.resolveWindowIndex(
            candidates: candidates, windowId: 999, title: "Nonexistent")
        #expect(idx == nil)
    }

    @Test func emptyCandidatesReturnsNil() {
        let idx = WindowManipulator.resolveWindowIndex(
            candidates: [], windowId: 100, title: "Alpha")
        #expect(idx == nil)
    }
}
