import Foundation
import LispKit

/// Wraps a LispKit context for evaluating Scheme code.
/// Provides the bridge between Swift and the Scheme configuration layer.
final class SchemeEngine {
    let context: LispKitContext
    let registry: CommandTreeRegistry

    init() throws {
        let delegate = ModaliserContextDelegate()
        registry = CommandTreeRegistry()
        context = LispKitContext(
            delegate: delegate,
            implementationName: "Modaliser",
            implementationVersion: "0.1",
            commandLineArguments: [],
            includeInternalResources: true,
            includeDocumentPath: nil
        )
        try context.environment.import(BaseLibrary.name)
        // Register and import the Modaliser DSL library
        try context.libraries.register(libraryType: ModaliserDSLLibrary.self)
        if let dslLib = try context.libraries.lookup(ModaliserDSLLibrary.self) {
            dslLib.registry = registry
        }
        try context.environment.import(ModaliserDSLLibrary.name)
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
        // Check if the result is an error
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
