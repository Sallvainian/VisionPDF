import Foundation

/// How pages that already contain text are handled. The three OCRmyPDF flags
/// are mutually exclusive.
enum TextHandling: String, CaseIterable, Codable, Sendable, Identifiable {
    /// `--skip-text`: OCR only pages without text, keep the rest untouched.
    case skipText
    /// `--redo-ocr`: replace a previous OCR text layer, keep real text.
    case redoOCR
    /// `--force-ocr`: rasterize every page and OCR it. Destructive.
    case forceOCR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skipText: "Skip pages with text"
        case .redoOCR: "Redo existing OCR"
        case .forceOCR: "Force OCR on every page"
        }
    }

    var argument: String {
        switch self {
        case .skipText: "--skip-text"
        case .redoOCR: "--redo-ocr"
        case .forceOCR: "--force-ocr"
        }
    }

    var help: String {
        switch self {
        case .skipText:
            "Pages that already contain text are copied through unchanged. Safest option."
        case .redoOCR:
            "Replaces text layers created by a previous OCR run while keeping born-digital text."
        case .forceOCR:
            "Rasterizes every page to an image before OCR. This removes original selectable text, links, and vector content from the output."
        }
    }
}

/// Where the finished PDFs are written.
enum OutputMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case besideOriginal
    case selectedFolder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .besideOriginal: "Beside the original"
        case .selectedFolder: "In a selected folder"
        }
    }
}

/// Everything the user can configure for a processing run. A pure value type so
/// that command construction is deterministic and easy to test.
struct OCRSettings: Equatable, Codable, Sendable {
    var engine: OCREngine = .appleVision
    var language: LanguageChoice = .english
    var customLanguage: String = ""

    // Page correction
    var rotatePages = false
    var deskew = false
    var cleanPages = false
    var removeBackground = false

    var textHandling: TextHandling = .skipText

    // Apple Vision plugin options
    var appleRecognitionMode: AppleRecognitionMode = .pluginDefault
    var appleDisableCorrection = false

    // Performance. `nil` means "let OCRmyPDF decide".
    var jobs: Int?
    /// `--optimize` level 0–3. 1 is OCRmyPDF's default, so it is only emitted
    /// when different.
    var optimizeLevel = 1
    /// `--oversample DPI`; nil disables oversampling.
    var oversampleDPI: Int?

    // Output
    var outputMode: OutputMode = .besideOriginal
    var outputFolder: URL?
    var suffix = "OCR"
    var allowOverwrite = false
    var continueAfterErrors = false
}
