import Foundation
@testable import VisionPDF

/// Scripted stand-in for `ProcessRunner`. Records every invocation and plays
/// back queued results, optionally emitting output lines and honoring task
/// cancellation, so process-driven logic can be tested without spawning
/// anything.
final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Invocation: Sendable {
        let executablePath: String
        let arguments: [String]
        let environment: [String: String]?
    }

    /// One scripted response.
    struct Script: Sendable {
        var result: ProcessResult
        var lines: [OutputLine] = []
        /// When set, the run "hangs" this long; if cancelled meanwhile, it
        /// returns a cancelled result like a terminated process would.
        var delay: Duration?
        /// When set, the run throws instead of returning — mirroring the real
        /// runner's launchFailed/timedOut paths.
        var error: ProcessRunnerError?
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    private var scripts: [Script]
    private let fallback: Script

    init(scripts: [Script] = [], fallback: Script = Script(
        result: ProcessResult(exitCode: 0, wasCancelled: false, standardOutput: "", standardError: "")
    )) {
        self.scripts = scripts
        self.fallback = fallback
    }

    var invocations: [Invocation] {
        lock.lock()
        defer { lock.unlock() }
        return _invocations
    }

    /// Synchronous so it can take the lock from the async `run`.
    private func dequeueScript(recording invocation: Invocation) -> Script {
        lock.lock()
        defer { lock.unlock() }
        _invocations.append(invocation)
        return scripts.isEmpty ? fallback : scripts.removeFirst()
    }

    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        onLine: (@Sendable (OutputLine) -> Void)?
    ) async throws -> ProcessResult {
        let script = dequeueScript(recording: Invocation(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment
        ))
        if let error = script.error {
            throw error
        }

        for line in script.lines {
            onLine?(line)
        }
        if let delay = script.delay {
            try? await Task.sleep(for: delay)
            if Task.isCancelled {
                return ProcessResult(
                    exitCode: 15,
                    wasCancelled: true,
                    standardOutput: "",
                    standardError: ""
                )
            }
        }
        return script.result
    }
}

extension ProcessResult {
    static func exit(_ code: Int32, stdout: String = "", stderr: String = "") -> ProcessResult {
        ProcessResult(exitCode: code, wasCancelled: false, standardOutput: stdout, standardError: stderr)
    }
}
