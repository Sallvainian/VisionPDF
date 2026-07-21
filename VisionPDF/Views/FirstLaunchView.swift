import SwiftUI

/// First-launch sheet: shows what was detected and how to proceed.
struct FirstLaunchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Welcome to VisionPDF")
                    .font(.title.weight(.semibold))
                Text("A front end for OCRmyPDF that makes scanned PDFs searchable.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                detectionRow(
                    ok: model.toolStatus.isOCRmyPDFAvailable,
                    pending: model.toolStatus == .checking || model.toolStatus == .unknown,
                    title: "OCRmyPDF",
                    detail: ocrmypdfDetail
                )
                detectionRow(
                    ok: model.toolStatus.isAppleVisionAvailable,
                    pending: model.toolStatus == .checking || model.toolStatus == .unknown,
                    title: "Apple Vision plugin",
                    detail: pluginDetail
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !model.toolStatus.isOCRmyPDFAvailable,
               model.toolStatus != .checking, model.toolStatus != .unknown {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OCRmyPDF needs to be installed separately — VisionPDF will not install it for you. One way, using uv:")
                        .font(.callout)
                    Text("uv tool install --with ocrmypdf-appleocr ocrmypdf")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    Text("Then click “Check Again” in the toolbar, or set the executable path in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Check Again") {
                    model.refreshDetection()
                }
                Spacer()
                Button("Get Started") {
                    model.hasCompletedFirstLaunch = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480)
    }

    private func detectionRow(ok: Bool, pending: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if pending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20)
            } else {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .red)
                    .font(.title3)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ocrmypdfDetail: String {
        switch model.toolStatus {
        case .unknown, .checking:
            "Looking in the standard install locations…"
        case .ocrmypdfMissing:
            "Not found in /usr/local/bin, /opt/homebrew/bin, ~/.local/bin, or your login-shell PATH."
        case .detectionFailed(let reason):
            reason
        case .pluginUnavailable(let version, _), .fullyAvailable(let version):
            "\(version) — \(model.toolInfo?.executablePath ?? "")"
        }
    }

    private var pluginDetail: String {
        switch model.toolStatus {
        case .unknown, .checking:
            "Waiting for OCRmyPDF detection…"
        case .fullyAvailable:
            "Apple Vision OCR is ready and selected as the default engine."
        case .pluginUnavailable(_, let reason):
            reason + " You can still OCR with Tesseract."
        case .ocrmypdfMissing, .detectionFailed:
            "Requires a working OCRmyPDF installation."
        }
    }
}

#Preview {
    FirstLaunchView()
        .environment(AppModel())
}
