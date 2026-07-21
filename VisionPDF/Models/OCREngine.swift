import Foundation

/// The OCR engine used by OCRmyPDF for text recognition.
enum OCREngine: String, CaseIterable, Codable, Sendable, Identifiable {
    case appleVision
    case tesseract

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleVision: "Apple Vision"
        case .tesseract: "Tesseract"
        }
    }

    var symbolName: String {
        switch self {
        case .appleVision: "eye"
        case .tesseract: "text.viewfinder"
        }
    }
}

/// Recognition mode for the Apple Vision plugin
/// (`--appleocr-recognition-mode {fast,accurate,livetext}`).
enum AppleRecognitionMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Let the plugin pick its own default (livetext on macOS 13+).
    case pluginDefault
    case fast
    case accurate
    case livetext

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pluginDefault: "Default (Live Text)"
        case .fast: "Fast"
        case .accurate: "Accurate"
        case .livetext: "Live Text"
        }
    }

    /// The value passed to `--appleocr-recognition-mode`, or nil to omit the flag.
    var argumentValue: String? {
        switch self {
        case .pluginDefault: nil
        case .fast: "fast"
        case .accurate: "accurate"
        case .livetext: "livetext"
        }
    }

    /// Live Text does not support undetermined-language (`-l und`) detection.
    var supportsAutomaticLanguage: Bool {
        switch self {
        case .fast, .accurate: true
        case .pluginDefault, .livetext: false
        }
    }
}
