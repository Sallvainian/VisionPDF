import Foundation
import Testing
@testable import VisionPDF

/// Exercises the real `ProcessRunner` against tiny system binaries — no
/// OCRmyPDF required.
@Suite("ProcessRunner")
struct ProcessRunnerTests {
    let runner = ProcessRunner()

    @Test("Successful exit status is reported")
    func success() async throws {
        let result = try await runner.run(
            executablePath: "/usr/bin/true",
            arguments: [],
            environment: nil,
            onLine: nil
        )
        #expect(result.exitCode == 0)
        #expect(!result.wasCancelled)
    }

    @Test("Failing exit status is reported")
    func failure() async throws {
        let result = try await runner.run(
            executablePath: "/usr/bin/false",
            arguments: [],
            environment: nil,
            onLine: nil
        )
        #expect(result.exitCode != 0)
        #expect(!result.wasCancelled)
    }

    @Test("Arguments with spaces, parentheses, brackets, and quotes survive verbatim")
    func argumentFidelity() async throws {
        let hostile = "My File (v2) [draft] 'quoted' $HOME && rm -rf ~"
        let result = try await runner.run(
            executablePath: "/bin/echo",
            arguments: [hostile],
            environment: nil,
            onLine: nil
        )
        #expect(result.exitCode == 0)
        // echo prints the argument exactly; a shell would have expanded it.
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == hostile)
    }

    @Test("stdout and stderr are captured separately and streamed")
    func streamSeparation() async throws {
        // The shell here is a test fixture generating two-stream output —
        // the app itself never launches OCRmyPDF through a shell.
        let collected = CollectedLines()
        let result = try await runner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo out1; echo err1 1>&2; echo out2"],
            environment: nil,
            onLine: { collected.append($0) }
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "out1\nout2\n")
        #expect(result.standardError == "err1\n")
        #expect(collected.lines(of: .stdout) == ["out1", "out2"])
        #expect(collected.lines(of: .stderr) == ["err1"])
    }

    @Test("Cancellation terminates the process", .timeLimit(.minutes(1)))
    func cancellation() async throws {
        let start = ContinuousClock.now
        let task = Task {
            try await runner.run(
                executablePath: "/bin/sleep",
                arguments: ["30"],
                environment: nil,
                onLine: nil
            )
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let result = try await task.value
        #expect(result.wasCancelled)
        // Terminated well before sleep would have finished on its own.
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("A nonexistent executable throws launchFailed")
    func launchFailure() async {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(
                executablePath: "/nonexistent/binary",
                arguments: [],
                environment: nil,
                onLine: nil
            )
        }
    }

    @Test("Environment is passed through")
    func environment() async throws {
        let result = try await runner.run(
            executablePath: "/usr/bin/env",
            arguments: [],
            environment: ["VISIONPDF_TEST_MARKER": "42", "PATH": "/usr/bin"],
            onLine: nil
        )
        #expect(result.standardOutput.contains("VISIONPDF_TEST_MARKER=42"))
    }

    @Test("Probe timeout kills a stuck process", .timeLimit(.minutes(1)))
    func probeTimeout() async {
        let start = ContinuousClock.now
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(
                executablePath: "/bin/sleep",
                arguments: ["30"],
                timeout: .seconds(1)
            )
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }
}

/// Thread-safe line collector for streaming assertions.
private final class CollectedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [OutputLine] = []

    func append(_ line: OutputLine) {
        lock.lock()
        all.append(line)
        lock.unlock()
    }

    func lines(of kind: OutputStreamKind) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return all.filter { $0.kind == kind }.map(\.text)
    }
}
