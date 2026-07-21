import Foundation

/// One PDF in the processing queue.
struct QueueItem: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case running
        case succeeded
        case failed(message: String, exitCode: Int32?)
        case cancelled
        /// Not attempted because an earlier file failed and
        /// "Continue after errors" was off.
        case skipped

        var isFinished: Bool {
            switch self {
            case .succeeded, .failed, .cancelled, .skipped: true
            case .waiting, .running: false
            }
        }
    }

    let id: UUID
    let url: URL

    var status: Status = .waiting
    /// Human-readable stage ("Recognizing text", "Optimizing", …).
    var stage: String?
    /// Page count read from the PDF before processing, when available.
    var pageCount: Int?
    var outputURL: URL?
    var startedAt: Date?
    var finishedAt: Date?
    /// Per-file combined stdout/stderr transcript.
    var log = ""

    init(url: URL) {
        self.id = UUID()
        self.url = url
    }

    var fileName: String { url.lastPathComponent }

    var statusLabel: String {
        switch status {
        case .waiting: "Waiting"
        case .running: stage ?? "Processing…"
        case .succeeded: "Done"
        case .failed(let message, _): message
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        }
    }

    var elapsed: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}
