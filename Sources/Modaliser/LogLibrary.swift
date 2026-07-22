import Foundation
import LispKit
import os

/// Native LispKit library providing an OS-visible diagnostic log line.
/// Scheme name: (modaliser log)
///
/// Logging is an OS capability — exactly what the Swift host is for; the
/// *policy* of what/when to log stays in Scheme (ADR-0017). NSLog is not
/// readable back from an installed .app ([[feedback_nslog_invisible_in_unified_log]]),
/// so this routes through os.Logger at .notice (the default persistence
/// level — .debug/.info never reach `log show` after the fact).
///
/// Provides: log-line
final class LogLibrary: NativeLibrary {

    private static let logger = Logger(subsystem: "dev.antony.Modaliser", category: "scheme")

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "log"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("log-line", logLineFunction))
    }

    /// (log-line message) → void
    /// Emits MESSAGE via os.Logger, readable via
    /// `log show --predicate 'subsystem == "dev.antony.Modaliser"'`.
    private func logLineFunction(_ message: Expr) throws -> Expr {
        let text = try message.asString()
        Self.logger.notice("\(text, privacy: .public)")
        return .void
    }
}
