import Foundation
import os

/// Probes an ocrmypdf executable: version, then Apple Vision plugin
/// availability. Never assumes the plugin exists just because ocrmypdf does.
struct ToolDetector: Sendable {
    private static let logger = Logger(
        subsystem: "com.sallvain.VisionPDF",
        category: "detection"
    )

    var processRunner: any ProcessRunning = ProcessRunner()

    struct Detection: Sendable {
        var status: ToolStatus
        var toolInfo: ToolInfo?
    }

    static let pluginName = "ocrmypdf_appleocr"

    /// Full detection pass for a located executable.
    func detect(executablePath: String, loginShellPATH: String?) async -> Detection {
        let environment = ExecutableLocator.environment(
            executablePath: executablePath,
            loginShellPATH: loginShellPATH
        )

        // Step 1: `ocrmypdf --version` proves the executable actually runs.
        let version: String
        do {
            let result = try await processRunner.run(
                executablePath: executablePath,
                arguments: ["--version"],
                environment: environment,
                timeout: .seconds(30)
            )
            Self.logger.info(
                "--version probe: exit=\(result.exitCode) cancelled=\(result.wasCancelled) stdout=\(result.standardOutput.count) bytes stderr=\(result.standardError.count) bytes stdoutHead='\(result.standardOutput.prefix(120))' stderrHead='\(result.standardError.prefix(200))'"
            )
            guard result.exitCode == 0 else {
                let detail = result.standardError
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Detection(
                    status: .detectionFailed(
                        "ocrmypdf --version exited with code \(result.exitCode)."
                        + (detail.isEmpty ? "" : "\n\(detail)")
                    ),
                    toolInfo: nil
                )
            }
            // OCRmyPDF 17 prints the version to stderr; older versions used
            // stdout. Accept the first non-empty line from either stream.
            let parsed = Self.firstNonEmptyLine(of: result.standardOutput)
                ?? Self.firstNonEmptyLine(of: result.standardError)
            guard let parsed else {
                return Detection(
                    status: .detectionFailed("ocrmypdf --version produced no output."),
                    toolInfo: nil
                )
            }
            version = parsed
        } catch {
            return Detection(
                status: .detectionFailed("Could not run ocrmypdf: \(error.localizedDescription)"),
                toolInfo: nil
            )
        }

        // Step 2: probe the Apple Vision plugin with a lightweight `--help`.
        // Exit code 0 means ocrmypdf imported the plugin successfully.
        do {
            let result = try await processRunner.run(
                executablePath: executablePath,
                arguments: ["--plugin", Self.pluginName, "--help"],
                environment: environment,
                timeout: .seconds(30)
            )
            if result.exitCode == 0 {
                return Detection(
                    status: .fullyAvailable(version: version),
                    toolInfo: ToolInfo(
                        executablePath: executablePath,
                        version: version,
                        appleVisionAvailable: true,
                        searchPATH: environment["PATH"] ?? ""
                    )
                )
            }
            let reason = Self.pluginFailureReason(
                exitCode: result.exitCode,
                stderr: result.standardError
            )
            return Detection(
                status: .pluginUnavailable(version: version, reason: reason),
                toolInfo: ToolInfo(
                    executablePath: executablePath,
                    version: version,
                    appleVisionAvailable: false,
                    searchPATH: environment["PATH"] ?? ""
                )
            )
        } catch {
            // ocrmypdf itself works; treat a misbehaving probe as an
            // unavailable plugin rather than a hard failure, but say why.
            return Detection(
                status: .pluginUnavailable(
                    version: version,
                    reason: "Plugin probe failed: \(error.localizedDescription)"
                ),
                toolInfo: ToolInfo(
                    executablePath: executablePath,
                    version: version,
                    appleVisionAvailable: false,
                    searchPATH: environment["PATH"] ?? ""
                )
            )
        }
    }

    private static func firstNonEmptyLine(of text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    static func pluginFailureReason(exitCode: Int32, stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveContains("ModuleNotFoundError")
            || trimmed.localizedCaseInsensitiveContains("No module named") {
            return "The \(pluginName) Python package is not installed in OCRmyPDF's environment. "
            + "Install it with: uv tool install --with ocrmypdf-appleocr ocrmypdf"
        }
        let lastLine = trimmed.components(separatedBy: .newlines).last { !$0.isEmpty } ?? ""
        return "Loading the plugin failed (exit code \(exitCode))."
        + (lastLine.isEmpty ? "" : " \(lastLine)")
    }
}
