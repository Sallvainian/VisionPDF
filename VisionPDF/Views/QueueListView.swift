import SwiftUI

/// The file queue.
struct QueueListView: View {
    @Environment(AppModel.self) private var model
    var isDropTargeted: Bool

    @State private var selection = Set<UUID>()

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(model.queue.items) { item in
                    QueueRowView(item: item)
                        .tag(item.id)
                }
            } header: {
                HStack {
                    Text("\(model.queue.items.count) file\(model.queue.items.count == 1 ? "" : "s")")
                    Spacer()
                    Text("Drop more PDFs anywhere to add them")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
        .listStyle(.inset)
        .onDeleteCommand {
            for id in selection {
                if let item = model.queue.items.first(where: { $0.id == id }) {
                    model.queue.remove(item)
                }
            }
            selection.removeAll()
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.06))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
                .padding(6)
                .allowsHitTesting(false)
            }
        }
    }
}

/// One row: file name, status, and per-file actions.
struct QueueRowView: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(item.statusLabel)
                        .foregroundStyle(subtitleColor)
                    if let detail = detailText {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(detail)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailingActions
        }
        .padding(.vertical, 5)
        .contextMenu {
            if let output = item.outputURL, item.status == .succeeded {
                Button("Open in Preview") {
                    Self.openInPreview(output)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }
                Divider()
            }
            Button("Show Original in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if item.status != .running {
                Divider()
                Button("Remove from Queue", role: .destructive) {
                    model.queue.remove(item)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch item.status {
        case .waiting:
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundStyle(.orange)
                .font(.title3)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }

    private var subtitleColor: Color {
        switch item.status {
        case .failed: .red
        case .cancelled: .orange
        default: .secondary
        }
    }

    private var detailText: String? {
        var parts: [String] = []
        if let pages = item.pageCount {
            parts.append("\(pages) page\(pages == 1 ? "" : "s")")
        }
        if let elapsed = item.elapsed, item.status.isFinished {
            parts.append(Self.durationFormatter.string(from: elapsed) ?? "")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailingActions: some View {
        switch item.status {
        case .succeeded:
            HStack(spacing: 4) {
                if let output = item.outputURL {
                    Button {
                        Self.openInPreview(output)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .help("Open the OCRed PDF in Preview")
                    .accessibilityLabel("Open in Preview")
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help("Show the OCRed PDF in Finder")
                    .accessibilityLabel("Show in Finder")
                }
            }
            .buttonStyle(.borderless)
        case .running:
            EmptyView()
        default:
            Button {
                model.queue.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
            .accessibilityLabel("Remove from queue")
        }
    }

    /// Opens the PDF in Preview specifically; NSWorkspace.open(_:) alone would
    /// use whatever app is the system-default PDF handler.
    static func openInPreview(_ url: URL) {
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: preview,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if error != nil {
                // Preview missing or refused — fall back to the default app.
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

#Preview {
    QueueListView(isDropTargeted: false)
        .environment(AppModel())
        .frame(width: 640, height: 400)
}
