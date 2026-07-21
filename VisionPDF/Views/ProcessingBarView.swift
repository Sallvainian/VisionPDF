import SwiftUI

/// Bottom bar: start/cancel, overall progress, current file and stage, elapsed
/// time, and the logs toggle.
struct ProcessingBarView: View {
    @Environment(AppModel.self) private var model
    @Binding var showLogs: Bool

    var body: some View {
        HStack(spacing: 14) {
            if model.queue.isProcessing {
                Button(role: .cancel) {
                    model.queue.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)
                .help("Stop the current file and skip the rest (⌘.)")
            } else {
                Button {
                    model.startProcessing()
                } label: {
                    Label("Start OCR", systemImage: "play.fill")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canStartProcessing)
                .help(startHelp)

                if model.queue.items.contains(where: { $0.status.isFinished }) {
                    Button {
                        model.queue.resetFinished()
                    } label: {
                        Label("Run Again", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.large)
                    .help("Reset finished files so the batch can run again")
                }
            }

            statusColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showLogs.toggle()
            } label: {
                Label("Logs", systemImage: showLogs ? "chevron.down" : "chevron.up")
            }
            .help(showLogs ? "Hide the log panel" : "Show the log panel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var statusColumn: some View {
        if model.queue.isProcessing {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let position = model.queue.queuePosition {
                        Text("File \(position.current) of \(position.total)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let item = model.queue.currentItem {
                        Text(item.fileName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("· \(item.stage ?? "Processing…")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    elapsedText
                }
                ProgressView(value: model.queue.overallProgress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
        } else {
            summaryText
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var elapsedText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let started = model.queue.batchStartedAt {
                Text(Self.elapsedFormatter.string(from: Date().timeIntervalSince(started)) ?? "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryText: Text {
        let items = model.queue.items
        if items.isEmpty {
            return Text("Add PDFs to get started.")
        }
        let done = items.filter { $0.status == .succeeded }.count
        let failed = items.filter {
            if case .failed = $0.status { return true } else { return false }
        }.count
        if done + failed > 0 {
            var parts: [String] = []
            if done > 0 { parts.append("\(done) finished") }
            if failed > 0 { parts.append("\(failed) failed") }
            return Text(parts.joined(separator: " · "))
        }
        return Text("\(items.count) file\(items.count == 1 ? "" : "s") ready.")
    }

    private var startHelp: String {
        if model.toolInfo == nil {
            return "OCRmyPDF is not available — check Settings."
        }
        if model.queue.pendingCount == 0 {
            return "Add PDF files to the queue first."
        }
        if model.settings.outputMode == .selectedFolder && model.settings.outputFolder == nil {
            return "Choose an output folder in Options first."
        }
        return "Run OCR on all waiting files (⌘R)"
    }

    private static let elapsedFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter
    }()
}

#Preview {
    ProcessingBarView(showLogs: .constant(false))
        .environment(AppModel())
        .frame(width: 800)
}
