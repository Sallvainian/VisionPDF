import Foundation

/// Result of probing the OCRmyPDF installation and the Apple Vision plugin.
enum ToolStatus: Equatable, Sendable {
    case unknown
    case checking
    /// No usable `ocrmypdf` executable was found anywhere.
    case ocrmypdfMissing
    /// OCRmyPDF works but `--plugin ocrmypdf_appleocr` failed to load.
    case pluginUnavailable(version: String, reason: String)
    /// OCRmyPDF works and the Apple Vision plugin loaded successfully.
    case fullyAvailable(version: String)
    /// A probe itself misbehaved (timeout, launch failure, unparseable output).
    case detectionFailed(String)

    var ocrmypdfVersion: String? {
        switch self {
        case .pluginUnavailable(let version, _), .fullyAvailable(let version):
            version
        default:
            nil
        }
    }

    /// OCRmyPDF itself is runnable, regardless of plugin state.
    var isOCRmyPDFAvailable: Bool {
        switch self {
        case .pluginUnavailable, .fullyAvailable: true
        default: false
        }
    }

    var isAppleVisionAvailable: Bool {
        if case .fullyAvailable = self { return true }
        return false
    }

    /// Short label for the status header.
    var appleVisionLabel: String {
        switch self {
        case .unknown, .checking: "Checking…"
        case .ocrmypdfMissing: "OCRmyPDF unavailable"
        case .pluginUnavailable: "Apple Vision OCR unavailable"
        case .fullyAvailable: "Apple Vision OCR available"
        case .detectionFailed: "Detection failed"
        }
    }
}

/// A fully resolved, ready-to-run OCRmyPDF installation.
struct ToolInfo: Equatable, Sendable {
    var executablePath: String
    var version: String
    var appleVisionAvailable: Bool
    /// PATH captured from a login shell, so OCRmyPDF's own subprocesses
    /// (tesseract, gs, unpaper) resolve the same way they do in Terminal.
    var searchPATH: String
}
