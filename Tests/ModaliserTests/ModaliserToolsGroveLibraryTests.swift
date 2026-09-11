import Testing

@testable import Modaliser

/// Tests for `(modaliser tools grove)` — the one-question wrapper over
/// grove's `grove-llm pick` (grove-leaf-reveal-k3).
///
/// Everything runs through **one seam**: `current-shell-runner`
/// (ADR-0023). No `grove-llm` binary is resolved and no grove tree is
/// walked — the canned runner both answers the query and records the
/// exact command that would have been spawned.
///
/// The command assertions are the point of the suite rather than
/// belt-and-braces. `pick` takes no directory argument: it walks up
/// from the *current directory*, so the `cd` in front of it is the
/// whole way the worktree is named. Get that wrong and the operation
/// still succeeds — it just confidently answers about the wrong grove,
/// which is the one failure this library exists to avoid.
@Suite("(modaliser tools grove) library")
struct ModaliserToolsGroveLibraryTests {

    @Test func taskPathsAreScopedAndFollowTheCurrentFilenameGrammar() throws {
        let engine = try engineWithRecordingRunner()
        for path in [
            "/p/.grove/01-impl--task-k1.md",
            "/p/.grove/nested/02-DONE-review-impl--task-name-k23.md",
            "/p/.grove/03-ABANDONED-integrate-review-design--task-k4.md",
            "/p/.grove/04-combine-research--task-k5.md",
        ] {
            #expect(try engine.evaluate("(grove:task-path? \(literal(path)) \(literal("/p/")))") == .true)
        }
        for path in [
            "/p-other/.grove/01-impl--task-k1.md", "/other/p/.grove/01-impl--task-k1.md",
            "/p/nested/.grove/01-impl--task-k1.md", "/p/.grove-other/01-impl--task-k1.md",
            "/p/.grove/../01-impl--task-k1.md", "/p/.grove/BRIEF.md", "/p/.grove/notes.md",
            "/p/.grove/01-impl-task-k1.md", "/p/.grove/01-unknown--task-k1.md",
            "/p/.grove/1-impl--task-k1.md", "/p/.grove/01-impl--task.md",
            "/p/.grove/01-impl--task-k.md", "/p/.grove/01-impl--task-k1.md.bak",
            "/p/.grove/01-impl--task-k1x.md", "p/.grove/01-impl--task-k1.md",
        ] {
            #expect(try engine.evaluate("(grove:task-path? \(literal(path)) \(literal("/p")))") == .false)
        }
        #expect(try engine.evaluate(#"(grove:task-path? #f "/p")"#) == .false)
        #expect(try engine.evaluate(#"(grove:task-path? "/p/.grove/01-impl--task-k1.md" #f)"#) == .false)
        #expect(try engine.evaluate("(null? seen)") == .true)
    }

    /// An engine with the library imported and a recording runner
    /// installed.
    ///
    /// Ordering is deliberate, exactly as in the paneru suite: the
    /// import comes first so `(modaliser terminal)` derives
    /// `modaliser-tool-path` with **no** runner installed and degrades
    /// to the ADR-0017 floor. Installing the runner first would feed
    /// the login-shell derivation this canned value and bake it into
    /// the preamble every assertion below reads back.
    private func engineWithRecordingRunner(answer: String = "") throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (prefix (modaliser tools grove) grove:)
                  (modaliser shell)
                  (only (modaliser util) string-contains?))
        """)
        try engine.evaluate("""
          (define seen '())
          (current-shell-runner
            (lambda (cmd) (set! seen (cons cmd seen)) \(literal(answer))))
        """)
        return engine
    }

    /// A Swift string as *Scheme source*. The interesting answers are
    /// newline-terminated — a real CLI prints one — and LispKit's
    /// reader rejects a raw newline inside a literal.
    private func literal(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: - Surface

    @Test func exportsResolveAsProcedures() throws {
        let engine = try engineWithRecordingRunner()
        #expect(try engine.evaluate("(procedure? grove:live-leaf)") == .true)
        #expect(try engine.evaluate("(procedure? grove:live-leaf-command)") == .true)
        #expect(try engine.evaluate("(procedure? grove:leaf-of-output)") == .true)
    }

    // MARK: - The command

    /// The shape in full: the PATH preamble, a guarded `cd` into the
    /// worktree, and `pick` — joined by `&&`, not `;`.
    @Test func theCommandCdsIntoTheWorktreeThenPicks() throws {
        let engine = try engineWithRecordingRunner()
        try engine.evaluate("""
          (define cmd (grove:live-leaf-command "/Users/me/Development/thing"))
        """)
        #expect(try engine.evaluate(#"(string-contains? cmd "export PATH=")"#) == .true)
        #expect(try engine.evaluate("""
          (string-contains? cmd
            "cd '/Users/me/Development/thing' 2>/dev/null && grove-llm pick 2>/dev/null")
        """) == .true)
    }

    /// The command clears `GROVE_SIGNAL_FILE` first. `pick` refuses when
    /// the tree it resolves is not the one the CALLING SESSION belongs
    /// to, and that variable is how it identifies the session — so a
    /// Modaliser launched from a shell that has one would report "no
    /// leaf" for every worktree but that session's own, which reads as
    /// a broken lookup rather than as a guard. Clearing it answers the
    /// guard truthfully: this invocation is not part of any session.
    @Test func theCommandClearsAnyInheritedGroveSession() throws {
        let engine = try engineWithRecordingRunner()
        #expect(try engine.evaluate("""
          (string-contains? (grove:live-leaf-command "/Users/me/Development/thing")
                            "unset GROVE_SIGNAL_FILE; cd '")
        """) == .true)
    }

    /// `&&` rather than `;`, and this is the assertion that earns its
    /// keep. With `;` a failed `cd` — a worktree that has been moved or
    /// deleted since VSCode last recorded it, which is ordinary — would
    /// leave the CLI running in whatever directory Modaliser itself was
    /// launched from, and `pick` would answer about THAT grove. A wrong
    /// leaf opening silently is far worse than no leaf opening.
    @Test func aFailedCdShortCircuitsRatherThanAskingTheWrongTree() throws {
        let engine = try engineWithRecordingRunner()
        #expect(try engine.evaluate("""
          (let ((cmd (grove:live-leaf-command "/gone")))
            (and (string-contains? cmd "&& grove-llm pick")
                 (not (string-contains? cmd "; grove-llm pick"))))
        """) == .true)
    }

    /// A worktree path is arbitrary text out of an editor's stored
    /// state: it may hold a space, and it may hold a quote. An
    /// unescaped quote here is a command-injection site, not merely a
    /// broken lookup.
    ///
    /// Asserted on the ESCAPE rather than on the absence of the
    /// payload: the payload text is still *in* the command —
    /// harmlessly, inside a quoted word — so "does not contain it"
    /// would be a test that passes for the wrong reason. What matters
    /// is that every `'` arrives as the `'\''` idiom.
    @Test func theWorktreePathIsShellQuoted() throws {
        let engine = try engineWithRecordingRunner()
        #expect(try engine.evaluate("""
          (string-contains? (grove:live-leaf-command "/Users/me/My Work/thing")
                            "cd '/Users/me/My Work/thing'")
        """) == .true)
        #expect(try engine.evaluate(#"""
          (string-contains?
            (grove:live-leaf-command "/tmp/it's; touch /tmp/pwned; ")
            "cd '/tmp/it'\\''s; touch /tmp/pwned; '")
        """#) == .true)
    }

    // MARK: - Reading the answer

    /// Success: one absolute path and a newline.
    @Test func aLeafPathIsTrimmedAndReturned() throws {
        let engine = try engineWithRecordingRunner()
        #expect(try engine.evaluate("""
          (equal? (grove:leaf-of-output "/Users/me/p/.grove/03-impl--thing-k7.md\\n")
                  "/Users/me/p/.grove/03-impl--thing-k7.md")
        """) == .true)
    }

    /// Every negative outcome arrives the same way — as empty stdout —
    /// and so has one code path. Established by running the CLI: a
    /// directory that is not a grove exits 1, a grove with no live
    /// leaves exits 0, a directory that is not a VCS working tree exits
    /// 1, and all three print their diagnostic on **stderr**, which the
    /// command discards. An uninstalled shell runner (every engine
    /// `swift test` builds) lands here too.
    @Test func everyKindOfMissReadsAsFalse() throws {
        let engine = try engineWithRecordingRunner()
        #expect(try engine.evaluate(#"(grove:leaf-of-output "")"#) == .false)
        #expect(try engine.evaluate(#"(grove:leaf-of-output "\n")"#) == .false)
        #expect(try engine.evaluate(#"(grove:leaf-of-output "   \n  ")"#) == .false)
    }

    /// Only the first line. `pick` prints exactly one, but a shell that
    /// leaked a warning onto stdout would otherwise produce a two-line
    /// "path" that no `code` invocation could open — a degradation to a
    /// wrong-but-single path is recoverable, a degradation to garbage
    /// is not.
    @Test func onlyTheFirstLineIsTaken() throws {
        let engine = try engineWithRecordingRunner()
        #expect(try engine.evaluate("""
          (equal? (grove:leaf-of-output "/a/leaf.md\\nsomething else\\n") "/a/leaf.md")
        """) == .true)
    }

    // MARK: - End to end, through the seam

    @Test func liveLeafSpawnsOnceAndReturnsThePath() throws {
        let engine = try engineWithRecordingRunner(
            answer: "/Users/me/Development/thing/.grove/03-impl--thing-k7.md\n")
        #expect(try engine.evaluate("""
          (equal? (grove:live-leaf "/Users/me/Development/thing")
                  "/Users/me/Development/thing/.grove/03-impl--thing-k7.md")
        """) == .true)
        #expect(try engine.evaluate("(= (length seen) 1)") == .true)
        #expect(try engine.evaluate("""
          (string-contains? (car seen) "cd '/Users/me/Development/thing' 2>/dev/null")
        """) == .true)
    }

    /// A worktree that could not be resolved is #f **without
    /// spawning**. The caller upstream is "which folder is this window
    /// rooted at", which has its own ordinary ways of failing, and
    /// `cd ''` — which succeeds, landing in the current directory — is
    /// the shape that would turn that failure into the wrong grove's
    /// leaf rather than into no leaf.
    @Test func anUnresolvedWorktreeNeverSpawns() throws {
        let engine = try engineWithRecordingRunner(answer: "/wrong/leaf.md\n")
        #expect(try engine.evaluate(#"(grove:live-leaf "")"#) == .false)
        #expect(try engine.evaluate("(grove:live-leaf #f)") == .false)
        #expect(try engine.evaluate("(null? seen)") == .true)
    }

    /// With no runner installed — every engine `swift test` builds
    /// unless it says otherwise — the seam answers "" and the library
    /// answers #f. So a bare engine reaches no `grove-llm`, and a
    /// screen composed against this library degrades to "no leaf"
    /// rather than to an error.
    @Test func aBareEngineReachesNothing() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (prefix (modaliser tools grove) grove:))")
        #expect(try engine.evaluate(#"(grove:live-leaf "/Users/me/Development/thing")"#) == .false)
    }
}
