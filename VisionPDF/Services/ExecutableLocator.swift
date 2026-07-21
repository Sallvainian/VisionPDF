import Foundation

/// Finds the `ocrmypdf` executable.
///
/// GUI apps launched from Finder inherit a minimal PATH
/// (`/usr/bin:/bin:/usr/sbin:/sbin`), which usually does not include Homebrew
/// or uv tool locations. So the locator checks well-known install paths
/// directly and, as a fallback, asks a login shell — which loads the user's
/// profile and therefore sees the same PATH as Terminal.
struct ExecutableLocator: Sendable {
    /// Well-known install locations, checked in order.
    static func defaultCandidates(home: String = NSHomeDirectory()) -> [String] {
        [
            "/usr/local/bin/ocrmypdf",
            "/opt/homebrew/bin/ocrmypdf",
            "\(home)/.local/bin/ocrmypdf",
        ]
    }

    /// Injectable for tests. Defaults to a real file-system check.
    var isExecutableFile: @Sendable (String) -> Bool = { path in
        FileManager.default.isExecutableFile(atPath: path)
    }

    var processRunner: any ProcessRunning = ProcessRunner()

    /// Locates ocrmypdf. `preferredPath` is the user's manual override from
    /// Settings and always wins when it still points at an executable.
    func locate(preferredPath: String?) async -> String? {
        if let preferredPath, !preferredPath.isEmpty, isExecutableFile(preferredPath) {
            return preferredPath
        }
        for candidate in Self.defaultCandidates() where isExecutableFile(candidate) {
            return candidate
        }
        return await locateViaLoginShell()
    }

    /// Runs `command -v ocrmypdf` in a zsh login shell. The single fixed
    /// argument string is a constant — no user input is ever interpolated into
    /// a shell command anywhere in the app.
    private func locateViaLoginShell() async -> String? {
        guard let result = try? await processRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-l", "-c", "command -v ocrmypdf"],
            timeout: .seconds(10)
        ), result.exitCode == 0 else {
            return nil
        }
        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, isExecutableFile(path) else { return nil }
        return path
    }

    /// Captures the login shell's PATH so OCRmyPDF's helper programs
    /// (tesseract, gs, unpaper) resolve exactly as they do in Terminal.
    func loginShellPATH() async -> String? {
        guard let result = try? await processRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-l", "-c", "printf %s \"$PATH\""],
            timeout: .seconds(10)
        ), result.exitCode == 0 else {
            return nil
        }
        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Builds the environment for OCRmyPDF runs: the current environment with
    /// PATH replaced by the login-shell PATH (when captured) plus well-known
    /// tool directories, so subprocesses spawned by OCRmyPDF are found even
    /// though the GUI app itself was launched with a minimal PATH.
    static func environment(
        executablePath: String,
        loginShellPATH: String?,
        home: String = NSHomeDirectory(),
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        var components: [String] = [executableDir]
        if let loginShellPATH {
            components.append(loginShellPATH)
        }
        components.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ])
        // Deduplicate while preserving priority order.
        var seen = Set<String>()
        let merged = components
            .flatMap { $0.split(separator: ":").map(String.init) }
            .filter { seen.insert($0).inserted }
        env["PATH"] = merged.joined(separator: ":")
        // Belt and braces: make sure Python streams are not block-buffered so
        // log output arrives promptly through the pipe.
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }
}
