import SwiftUI

/// Compact tool-status chip for the toolbar. The "Check Again" action lives in
/// its own toolbar item (see ContentView) so the system gives each its own
/// background — combined in one group, the refresh arrow lands on the shared
/// capsule's border.
struct StatusBadgeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // No custom capsule background: the toolbar already wraps each item in
        // its own chrome on modern macOS, and a second capsule underneath it
        // collides with that border.
        HStack(spacing: 5) {
            statusIcon
            Text(model.toolStatus.appleVisionLabel)
                .font(.callout)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .help(helpText)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.toolStatus {
        case .unknown, .checking:
            ProgressView()
                .controlSize(.mini)
        case .fullyAvailable:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .pluginUnavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case .ocrmypdfMissing, .detectionFailed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var helpText: String {
        switch model.toolStatus {
        case .unknown, .checking:
            return "Checking the OCRmyPDF installation…"
        case .fullyAvailable(let version):
            return "OCRmyPDF \(version) with the Apple Vision plugin is ready."
        case .pluginUnavailable(let version, let reason):
            return "OCRmyPDF \(version) works, but Apple Vision is unavailable: \(reason)"
        case .ocrmypdfMissing:
            return "No ocrmypdf executable was found. Set its location in Settings."
        case .detectionFailed(let reason):
            return "Detection failed: \(reason)"
        }
    }
}

#Preview {
    StatusBadgeView()
        .environment(AppModel())
        .padding()
}
