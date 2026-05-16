import Foundation
import LispKit

/// Locate LispKit's bundled R7RS+SRFI Libraries directory for use under
/// `swift test`. Returns nil if not found — under the installed .app build
/// LispKit's own Bundle(identifier:) lookup succeeds and this fallback is
/// unnecessary.
///
/// Under `swift test` the process is `swiftpm-testing-helper` so
/// `arguments[0]` does not point into the project tree. Instead we walk
/// from the current working directory (which `swift test` sets to the
/// package root) and from the executable location as a secondary strategy.
private func locateLispKitLibrariesFallback() -> String? {
    let suffix = ".build/checkouts/swift-lispkit/Sources/LispKit/Resources/Libraries"
    // Primary: walk up from current working directory.
    // `swift test` sets CWD to the package root, so the checkout is
    // directly at <cwd>/<suffix>.
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .resolvingSymlinksInPath()
    for _ in 0..<8 {
        let candidate = dir.appendingPathComponent(suffix).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break } // not found under CWD tree; try arguments[0] below
        dir = parent
    }
    // Secondary: walk up from the executable (useful for `swift build` runs
    // and any context where CWD differs from the package root).
    dir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
    for _ in 0..<8 {
        let candidate = dir.appendingPathComponent(suffix).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { return nil }
        dir = parent
    }
    return nil
}

/// Wraps a LispKit context for evaluating Scheme code.
/// Provides the bridge between Swift and the Scheme configuration layer.
final class SchemeEngine {
    let context: LispKitContext

    /// The resolved path to the Scheme directory, if found.
    private(set) var schemeDirectoryPath: String?

    init(userConfigDir: String? = nil) throws {
        let delegate = ModaliserContextDelegate()
        context = LispKitContext(
            delegate: delegate,
            implementationName: "Modaliser",
            implementationVersion: "0.1",
            commandLineArguments: [],
            includeInternalResources: true,
            includeDocumentPath: nil
        )
        try context.environment.import(BaseLibrary.name)
        // Import standard libraries needed by Scheme files
        try context.environment.import(ListLibrary.name)
        try context.environment.import(HashTableLibrary.name)
        try context.environment.import(StringLibrary.name)
        try context.environment.import(PortLibrary.name)
        try context.environment.import(SystemLibrary.name)
        try context.environment.import(MathLibrary.name)
        try context.environment.import(BytevectorLibrary.name)

        // Resolve and register the Scheme directory as a search path
        schemeDirectoryPath = SchemeEngine.resolveSchemeDirectory()
        if let schemePath = schemeDirectoryPath {
            _ = context.fileHandler.addSearchPath(schemePath)
            try evaluate("(define *scheme-directory* \"\(schemePath)\")")
            // Prepend the bundled Modaliser stdlib root so (import (modaliser …))
            // resolves to files under <scheme>/lib/. Auto-added LispKit
            // R7RS+SRFI root remains last on the list.
            let bundledLibRoot = (schemePath as NSString).appendingPathComponent("lib")
            _ = context.fileHandler.prependLibrarySearchPath(bundledLibRoot)
            NSLog("SchemeEngine: Scheme directory at %@", schemePath)
        }

        // Prepend the user-config root LAST, so it ends up FIRST on the
        // library search path — user libraries shadow bundled ones.
        // Missing path is silently skipped by prependLibrarySearchPath.
        let resolvedUserConfigDir = userConfigDir
            ?? NSString(string: "~/.config/modaliser").expandingTildeInPath
        _ = context.fileHandler.prependLibrarySearchPath(resolvedUserConfigDir)

        // Fallback: under `swift test` LispKit's own Bundle(identifier:)
        // lookup is nil, so the bundled R7RS+SRFI Libraries/ directory
        // never gets added to the library search path. Locate it via the
        // SPM checkout and append it (lowest precedence so a real LispKit
        // path or user override stays in front). No-op in .app builds
        // where the bundle resolves.
        if let lispKitLibs = locateLispKitLibrariesFallback() {
            _ = context.fileHandler.addLibrarySearchPath(lispKitLibs)
        }

        // Register primitive libraries
        try context.libraries.register(libraryType: LifecycleLibrary.self)
        try context.environment.import(LifecycleLibrary.name)
        try context.libraries.register(libraryType: LibraryPathLibrary.self)
        try context.environment.import(LibraryPathLibrary.name)
        try context.libraries.register(libraryType: KeyboardLibrary.self)
        try context.environment.import(KeyboardLibrary.name)
        try context.libraries.register(libraryType: WebViewLibrary.self)
        try context.environment.import(WebViewLibrary.name)
        // Register native system libraries
        try context.libraries.register(libraryType: PasteboardLibrary.self)
        try context.environment.import(PasteboardLibrary.name)
        try context.libraries.register(libraryType: ShellLibrary.self)
        try context.environment.import(ShellLibrary.name)
        try context.libraries.register(libraryType: AppLibrary.self)
        try context.environment.import(AppLibrary.name)
        try context.libraries.register(libraryType: WindowLibrary.self)
        try context.environment.import(WindowLibrary.name)
        try context.libraries.register(libraryType: InputLibrary.self)
        try context.environment.import(InputLibrary.name)
        try context.libraries.register(libraryType: FuzzyMatchLibrary.self)
        try context.environment.import(FuzzyMatchLibrary.name)
        try context.libraries.register(libraryType: ClipboardHistoryLibrary.self)
        try context.environment.import(ClipboardHistoryLibrary.name)
        try context.libraries.register(libraryType: HttpLibrary.self)
        try context.environment.import(HttpLibrary.name)
        try context.libraries.register(libraryType: HintsLibrary.self)
        try context.environment.import(HintsLibrary.name)
        try context.libraries.register(libraryType: AccessibilityLibrary.self)
        try context.environment.import(AccessibilityLibrary.name)
    }

    /// Evaluate a string of Scheme code and return the result.
    @discardableResult
    func evaluate(_ code: String) throws -> Expr {
        let result = context.evaluator.execute { machine in
            try machine.eval(
                str: code,
                sourceId: SourceManager.consoleSourceId,
                in: self.context.global
            )
        }
        if case .error(let err) = result {
            throw err
        }
        return result
    }

    /// Load and evaluate a Scheme file.
    func evaluateFile(_ path: String) throws {
        let result = context.evaluator.execute { machine in
            try machine.eval(file: path, in: self.context.global)
        }
        if case .error(let err) = result {
            throw err
        }
    }

    /// Load the root Scheme file which bootstraps the entire application.
    /// root.scm uses (load-module path) to load all other modules.
    func loadRootSchemeFile() throws {
        guard let schemePath = schemeDirectoryPath else {
            NSLog("SchemeEngine: No Scheme directory found — skipping root load")
            return
        }

        let rootPath = (schemePath as NSString).appendingPathComponent("root.scm")
        guard FileManager.default.fileExists(atPath: rootPath) else {
            NSLog("SchemeEngine: root.scm not found at %@", rootPath)
            return
        }

        try evaluateFile(rootPath)
        NSLog("SchemeEngine: loaded root.scm")
    }

    // MARK: - Scheme directory resolution

    /// Resolve the path to the Scheme directory.
    /// Checks in order:
    /// 1. SPM resource bundle (Bundle.module for executables with .copy resources)
    /// 2. Relative to executable (for swift build development)
    /// 3. Relative to working directory (fallback)
    private static func resolveSchemeDirectory() -> String? {
        // 1. Check Bundle.main for .app bundles or SPM resource bundles
        if let resourceURL = Bundle.main.resourceURL {
            let bundlePath = resourceURL.appendingPathComponent("Modaliser_Modaliser.bundle/Scheme").path
            if FileManager.default.fileExists(atPath: bundlePath) {
                return bundlePath
            }
            let directPath = resourceURL.appendingPathComponent("Scheme").path
            if FileManager.default.fileExists(atPath: directPath) {
                return directPath
            }
        }

        // 2. Relative to executable — for `swift build`, binary is at .build/debug/Modaliser
        //    and Scheme files are at Sources/Modaliser/Scheme/
        let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        let execDir = executableURL.deletingLastPathComponent()

        // Walk up from .build/debug/ to project root
        let projectRoot = execDir.deletingLastPathComponent().deletingLastPathComponent()
        let devPath = projectRoot.appendingPathComponent("Sources/Modaliser/Scheme").path
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        // 3. Relative to working directory
        let cwdPath = FileManager.default.currentDirectoryPath + "/Sources/Modaliser/Scheme"
        if FileManager.default.fileExists(atPath: cwdPath) {
            return cwdPath
        }

        return nil
    }
}

/// Minimal context delegate for Modaliser — routes console output to NSLog.
final class ModaliserContextDelegate: ContextDelegate {
    func print(_ str: String) {
        NSLog("Scheme: %@", str)
    }

    func read() -> String? {
        nil
    }
}
