import Foundation

/// The document-language selection offered in the UI.
///
/// Both engines are driven through OCRmyPDF's `-l` flag using ISO 639-2 codes
/// (`eng`, `spa`, …). The Apple Vision plugin maps those codes to Apple locale
/// identifiers internally, but it rejects Tesseract-style `eng+spa` combinations
/// inside a single `-l` value, so multiple languages are always emitted as
/// separate `-l` arguments — a form both engines accept.
enum LanguageChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Apple Vision only: pass `-l und` for undetermined-language detection.
    case automatic
    case english
    case spanish
    case englishSpanish
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic (Apple Vision)"
        case .english: "English"
        case .spanish: "Spanish"
        case .englishSpanish: "English + Spanish"
        case .custom: "Custom…"
        }
    }

    /// Whether this choice can be used with the given engine.
    func isSupported(by engine: OCREngine) -> Bool {
        if self == .automatic { return engine == .appleVision }
        return true
    }

    /// Resolves the ISO 639-2 codes to emit as separate `-l` arguments.
    ///
    /// For `.custom`, the user's text is split on `+`, commas, and whitespace so
    /// that habits from both engines ("eng+deu", "eng, deu") work unchanged.
    /// Returns an empty array when nothing usable was entered, in which case the
    /// `-l` flag is omitted and OCRmyPDF applies its own default (English).
    func languageCodes(custom: String) -> [String] {
        switch self {
        case .automatic:
            return ["und"]
        case .english:
            return ["eng"]
        case .spanish:
            return ["spa"]
        case .englishSpanish:
            return ["eng", "spa"]
        case .custom:
            let separators = CharacterSet(charactersIn: "+, \t")
            return custom
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}
