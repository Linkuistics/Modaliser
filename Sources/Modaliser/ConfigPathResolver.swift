import Foundation

/// Resolves the path to config.scm by searching standard locations.
/// Search order: user config directory first, then working directory (for development).
struct ConfigPathResolver {
    private let fileManager: FileManager
    private let homeDirectory: String

    init(fileManager: FileManager = .default, homeDirectory: String = NSHomeDirectory()) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    /// Find the first existing config.scm in the search locations.
    func resolve() -> String? {
        for path in searchPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private var searchPaths: [String] {
        [
            homeDirectory + "/.config/modaliser/config.scm",
            fileManager.currentDirectoryPath + "/config.scm",
        ]
    }
}
