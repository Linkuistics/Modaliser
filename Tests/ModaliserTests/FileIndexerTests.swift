import Testing
import Foundation
@testable import Modaliser

@Suite("FileIndexer")
struct FileIndexerTests {

    // MARK: - Default exclusions

    @Test func defaultExclusionsContainCommonNoiseDirs() {
        let exclusions = FileIndexer.defaultExclusions
        #expect(exclusions.contains("Library"))
        #expect(exclusions.contains(".Trash"))
        #expect(exclusions.contains(".git"))
        #expect(exclusions.contains(".cache"))
        #expect(exclusions.contains(".build"))
    }

    // MARK: - Initial state

    @Test func initialStateHasNoChoicesAndIsNotIndexing() {
        let indexer = FileIndexer()
        #expect(indexer.choices.isEmpty)
        #expect(!indexer.isIndexing)
    }

    // MARK: - Integration (requires fd)

    @Test func indexProducesChoicesFromSourcesDirectory() async throws {
        let indexer = FileIndexer()

        // Index the project's own Sources directory (small, guaranteed to exist)
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .path

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.main.async {
                indexer.index(roots: [sourcesDir]) { result in
                    continuation.resume(returning: result)
                }
            }
        }

        guard success else {
            // fd not installed — skip gracefully
            return
        }

        #expect(!indexer.choices.isEmpty)

        // text should be just the filename, subText should be the full path
        let firstChoice = indexer.choices[0]
        #expect(!firstChoice.text.contains("/"))
        #expect(firstChoice.subText != nil)
        #expect(firstChoice.subText!.contains("/"))
    }
}
