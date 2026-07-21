import Foundation

/// Which stream a piece of process output arrived on.
enum OutputStreamKind: Hashable, Sendable {
    case stdout
    case stderr
}

/// One decoded line of process output.
struct OutputLine: Sendable {
    let kind: OutputStreamKind
    let text: String
}

/// Result of a completed (or terminated) process.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let wasCancelled: Bool
    /// Full stdout, for short probe commands like `--version`.
    let standardOutput: String
    /// Full stderr, for diagnostics.
    let standardError: String
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): "Could not launch process: \(reason)"
        case .timedOut: "The process did not respond in time."
        }
    }
}

/// Abstraction over process execution so view models and detection logic can be
/// unit-tested with a mock.
protocol ProcessRunning: Sendable {
    /// Runs `executablePath` with `arguments` (a structured array — never a
    /// shell string), streaming decoded output lines to `onLine`.
    ///
    /// Cancellation of the surrounding Swift task terminates the process
    /// (SIGTERM, escalating to SIGKILL after a grace period).
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        onLine: (@Sendable (OutputLine) -> Void)?
    ) async throws -> ProcessResult
}

extension ProcessRunning {
    /// Convenience for short probe commands with an overall timeout.
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: Duration
    ) async throws -> ProcessResult {
        try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await run(
                    executablePath: executablePath,
                    arguments: arguments,
                    environment: environment,
                    onLine: nil
                )
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ProcessRunnerError.timedOut
            }
            // First finished child wins; cancel the loser. If the sleep wins,
            // cancelling the runner child terminates the stuck process.
            guard let result = try await group.next() else {
                throw ProcessRunnerError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}

/// Splits raw pipe data into lines. Treats both `\n` and `\r` as line breaks so
/// terminal-style progress output (carriage-return rewrites) still becomes
/// discrete lines. Splitting only at ASCII control bytes means multi-byte UTF-8
/// sequences are never cut apart.
private struct LineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let breakIndex = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = pending.subdata(in: pending.startIndex..<breakIndex)
            if !lineData.isEmpty {
                lines.append(String(decoding: lineData, as: UTF8.self))
            }
            pending.removeSubrange(pending.startIndex...breakIndex)
        }
        return lines
    }

    mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        let text = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return text
    }
}

/// Shared mutable state for one process run. All mutation happens on the serial
/// `queue`, which is what makes the `@unchecked Sendable` sound.
private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    let queue = DispatchQueue(label: "VisionPDF.ProcessRunner")

    var cancelled = false
    var stdout = ""
    var stderr = ""
    private var buffers: [OutputStreamKind: LineBuffer] = [
        .stdout: LineBuffer(),
        .stderr: LineBuffer(),
    ]
    private var closedStreams = Set<OutputStreamKind>()
    private var drainContinuation: CheckedContinuation<Void, Never>?
    /// Runs when the drain grace period expires with a stream still open.
    var forceDrainCleanup: (() -> Void)?

    /// Called on `queue`: buffers incoming data, returning any completed lines.
    func bufferedLines(appending data: Data, kind: OutputStreamKind) -> [String] {
        buffers[kind, default: LineBuffer()].append(data)
    }

    /// Called on `queue`: returns the unterminated tail at EOF, if any.
    func flushBuffer(kind: OutputStreamKind) -> String? {
        buffers[kind, default: LineBuffer()].flush()
    }

    /// Called on `queue` when a stream reaches EOF. Idempotent per stream:
    /// at EOF the readability handler can fire more than once before it is
    /// fully uninstalled, so extra notifications must not over-count.
    func streamClosed(_ kind: OutputStreamKind) {
        guard closedStreams.insert(kind).inserted else { return }
        if closedStreams.count == 2 {
            resumeDrain()
        }
    }

    /// Called on `queue`. Resumes immediately if both streams already closed;
    /// otherwise waits for EOF, but only up to `grace` seconds. The bound
    /// matters: pipe EOF requires *every* copy of the write end to close, and
    /// descendants of the child (OCRmyPDF worker processes, or daemons spawned
    /// by a login shell) inherit those write ends — without the bound, a
    /// lingering grandchild would block this continuation forever.
    func notifyWhenDrained(_ continuation: CheckedContinuation<Void, Never>, grace: TimeInterval) {
        if closedStreams.count == 2 {
            continuation.resume()
            return
        }
        drainContinuation = continuation
        queue.asyncAfter(deadline: .now() + grace) { [self] in
            if drainContinuation != nil {
                forceDrainCleanup?()
                resumeDrain()
            }
        }
    }

    private func resumeDrain() {
        if let continuation = drainContinuation {
            drainContinuation = nil
            continuation.resume()
        }
    }

    /// Called on `queue`. Terminates a running process, escalating to SIGKILL
    /// if it ignores SIGTERM.
    func terminateNow() {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        queue.asyncAfter(deadline: .now() + 5) { [self] in
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}

/// Real process execution built on `Foundation.Process` with `executableURL`
/// and a structured argument array — arguments are never joined into a shell
/// string, so file names containing spaces, quotes, brackets, parentheses, or
/// other shell metacharacters need no quoting and cannot be misinterpreted.
struct ProcessRunner: ProcessRunning {
    func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        onLine: (@Sendable (OutputLine) -> Void)?
    ) async throws -> ProcessResult {
        let box = ProcessBox()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        box.process.executableURL = URL(fileURLWithPath: executablePath)
        box.process.arguments = arguments
        if let environment {
            box.process.environment = environment
        }
        box.process.standardOutput = stdoutPipe
        box.process.standardError = stderrPipe
        box.process.standardInput = FileHandle.nullDevice

        let installReader: (Pipe, OutputStreamKind) -> Void = { pipe, kind in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // Uninstall synchronously — at EOF the handler would
                    // otherwise keep firing until the async hop runs.
                    handle.readabilityHandler = nil
                }
                box.queue.async {
                    if data.isEmpty {
                        if let tail = box.flushBuffer(kind: kind) {
                            box.record(kind: kind, line: tail)
                            onLine?(OutputLine(kind: kind, text: tail))
                        }
                        box.streamClosed(kind)
                        return
                    }
                    for line in box.bufferedLines(appending: data, kind: kind) {
                        box.record(kind: kind, line: line)
                        onLine?(OutputLine(kind: kind, text: line))
                    }
                }
            }
        }
        installReader(stdoutPipe, .stdout)
        installReader(stderrPipe, .stderr)

        return try await withTaskCancellationHandler {
            let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
                box.process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }
                do {
                    try box.process.run()
                    // Cancellation may have been delivered before launch — the
                    // onCancel handler fires only once and would have found no
                    // running process. Re-check now that the process exists.
                    box.queue.async {
                        if box.cancelled {
                            box.terminateNow()
                        }
                    }
                } catch {
                    box.process.terminationHandler = nil
                    // Tear down the readers; the process never started.
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                }
            }

            // The process has exited, but the pipes may still hold buffered
            // output. Wait for both streams to report EOF (bounded — see
            // notifyWhenDrained) before reading the transcripts.
            await withCheckedContinuation { continuation in
                box.queue.async {
                    box.forceDrainCleanup = {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                    }
                    box.notifyWhenDrained(continuation, grace: 2)
                }
            }
            let (cancelled, stdout, stderr) = await withCheckedContinuation { continuation in
                box.queue.async {
                    continuation.resume(returning: (box.cancelled, box.stdout, box.stderr))
                }
            }
            return ProcessResult(
                exitCode: exitCode,
                wasCancelled: cancelled,
                standardOutput: stdout,
                standardError: stderr
            )
        } onCancel: {
            box.queue.async {
                box.cancelled = true
                box.terminateNow()
            }
        }
    }
}

private extension ProcessBox {
    /// Called on `queue`.
    func record(kind: OutputStreamKind, line: String) {
        switch kind {
        case .stdout: stdout += line + "\n"
        case .stderr: stderr += line + "\n"
        }
    }
}
