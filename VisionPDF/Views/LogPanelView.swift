import SwiftUI
import UniformTypeIdentifiers

/// Collapsible log panel: live process output, diagnostics summary, and
/// copy / clear / save actions.
struct LogPanelView: View {
    @Environment(AppModel.self) private var model

    @State private var showDiagnostics = false
    @State private var showSaveDialog = false
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Logs", systemImage: "terminal")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("Diagnostics", isOn: $showDiagnostics)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Show environment and last-run diagnostics")

                Button {
                    copyLogs()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy all log output to the clipboard")

                Button {
                    showSaveDialog = true
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .help("Save the logs to a text file")

                Button {
                    model.queue.clearLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .controlSize(.small)
                .help("Clear the log panel")
                .disabled(model.queue.globalLog.isEmpty)
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    // One Text per line inside a LazyVStack: appending a line
                    // lays out only the new row instead of re-measuring the
                    // whole (potentially multi-thousand-line) transcript.
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if showDiagnostics {
                            Text(model.diagnosticsText)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                        }
                        if model.queue.logLines.isEmpty {
                            Text("No output yet.")
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(Array(model.queue.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("logEnd")
                    }
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                }
                .background(.background.secondary)
                .onChange(of: model.queue.logLines.count) {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
        }
        .fileExporter(
            isPresented: $showSaveDialog,
            document: LogDocument(text: exportText),
            contentType: .plainText,
            defaultFilename: "VisionPDF Log"
        ) { _ in }
    }

    private var exportText: String {
        model.diagnosticsText + "\n\n── Log ──\n" + model.queue.globalLog
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportText, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}

/// Minimal plain-text document wrapper for the log save dialog.
struct LogDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#Preview {
    LogPanelView()
        .environment(AppModel())
        .frame(width: 800, height: 240)
}
