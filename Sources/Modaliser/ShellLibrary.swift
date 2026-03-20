import Foundation
import LispKit

/// Native LispKit library providing shell command execution.
/// Scheme name: (modaliser shell)
///
/// Provides: run-shell
final class ShellLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "shell"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("run-shell", runShellFunction))
    }

    // MARK: - Functions

    /// (run-shell command) → string
    /// Executes a shell command via /bin/zsh -c and returns stdout as a string.
    private func runShellFunction(_ command: Expr) throws -> Expr {
        let commandString = try command.asString()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", commandString]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return .makeString(output)
    }
}
