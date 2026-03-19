import Foundation
import LispKit

/// Executes Scheme lambdas (command actions) through the LispKit evaluator.
/// Separates action execution from the state machine for testability.
final class CommandExecutor {
    private let engine: SchemeEngine

    init(engine: SchemeEngine) {
        self.engine = engine
    }

    /// Execute a Scheme lambda (zero-argument procedure) and return its result.
    /// Throws if the expression is not a procedure or if evaluation fails.
    @discardableResult
    func execute(action: Expr) throws -> Expr {
        try execute(action: action, arguments: .null)
    }

    /// Execute a Scheme lambda with a single argument and return its result.
    /// Used for selector callbacks (onSelect, action run) that receive the chosen value.
    @discardableResult
    func execute(action: Expr, argument: Expr) throws -> Expr {
        try execute(action: action, arguments: .pair(argument, .null))
    }

    // MARK: - Private

    private func execute(action: Expr, arguments: Expr) throws -> Expr {
        guard case .procedure = action else {
            throw CommandExecutorError.notAProcedure(action)
        }
        let result = engine.context.evaluator.execute { machine in
            try machine.apply(action, to: arguments)
        }
        if case .error(let err) = result {
            throw err
        }
        return result
    }
}

/// Errors from command execution.
enum CommandExecutorError: Error, LocalizedError {
    case notAProcedure(Expr)

    var errorDescription: String? {
        switch self {
        case .notAProcedure(let expr):
            return "Expected a Scheme procedure to execute, got: \(expr)"
        }
    }
}
