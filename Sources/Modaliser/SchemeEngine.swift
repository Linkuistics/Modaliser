import Foundation
import LispKit

/// Locate LispKit's bundled R7RS+SRFI Libraries directory.
///
/// LispKit's Package.swift `exclude`s its Resources/ directory from SPM
/// bundling, so neither static nor dynamic linking ships the .sld files
/// automatically. We probe several locations:
///
///   1. Installed .app — `Contents/Resources/LispKitLibraries/` (copied
///      in by scripts/build-app.sh from the SPM checkout)
///   2. `swift test` / `swift run` — walk up from CWD looking for
///      `.build/checkouts/swift-lispkit/Sources/LispKit/Resources/Libraries`
///   3. Same walk from the executable path (covers `swift build` runs
///      where CWD ≠ project root)
///
/// Returns nil if none found — root.scm will then fail at the first
/// `(import (modaliser …))` because `(scheme base)` can't be resolved.
private func locateLispKitLibrariesFallback() -> String? {
    // 1. Installed .app bundle. Resources are siblings of the main bundle's
    // Modaliser binary inside Contents/Resources/.
    if let resourceURL = Bundle.main.resourceURL {
        let bundled = resourceURL.appendingPathComponent("LispKitLibraries").path
        if FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
    }

    let suffix = ".build/checkouts/swift-lispkit/Sources/LispKit/Resources/Libraries"
    // 2. Walk up from CWD.
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .resolvingSymlinksInPath()
    for _ in 0..<8 {
        let candidate = dir.appendingPathComponent(suffix).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent
    }
    // 3. Walk up from the executable.
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

/// The engine's LispKit context, extended with a per-engine evaluation
/// fence.
///
/// In the app every evaluation reaches the evaluator on the main thread
/// (key events, menu actions, timer/completion callbacks all dispatch to
/// the main queue), so the run loop serializes them. Under `swift test`,
/// Swift Testing runs @Test bodies on cooperative-pool threads while the
/// process main thread keeps draining the main queue — so a main-queue
/// callback (e.g. `after-delay`) can re-enter a VirtualMachine that is
/// mid-evaluation on a test thread, tripping LispKit's `assertTopLevel`
/// precondition and killing the process. The fence restores the
/// one-evaluation-at-a-time guarantee per engine.
///
/// Recursive so a same-thread nested entry can never self-deadlock at the
/// fence (LispKit's own precondition still guards genuine reentrancy).
final class ModaliserContext: Context {
    let evalLock = NSRecursiveLock()

    init(delegate: ContextDelegate,
         implementationName: String,
         implementationVersion: String) {
        super.init(delegate: delegate,
                   implementationName: implementationName,
                   implementationVersion: implementationVersion,
                   commandLineArguments: [],
                   initialHomePath: nil,
                   includeInternalResources: true,
                   includeDocumentPath: nil,
                   assetPath: nil,
                   gcDelay: 5.0,
                   features: [],
                   limitStack: 10000000)
    }
}

extension Context {
    /// Run `body` holding the per-engine evaluation fence, blocking until
    /// it is free. For synchronous evaluator entries (SchemeEngine's
    /// evaluate/evaluateFile). Must NOT be used on the main thread for
    /// callback re-entries — see `withEvalLockNonBlocking`.
    func withEvalLock<T>(_ body: () throws -> T) rethrows -> T {
        guard let lock = (self as? ModaliserContext)?.evalLock else {
            return try body()
        }
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Run `body` under the evaluation fence without ever blocking the
    /// calling thread: on contention, re-enqueue on the main queue and try
    /// again shortly. Every evaluator re-entry from a main-queue callback
    /// must use this — blocking the main thread on the fence can deadlock
    /// against an off-main evaluation that synchronously hops to the main
    /// thread (HintsLibrary.onMain does `DispatchQueue.main.sync`).
    /// Contention only exists under `swift test`; in the app all
    /// evaluation is main-thread and the try always succeeds immediately.
    func withEvalLockNonBlocking(_ body: @escaping () -> Void) {
        guard let lock = (self as? ModaliserContext)?.evalLock else {
            body()
            return
        }
        if lock.try() {
            defer { lock.unlock() }
            body()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.withEvalLockNonBlocking(body)
            }
        }
    }
}

/// Wraps a LispKit context for evaluating Scheme code.
/// Provides the bridge between Swift and the Scheme configuration layer.
final class SchemeEngine {
    let context: ModaliserContext

    /// The resolved path to the Scheme directory, if found.
    private(set) var schemeDirectoryPath: String?

    init(userConfigDir: String? = nil) throws {
        let delegate = ModaliserContextDelegate()
        context = ModaliserContext(
            delegate: delegate,
            implementationName: "Modaliser",
            implementationVersion: "0.1"
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

        // Resolve the Scheme directory. In production we mirror the whole
        // tree into ~/.config/modaliser/sys/scheme via SysSync and read
        // from there so users can browse/fork every bundled file. In
        // dev/test we read directly from the bundle.
        let bundleSchemePath = SchemeEngine.resolveSchemeDirectory()
        let resolvedUserConfigDir = userConfigDir
            ?? NSString(string: "~/.config/modaliser").expandingTildeInPath

        var effectiveSchemePath = bundleSchemePath
        if let bundlePath = bundleSchemePath {
            // Always allow the bundle path to satisfy reads in dev/test.
            _ = context.fileHandler.addSearchPath(bundlePath)
            let bundledLibRoot = (bundlePath as NSString).appendingPathComponent("lib")
            _ = context.fileHandler.prependLibrarySearchPath(bundledLibRoot)

            if SchemeEngine.isProductionBundlePath(bundlePath) {
                if let sysSchemeDir = SysSync.sync(
                    bundleSchemeDir: bundlePath,
                    userConfigDir: resolvedUserConfigDir) {
                    effectiveSchemePath = sysSchemeDir
                    _ = context.fileHandler.addSearchPath(sysSchemeDir)
                    let syncedLibRoot = (sysSchemeDir as NSString).appendingPathComponent("lib")
                    _ = context.fileHandler.prependLibrarySearchPath(syncedLibRoot)
                }
            }

            if let schemePath = effectiveSchemePath {
                try evaluate("(define *scheme-directory* \"\(schemePath)\")")
            }
            NSLog("SchemeEngine: Scheme directory at %@ (bundle=%@)",
                  effectiveSchemePath ?? "(nil)", bundlePath)
        }

        schemeDirectoryPath = effectiveSchemePath

        // Prepend the user-config root LAST, so it ends up FIRST on the
        // library search path — user libraries shadow bundled ones (and
        // shadow the synced sys/ copies). Missing path is silently
        // skipped by prependLibrarySearchPath.
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
        try context.libraries.register(libraryType: LogLibrary.self)
        try context.environment.import(LogLibrary.name)
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
        try context.libraries.register(libraryType: CursorLibrary.self)
        try context.environment.import(CursorLibrary.name)
    }

    /// Evaluate a string of Scheme code and return the result.
    @discardableResult
    func evaluate(_ code: String) throws -> Expr {
        let result = context.withEvalLock {
            context.evaluator.execute { machine in
                try machine.eval(
                    str: code,
                    sourceId: SourceManager.consoleSourceId,
                    in: self.context.global
                )
            }
        }
        if case .error(let err) = result {
            throw err
        }
        return result
    }

    /// Load and evaluate a Scheme file.
    func evaluateFile(_ path: String) throws {
        let result = context.withEvalLock {
            context.evaluator.execute { machine in
                try machine.eval(file: path, in: self.context.global)
            }
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

    /// True iff `path` lives inside an installed .app bundle's
    /// Contents/. This is the signal we use to decide whether to mirror
    /// bundled libraries into ~/.config/modaliser/sys/ — dev runs
    /// (Sources/Modaliser/Scheme) and tests must never write there.
    private static func isProductionBundlePath(_ path: String) -> Bool {
        return path.range(of: ".app/Contents/") != nil
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
