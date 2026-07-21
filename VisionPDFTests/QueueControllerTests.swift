import Foundation
import Testing
@testable import VisionPDF

/// Drives the queue with a mocked process runner and real temp files.
@MainActor
@Suite("QueueController")
struct QueueControllerTests {
    private let toolInfo = ToolInfo(
        executablePath: "/fake/ocrmypdf",
        version: "17.8.1",
        appleVisionAvailable: true,
        searchPATH: "/usr/bin"
    )

    /// Creates a temp directory with the given (tiny, fake) PDF files.
    private func makeTempPDFs(_ names: [String]) throws -> (dir: URL, files: [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VisionPDFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [URL] = []
        for name in names {
            let url = dir.appendingPathComponent(name)
            try Data("%PDF-1.4 fake".utf8).write(to: url)
            files.append(url)
        }
        return (dir, files)
    }

    @Test("Only PDFs are added and duplicates are ignored")
    func addFiltering() throws {
        let (dir, files) = try makeTempPDFs(["a.pdf", "b.PDF"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let notPDF = dir.appendingPathComponent("c.txt")

        let queue = QueueController()
        let added = queue.add(urls: [files[0], files[1], notPDF, files[0]])
        #expect(added == 2)
        #expect(queue.items.count == 2)
    }

    @Test("A successful run marks the item succeeded with its output URL")
    func successFlow() async throws {
        let (dir, files) = try makeTempPDFs(["Document.pdf"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = MockProcessRunner(scripts: [
            .init(
                result: .exit(0),
                lines: [
                    OutputLine(kind: .stderr, text: "Starting processing with 3 workers concurrently"),
                    OutputLine(kind: .stderr, text: "Postprocessing..."),
                ]
            ),
        ])
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: files)

        var settings = OCRSettings()
        settings.engine = .appleVision
        queue.start(settings: settings, toolInfo: toolInfo)
        await queue.awaitCompletion()

        #expect(queue.items[0].status == .succeeded)
        #expect(queue.items[0].outputURL?.lastPathComponent == "Document OCR.pdf")
        #expect(queue.globalLog.contains("Starting processing"))

        // Engine-specific arguments went to the runner.
        let invocation = try #require(runner.invocations.first)
        #expect(invocation.executablePath == "/fake/ocrmypdf")
        #expect(invocation.arguments.starts(with: ["--plugin", "ocrmypdf_appleocr"]))
        #expect(invocation.arguments.last == dir.appendingPathComponent("Document OCR.pdf").path)
    }

    @Test("A failed file stops the batch when continue-after-errors is off")
    func stopOnError() async throws {
        let (dir, files) = try makeTempPDFs(["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(6, stderr: "page already has text!")),
        ])
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: files)

        var settings = OCRSettings()
        settings.continueAfterErrors = false
        queue.start(settings: settings, toolInfo: toolInfo)
        await queue.awaitCompletion()

        #expect(queue.items[0].status == .failed(message: "Already has text", exitCode: 6))
        #expect(queue.items[1].status == .skipped)
        #expect(runner.invocations.count == 1)
    }

    @Test("Continue-after-errors processes the whole queue")
    func continueOnError() async throws {
        let (dir, files) = try makeTempPDFs(["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(2)),
            .init(result: .exit(0)),
        ])
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: files)

        var settings = OCRSettings()
        settings.continueAfterErrors = true
        queue.start(settings: settings, toolInfo: toolInfo)
        await queue.awaitCompletion()

        #expect(queue.items[0].status == .failed(message: "Unsupported or corrupt PDF", exitCode: 2))
        #expect(queue.items[1].status == .succeeded)
        #expect(runner.invocations.count == 2)
    }

    @Test("Missing input file fails validation without launching a process")
    func validationFailure() async throws {
        let (dir, files) = try makeTempPDFs(["a.pdf"])
        let queue = QueueController()
        let runner = MockProcessRunner()
        queue.processRunner = runner
        queue.add(urls: files)
        try FileManager.default.removeItem(at: dir)  // pull the rug

        queue.start(settings: OCRSettings(), toolInfo: toolInfo)
        await queue.awaitCompletion()

        #expect(queue.items[0].status == .failed(message: "Not started", exitCode: nil))
        #expect(runner.invocations.isEmpty)
        #expect(queue.items[0].log.contains("no longer exists"))
    }

    @Test("Existing output is refused unless overwriting is allowed")
    func overwriteGuard() async throws {
        let (dir, files) = try makeTempPDFs(["Document.pdf", "Document OCR.pdf"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = MockProcessRunner()
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: [files[0]])

        var settings = OCRSettings()
        settings.allowOverwrite = false
        queue.start(settings: settings, toolInfo: toolInfo)
        await queue.awaitCompletion()

        #expect(queue.items[0].status == .failed(message: "Not started", exitCode: nil))
        #expect(queue.items[0].log.contains("already exists"))
        #expect(runner.invocations.isEmpty)
    }

    @Test("Duplicate basenames into one folder get numbered outputs")
    func duplicateOutputs() async throws {
        let (dirA, filesA) = try makeTempPDFs(["Report.pdf"])
        let (dirB, filesB) = try makeTempPDFs(["Report.pdf"])
        let (outDir, _) = try makeTempPDFs([])
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
            try? FileManager.default.removeItem(at: outDir)
        }

        let runner = MockProcessRunner()
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: [filesA[0], filesB[0]])

        var settings = OCRSettings()
        settings.outputMode = .selectedFolder
        settings.outputFolder = outDir
        queue.start(settings: settings, toolInfo: toolInfo)
        await queue.awaitCompletion()

        let outputs = runner.invocations.compactMap(\.arguments.last)
        #expect(outputs.count == 2)
        #expect(outputs[0].hasSuffix("/Report OCR.pdf"))
        #expect(outputs[1].hasSuffix("/Report OCR 2.pdf"))
    }

    @Test("Cancellation marks the running item cancelled", .timeLimit(.minutes(1)))
    func cancellation() async throws {
        let (dir, files) = try makeTempPDFs(["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(0), delay: .seconds(30)),
        ])
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: files)

        queue.start(settings: OCRSettings(), toolInfo: toolInfo)
        // Give the first run a moment to start, then cancel.
        try await Task.sleep(for: .milliseconds(200))
        queue.cancel()
        await queue.awaitCompletion()

        #expect(queue.items[0].status == .cancelled)
        #expect(queue.items[1].status == .skipped)
        #expect(!queue.isProcessing)
    }

    @Test("A runner that throws marks the item failed and stops the batch")
    func launchFailureFlow() async throws {
        let (dir, files) = try makeTempPDFs(["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = MockProcessRunner(scripts: [
            .init(result: .exit(0), error: .launchFailed("No such file or directory")),
        ])
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: files)

        var settings = OCRSettings()
        settings.continueAfterErrors = false
        queue.start(settings: settings, toolInfo: toolInfo)
        await queue.awaitCompletion()

        #expect(queue.items[0].status == .failed(message: "Could not launch OCRmyPDF", exitCode: nil))
        #expect(queue.items[0].log.contains("No such file or directory"))
        #expect(queue.items[1].status == .skipped)
        #expect(!queue.isProcessing)
    }

    @Test("Stage events from stderr update the running item")
    func stageTracking() async throws {
        let (dir, files) = try makeTempPDFs(["a.pdf"])
        defer { try? FileManager.default.removeItem(at: dir) }

        let runner = MockProcessRunner(scripts: [
            .init(
                result: .exit(0),
                lines: [OutputLine(kind: .stderr, text: "Parsing 12 pages with HocrParser")]
            ),
        ])
        let queue = QueueController()
        queue.processRunner = runner
        queue.add(urls: files)

        queue.start(settings: OCRSettings(), toolInfo: toolInfo)
        await queue.awaitCompletion()

        #expect(queue.items[0].pageCount == 12)
    }
}
