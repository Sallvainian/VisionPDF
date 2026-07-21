import Foundation
import Testing
@testable import VisionPDF

@Suite("ToolDetector")
struct ToolDetectorTests {
    private let executable = "/Users/someone/.local/bin/ocrmypdf"

    @Test("Working ocrmypdf with a working plugin reports fully available")
    func fullyAvailable() async {
        // OCRmyPDF 17.8.1 really prints the version to stderr (verified
        // empirically: `ocrmypdf --version 2>/dev/null` is empty).
        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(0, stderr: "17.8.1\n")),   // --version
            .init(result: .exit(0, stdout: "usage: …")),   // plugin --help
        ])
        var detector = ToolDetector()
        detector.processRunner = runner
        let detection = await detector.detect(executablePath: executable, loginShellPATH: nil)

        #expect(detection.status == .fullyAvailable(version: "17.8.1"))
        #expect(detection.toolInfo?.appleVisionAvailable == true)
        #expect(detection.toolInfo?.version == "17.8.1")

        // The probe used the documented plugin invocation.
        #expect(runner.invocations.count == 2)
        #expect(runner.invocations[0].arguments == ["--version"])
        #expect(runner.invocations[1].arguments == ["--plugin", "ocrmypdf_appleocr", "--help"])
    }

    @Test("Missing plugin module reports plugin unavailable with install hint")
    func pluginMissing() async {
        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(0, stdout: "17.8.1\n")),
            .init(result: .exit(1, stderr: "ModuleNotFoundError: No module named 'ocrmypdf_appleocr'")),
        ])
        var detector = ToolDetector()
        detector.processRunner = runner
        let detection = await detector.detect(executablePath: executable, loginShellPATH: nil)

        guard case .pluginUnavailable(let version, let reason) = detection.status else {
            Issue.record("Expected pluginUnavailable, got \(detection.status)")
            return
        }
        #expect(version == "17.8.1")
        #expect(reason.contains("uv tool install"))
        #expect(detection.toolInfo?.appleVisionAvailable == false)
    }

    @Test("Version on stdout (older OCRmyPDF) is also accepted")
    func versionOnStdout() async {
        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(0, stdout: "16.0.0\n")),
            .init(result: .exit(0)),
        ])
        var detector = ToolDetector()
        detector.processRunner = runner
        let detection = await detector.detect(executablePath: executable, loginShellPATH: nil)
        #expect(detection.status == .fullyAvailable(version: "16.0.0"))
    }

    @Test("Broken executable reports detection failed")
    func versionFails() async {
        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(2, stderr: "dyld: missing library")),
        ])
        var detector = ToolDetector()
        detector.processRunner = runner
        let detection = await detector.detect(executablePath: executable, loginShellPATH: nil)

        guard case .detectionFailed(let reason) = detection.status else {
            Issue.record("Expected detectionFailed, got \(detection.status)")
            return
        }
        #expect(reason.contains("exited with code 2"))
        #expect(detection.toolInfo == nil)
    }

    @Test("Plugin failure reasons surface the last stderr line")
    func failureReason() {
        let reason = ToolDetector.pluginFailureReason(
            exitCode: 1,
            stderr: "Traceback…\nSomethingError: plugin exploded"
        )
        #expect(reason.contains("plugin exploded"))
        #expect(reason.contains("exit code 1"))
    }
}
