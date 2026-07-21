import Foundation

/// Assembles the diagnostics summary shown in the log panel and included in
/// saved logs. Contains only tool and run information — no personal data
/// beyond the file paths the user chose to process.
enum Diagnostics {
    static func summary(
        toolStatus: ToolStatus,
        toolInfo: ToolInfo?,
        settings: OCRSettings,
        lastArguments: [String]?,
        lastExitCode: Int32?
    ) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        var lines: [String] = [
            "── Diagnostics ──",
            "macOS: \(os)",
            "App: VisionPDF \(appVersion) (\(build))",
            "OCRmyPDF executable: \(toolInfo?.executablePath ?? "not found")",
            "OCRmyPDF version: \(toolInfo?.version ?? "unknown")",
            "Apple Vision plugin: \(toolStatus.appleVisionLabel)",
            "Selected engine: \(settings.engine.displayName)",
        ]
        if let lastArguments {
            lines.append("Arguments: \(lastArguments.joined(separator: " "))")
        }
        if let lastExitCode {
            lines.append("Exit code: \(lastExitCode) — \(OCRExitCode.explanation(for: lastExitCode))")
        }
        return lines.joined(separator: "\n")
    }
}
