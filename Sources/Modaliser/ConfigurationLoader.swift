import Foundation
import LispKit
import os

/// What the configuration boot ended up doing.
///
/// `errorText` is what the user is shown; the distinction between `degraded`
/// and `failed` is whether anything is armed behind that message.
enum ConfigLoadOutcome: Equatable {
    /// The user's own config evaluated cleanly.
    case loaded
    /// The user's config aborted; the bundled default is armed in its place,
    /// so leaders still work.
    case degraded(String)
    /// The user's config aborted and so did the bundled default. Usually
    /// nothing is armed; the exception is a config that aborted *after* its
    /// handoff, which leaves its own leaders live and makes the fallback's
    /// handoff a second call. Either way the menu is still built.
    case failed(userError: String, fallbackError: String)

    /// The user-facing error, or nil when the user's own config loaded.
    var errorText: String? {
        switch self {
        case .loaded: return nil
        case .degraded(let message): return message
        case .failed(let userError, _): return userError
        }
    }
}

extension SchemeEngine {

    private static let logger = Logger(subsystem: LogLibrary.subsystem, category: "config")

    /// Evaluate the user's configuration, falling back to the bundled default
    /// if it aborts. Never throws: a bad config degrades, it does not wedge.
    ///
    /// **Why this is the host's job.** LispKit implements `raise` in Scheme, so
    /// `guard` catches only conditions a Scheme program raised deliberately. The
    /// three ways a config actually fails — a read error, a type error, an
    /// unbound variable — are thrown out of the virtual machine and unwind past
    /// every Scheme handler; and `evaluator.execute` asserts top level, so a
    /// native primitive cannot wrap a nested evaluation either. Sequencing two
    /// top-level evaluations, and looking at the abort in between, is the only
    /// place the guard can live (ADR-0022).
    ///
    /// **Why the fallback is safe.** `modaliser:start!` is the single effectful
    /// moment and validates before it installs (ADR-0018), so a config that dies
    /// mid-file installed nothing. The bundled default therefore loads into a
    /// clean engine rather than colliding with half of the user's graph.
    func loadConfiguration(userConfigPath: String, fallbackPath: String) -> ConfigLoadOutcome {
        do {
            try evaluateFile(userConfigPath)
            return .loaded
        } catch {
            let userError = describeEvalFailure(error)
            Self.logger.error("""
                user config failed to load: \(userError, privacy: .public) \
                (path: \(userConfigPath, privacy: .public))
                """)
            do {
                try evaluateFile(fallbackPath)
                Self.logger.notice("armed the bundled default config instead")
                return .degraded(userError)
            } catch {
                let fallbackError = describeEvalFailure(error)
                Self.logger.fault("""
                    bundled default config also failed: \(fallbackError, privacy: .public) \
                    (path: \(fallbackPath, privacy: .public))
                    """)
                return .failed(userError: userError, fallbackError: fallbackError)
            }
        }
    }

    /// Render an evaluation failure as text a user can act on: the descriptor
    /// and message, plus the source position when LispKit knows one — a bare
    /// "variable not yet initialized" does not say which line to edit.
    /// Irritants and the call trace are suppressed; they describe engine
    /// internals, not the config.
    private func describeEvalFailure(_ error: Error) -> String {
        guard let runtimeError = error as? RuntimeError else {
            return "\(error)"
        }
        return runtimeError.printableDescription(context: context,
                                                 irritantHeader: nil,
                                                 stackTraceHeader: nil)
    }
}
