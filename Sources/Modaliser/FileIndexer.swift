import Foundation

/// Indexes files using the `fd` command-line tool for file-based selectors.
///
/// Runs `fd` with sensible defaults (hidden files, follow symlinks, common exclusions)
/// and caches the result as `ChooserChoice` objects. Indexing runs asynchronously
/// on a background queue. The file list is rebuilt on each call to `index()`.
final class FileIndexer {

    /// GUI apps inherit a minimal PATH; extend it to find Homebrew tools.
    private static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":" + extraPaths
        return env
    }()

    /// Default exclusions for file indexing — common directories that produce
    /// noise in search results or are extremely large.
    static let defaultExclusions = [
        "Library", ".Trash", "Movies", "Music", "Pictures",
        ".cache", ".build", ".git",
    ]

    /// Maximum number of files to index. Prevents runaway memory usage
    /// if file-roots cover a very large directory tree.
    static let maxResults = 100_000

    private(set) var choices: [ChooserChoice] = []
    private(set) var isIndexing = false

    /// Index files under the given roots using `fd`.
    /// Calls completion on the main thread when done.
    func index(roots: [String], completion: @escaping (Bool) -> Void) {
        isIndexing = true
        let expandedRoots = roots.map { ($0 as NSString).expandingTildeInPath }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var args = [
                "--hidden", "--follow", "--type", "f", "--type", "d",
            ]
            for exclusion in Self.defaultExclusions {
                args.append("--exclude")
                args.append(exclusion)
            }
            args.append(".")
            args.append(contentsOf: expandedRoots)

            let pipe = Pipe()
            let process = Process()
            process.environment = Self.environment
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["fd"] + args
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.split(separator: "\n", omittingEmptySubsequences: true)

                if lines.count > Self.maxResults {
                    NSLog("FileIndexer: %d files found, capping at %d", lines.count, Self.maxResults)
                }

                let choices = lines.prefix(Self.maxResults).map { line -> ChooserChoice in
                    let path = String(line)
                    let name = (path as NSString).lastPathComponent
                    return ChooserChoice(
                        text: name,
                        subText: path,
                        icon: nil,
                        iconType: nil,
                        schemeValue: .makeString(path)
                    )
                }

                DispatchQueue.main.async {
                    self?.choices = choices
                    self?.isIndexing = false
                    completion(true)
                }
            } catch {
                NSLog("FileIndexer: fd failed (is it installed? brew install fd): %@", "\(error)")
                DispatchQueue.main.async {
                    self?.isIndexing = false
                    completion(false)
                }
            }
        }
    }
}
