import Foundation
import Testing
@testable import VisionPDF

@Suite("ExecutableLocator")
struct ExecutableLocatorTests {
    @Test("A valid manual override always wins")
    func overrideWins() async {
        var locator = ExecutableLocator()
        locator.isExecutableFile = { $0 == "/custom/ocrmypdf" || $0 == "/opt/homebrew/bin/ocrmypdf" }
        locator.processRunner = MockProcessRunner()
        let found = await locator.locate(preferredPath: "/custom/ocrmypdf")
        #expect(found == "/custom/ocrmypdf")
    }

    @Test("A stale override falls back to the standard candidates")
    func staleOverrideFallsBack() async {
        var locator = ExecutableLocator()
        locator.isExecutableFile = { $0 == "/opt/homebrew/bin/ocrmypdf" }
        locator.processRunner = MockProcessRunner()
        let found = await locator.locate(preferredPath: "/gone/ocrmypdf")
        #expect(found == "/opt/homebrew/bin/ocrmypdf")
    }

    @Test("Candidates are checked in declared order")
    func candidateOrder() async {
        var locator = ExecutableLocator()
        locator.isExecutableFile = { path in
            path == "/usr/local/bin/ocrmypdf" || path == "/opt/homebrew/bin/ocrmypdf"
        }
        locator.processRunner = MockProcessRunner()
        let found = await locator.locate(preferredPath: nil)
        #expect(found == "/usr/local/bin/ocrmypdf")
    }

    @Test("Login shell result is used when no candidate exists")
    func loginShellFallback() async {
        let shellPath = "/Users/someone/.local/bin/ocrmypdf"
        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(0, stdout: shellPath + "\n")),
        ])
        var locator = ExecutableLocator()
        locator.isExecutableFile = { $0 == shellPath }
        locator.processRunner = runner
        let found = await locator.locate(preferredPath: nil)
        #expect(found == shellPath)
        // And the probe really was `command -v` through a login shell.
        #expect(runner.invocations.first?.executablePath == "/bin/zsh")
        #expect(runner.invocations.first?.arguments == ["-l", "-c", "command -v ocrmypdf"])
    }

    @Test("Nothing found anywhere returns nil")
    func nothingFound() async {
        let runner = MockProcessRunner(fallback: .init(result: .exit(1)))
        var locator = ExecutableLocator()
        locator.isExecutableFile = { _ in false }
        locator.processRunner = runner
        let found = await locator.locate(preferredPath: nil)
        #expect(found == nil)
    }

    @Test("Environment PATH puts the executable's directory first and deduplicates")
    func environmentMerge() {
        let env = ExecutableLocator.environment(
            executablePath: "/Users/someone/.local/bin/ocrmypdf",
            loginShellPATH: "/opt/homebrew/bin:/usr/bin:/Users/someone/.local/bin",
            home: "/Users/someone",
            base: ["PATH": "/usr/bin:/bin"]
        )
        let path = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        #expect(path.first == "/Users/someone/.local/bin")
        #expect(path.filter { $0 == "/opt/homebrew/bin" }.count == 1)
        #expect(path.contains("/usr/bin"))
        #expect(path.contains("/bin"))
        #expect(env["PYTHONUNBUFFERED"] == "1")
    }

    @Test("Environment works without a login shell PATH")
    func environmentWithoutLoginShell() {
        let env = ExecutableLocator.environment(
            executablePath: "/usr/local/bin/ocrmypdf",
            loginShellPATH: nil,
            home: "/Users/someone",
            base: [:]
        )
        let path = env["PATH"] ?? ""
        #expect(path.hasPrefix("/usr/local/bin"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/Users/someone/.local/bin"))
    }
}
