import SwiftUI

/// Empty-state drop target shown when the queue has no files.
struct DropZoneView: View {
    var isTargeted: Bool
    var onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.document")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .symbolEffect(.bounce, value: isTargeted)

            VStack(spacing: 6) {
                Text("Drop PDFs Here")
                    .font(.title2.weight(.semibold))
                Text("Add scanned PDFs to make them searchable with OCR.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button(action: onBrowse) {
                Label("Choose Files…", systemImage: "folder")
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .padding(24)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone. Drop PDF files here or choose files.")
    }
}

#Preview("Idle") {
    DropZoneView(isTargeted: false) {}
        .frame(width: 600, height: 400)
}

#Preview("Targeted") {
    DropZoneView(isTargeted: true) {}
        .frame(width: 600, height: 400)
}
