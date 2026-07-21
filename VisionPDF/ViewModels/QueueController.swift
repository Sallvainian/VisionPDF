import Foundation
import Observation
import PDFKit

/// Owns the file queue and drives sequential OCR processing.
@MainActor
@Observable
final class QueueController {
    private(set) var items: [QueueItem] = []
    private(set) var isProcessing = false
    private(set) var currentItemID: UUID?
    private(set) var batchStartedAt: Date?

    /// Combined transcript of all runs, kept as discrete lines so the log
    /// panel can lay out lazily instead of re-rendering one giant string on
    /// every appended line.
    private(set) var logLines: [String] = []
    /// Arguments of the most recent run, for diagnostics.
    private(set) var lastArguments: [String]?
    private(set) var lastExitCode: Int32?

    var processRunner: any ProcessRunning = ProcessRunner()

    private var processingTask: Task<Void, Never>?
    private static let logLineLimit = 4000

    /// Full transcript, joined on demand (Copy/Save and tests).
    var globalLog: String {
        logLines.joined(separator: "\n")
    }

    // MARK: - Queue management

    /// Adds PDFs, ignoring non-PDF files and paths already in the queue.
    /// Returns the number actually added.
    @discardableResult
    func add(urls: [URL]) -> Int {
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        var added = 0
        var seen = existing
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            items.append(QueueItem(url: url))
            added += 1
        }
        return added
    }

    func remove(_ item: QueueItem) {
        guard item.id != currentItemID else { return }
        items.removeAll { $0.id == item.id }
    }

    func clearQueue() {
        guard !isProcessing else { return }
        items.removeAll()
    }

    /// Resets finished items back to waiting so the batch can run again.
    func resetFinished() {
        guard !isProcessing else { return }
        for index in items.indices where items[index].status.isFinished {
            items[index].status = .waiting
            items[index].stage = nil
            items[index].outputURL = nil
            items[index].startedAt = nil
            items[index].finishedAt = nil
            items[index].log = ""
        }
    }

    var pendingCount: Int {
        items.filter { $0.status == .waiting }.count
    }

    /// Determinate queue-level progress: finished files over total files in
    /// this batch. Per-file progress stays indeterminate because OCRmyPDF does
    /// not report reliable percentages through a pipe.
    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        let finished = items.filter { $0.status.isFinished }.count
        return Double(finished) / Double(items.count)
    }

    /// 1-based position of the running file, e.g. (2, 5) for "file 2 of 5".
    var queuePosition: (current: Int, total: Int)? {
        guard let currentItemID,
              let index = items.firstIndex(where: { $0.id == currentItemID })
        else { return nil }
        return (index + 1, items.count)
    }

    var currentItem: QueueItem? {
        guard let currentItemID else { return nil }
        return items.first { $0.id == currentItemID }
    }

    // MARK: - Processing

    func start(settings: OCRSettings, toolInfo: ToolInfo) {
        guard !isProcessing, pendingCount > 0 else { return }
        isProcessing = true
        batchStartedAt = Date()
        processingTask = Task { [weak self] in
            await self?.processQueue(settings: settings, toolInfo: toolInfo)
            self?.isProcessing = false
            self?.currentItemID = nil
            self?.processingTask = nil
        }
    }

    func cancel() {
        processingTask?.cancel()
    }

    /// Awaits the end of the current batch (used by tests).
    func awaitCompletion() async {
        await processingTask?.value
    }

    private func processQueue(settings: OCRSettings, toolInfo: ToolInfo) async {
        var takenOutputs = Set<String>()
        var abortRemaining = false

        for id in items.map(\.id) {
            guard let index = items.firstIndex(where: { $0.id == id }),
                  items[index].status == .waiting else { continue }

            if Task.isCancelled || abortRemaining {
                items[index].status = .skipped
                continue
            }

            let input = items[index].url
            let proposed = OutputNaming.outputURL(
                for: input,
                mode: settings.outputMode,
                folder: settings.outputFolder,
                suffix: settings.suffix
            )
            let output = OutputNaming.uniquifiedURL(proposed, taken: takenOutputs)
            takenOutputs.insert(output.standardizedFileURL.path)

            currentItemID = id
            items[index].status = .running
            items[index].startedAt = Date()
            items[index].stage = "Preparing"

            // `index` is stale after any suspension — the user can remove
            // other queue rows while the main actor is free — so re-resolve
            // by id after the await (and bail if this item was removed).
            let pageCount = await Self.pageCount(of: input)
            guard let resumedIndex = items.firstIndex(where: { $0.id == id }) else { continue }
            items[resumedIndex].pageCount = pageCount

            do {
                try OutputNaming.validate(
                    input: input,
                    output: output,
                    allowOverwrite: settings.allowOverwrite
                )
            } catch {
                finishItem(
                    id: id,
                    status: .failed(message: "Not started", exitCode: nil),
                    detail: error.localizedDescription
                )
                if !settings.continueAfterErrors { abortRemaining = true }
                continue
            }

            let arguments = CommandBuilder.arguments(
                inputPath: input.standardizedFileURL.path,
                outputPath: output.standardizedFileURL.path,
                settings: settings
            )
            lastArguments = arguments
            appendLog(
                "\n$ " + CommandBuilder.displayCommand(
                    executablePath: toolInfo.executablePath,
                    arguments: arguments
                ) + "\n",
                itemID: id
            )

            let environment = ExecutableLocator.environment(
                executablePath: toolInfo.executablePath,
                loginShellPATH: toolInfo.searchPATH.isEmpty ? nil : toolInfo.searchPATH
            )

            // Funnel output lines through an ordered stream back to the main
            // actor; the runner's callback fires on a background queue.
            let (stream, continuation) = AsyncStream.makeStream(of: OutputLine.self)
            let consumer = Task { [weak self] in
                for await line in stream {
                    self?.handleOutput(line, itemID: id)
                }
            }

            do {
                let result = try await processRunner.run(
                    executablePath: toolInfo.executablePath,
                    arguments: arguments,
                    environment: environment,
                    onLine: { continuation.yield($0) }
                )
                continuation.finish()
                await consumer.value
                lastExitCode = result.exitCode

                if result.wasCancelled {
                    finishItem(id: id, status: .cancelled, detail: "Processing was cancelled.")
                } else if result.exitCode == 0 {
                    finishItem(id: id, status: .succeeded, detail: nil, outputURL: output)
                } else {
                    finishItem(
                        id: id,
                        status: .failed(
                            message: OCRExitCode.shortLabel(for: result.exitCode),
                            exitCode: result.exitCode
                        ),
                        detail: OCRExitCode.explanation(for: result.exitCode)
                    )
                    if !settings.continueAfterErrors { abortRemaining = true }
                }
            } catch {
                continuation.finish()
                await consumer.value
                finishItem(
                    id: id,
                    status: .failed(message: "Could not launch OCRmyPDF", exitCode: nil),
                    detail: error.localizedDescription
                )
                if !settings.continueAfterErrors { abortRemaining = true }
            }

            if Task.isCancelled { abortRemaining = true }
        }
    }

    private func finishItem(
        id: UUID,
        status: QueueItem.Status,
        detail: String?,
        outputURL: URL? = nil
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
        items[index].stage = nil
        items[index].finishedAt = Date()
        items[index].outputURL = outputURL
        if let detail {
            appendLog(detail + "\n", itemID: id)
        }
        let name = items[index].fileName
        switch status {
        case .succeeded:
            appendLog("✓ Finished \(name)\n", itemID: nil)
        case .cancelled:
            appendLog("⨯ Cancelled \(name)\n", itemID: nil)
        case .failed:
            appendLog("✗ Failed \(name)\n", itemID: nil)
        default:
            break
        }
    }

    private func handleOutput(_ line: OutputLine, itemID: UUID) {
        appendLog(line.text + "\n", itemID: itemID)
        guard let event = ProgressParser.parse(line: line.text) else { return }
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        switch event {
        case .stage(let stage):
            if items[index].status == .running {
                items[index].stage = stage
            }
        case .pageCount(let count):
            items[index].pageCount = count
        case .warning:
            break  // Already visible in the log transcript.
        }
    }

    private func appendLog(_ text: String, itemID: UUID?) {
        logLines.append(contentsOf: text.split(separator: "\n").map(String.init))
        if logLines.count > Self.logLineLimit {
            logLines.removeFirst(logLines.count - Self.logLineLimit / 2)
        }
        if let itemID, let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].log += text
        }
    }

    func clearLog() {
        logLines.removeAll()
    }

    /// Reads the page count off the main actor; PDFKit opens the file lazily.
    private nonisolated static func pageCount(of url: URL) async -> Int? {
        let path = url.standardizedFileURL.path
        return await Task.detached(priority: .utility) {
            PDFDocument(url: URL(fileURLWithPath: path))?.pageCount
        }.value
    }
}
