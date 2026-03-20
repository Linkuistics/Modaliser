import Foundation
import LispKit

/// Native LispKit library providing shell command execution.
/// Scheme name: (modaliser shell)
///
/// Provides: run-shell, run-shell-async
final class ShellLibrary: NativeLibrary {
    private var activeProcesses: Set<Process> = []

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
        self.define(Procedure("run-shell-async", runShellAsyncFunction))
    }

    /// Terminate all active background processes. Called on app quit.
    func terminateAllProcesses() {
        for process in activeProcesses where process.isRunning {
            process.terminate()
        }
        activeProcesses.removeAll()
    }

    // MARK: - Sync

    /// (run-shell command) -> string
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

    // MARK: - Async

    /// (run-shell-async command callback ['timeout seconds]) -> void
    /// Runs command in background, calls (callback exit-code stdout stderr) on main thread.
    /// On timeout: exit-code = -1, stdout = "", stderr = "timeout".
    private func runShellAsyncFunction(_ command: Expr, _ callback: Expr, _ rest: Arguments) throws -> Expr {
        let commandString = try command.asString()
        guard case .procedure = callback else {
            throw RuntimeError.custom("eval", "run-shell-async: second argument must be a procedure", [])
        }

        var timeoutSeconds: Double? = nil
        var i = rest.startIndex
        while i < rest.endIndex {
            if case .symbol(let sym) = rest[i], sym.description == "timeout" {
                let nextIndex = rest.index(after: i)
                if nextIndex < rest.endIndex {
                    if case .fixnum(let n) = rest[nextIndex] {
                        timeoutSeconds = Double(n)
                    } else if case .flonum(let n) = rest[nextIndex] {
                        timeoutSeconds = n
                    }
                    i = rest.index(after: nextIndex)
                    continue
                }
            }
            i = rest.index(after: i)
        }

        guard let evaluator = self.context.evaluator else {
            throw RuntimeError.custom("eval", "run-shell-async: evaluator not available", [])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", commandString]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        activeProcesses.insert(process)

        DispatchQueue.global().async { [weak self] in
            do {
                try process.run()
            } catch {
                self?.invokeCallback(
                    evaluator: evaluator,
                    callback: callback,
                    exitCode: -1,
                    stdout: "",
                    stderr: error.localizedDescription
                )
                DispatchQueue.main.async { self?.activeProcesses.remove(process) }
                return
            }

            var timedOut = false

            if let timeout = timeoutSeconds {
                let deadline = DispatchTime.now() + timeout
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning {
                        timedOut = true
                        process.terminate()
                    }
                }
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            if timedOut {
                self?.invokeCallback(
                    evaluator: evaluator,
                    callback: callback,
                    exitCode: -1,
                    stdout: "",
                    stderr: "timeout"
                )
            } else {
                let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                let exitCode = Int(process.terminationStatus)

                self?.invokeCallback(
                    evaluator: evaluator,
                    callback: callback,
                    exitCode: exitCode,
                    stdout: stdoutStr,
                    stderr: stderrStr
                )
            }

            DispatchQueue.main.async { self?.activeProcesses.remove(process) }
        }

        return .void
    }

    private func invokeCallback(
        evaluator: Evaluator,
        callback: Expr,
        exitCode: Int,
        stdout: String,
        stderr: String
    ) {
        let args: Expr = .pair(
            .fixnum(Int64(exitCode)),
            .pair(.makeString(stdout),
                  .pair(.makeString(stderr), .null))
        )
        DispatchQueue.main.async {
            _ = evaluator.execute { machine in
                try machine.apply(callback, to: args)
            }
        }
    }
}
