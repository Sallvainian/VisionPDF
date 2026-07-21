import Foundation

/// Builds the OCRmyPDF argument array from user settings.
///
/// Arguments are produced as a structured `[String]` and handed straight to
/// `Process` — never concatenated into a shell string — so paths containing
/// spaces, quotes, parentheses, brackets, apostrophes, or any other shell
/// metacharacter are passed through byte-for-byte without quoting.
enum CommandBuilder {
    /// Builds the full argument array for one input/output pair.
    static func arguments(
        inputPath: String,
        outputPath: String,
        settings: OCRSettings
    ) -> [String] {
        var args: [String] = []

        if settings.engine == .appleVision {
            args += ["--plugin", ToolDetector.pluginName]
        }

        // Language. Emitted as one `-l` per code: the Apple Vision plugin
        // rejects Tesseract-style `eng+spa` combinations, while both engines
        // accept repeated `-l` flags.
        var recognitionMode = settings.appleRecognitionMode
        let codes = effectiveLanguageCodes(settings: settings)
        if codes.contains("und") {
            // Undetermined-language detection ("und") is an Apple Vision
            // feature that Live Text mode rejects — even mixed in with other
            // codes via a custom entry like "eng+und" — so fall back to
            // "accurate", which supports it.
            if !recognitionMode.supportsAutomaticLanguage {
                recognitionMode = .accurate
            }
        }
        for code in codes {
            args += ["-l", code]
        }

        // Apple Vision plugin options are only valid when the plugin is loaded.
        if settings.engine == .appleVision {
            if let mode = recognitionMode.argumentValue {
                args += ["--appleocr-recognition-mode", mode]
            }
            if settings.appleDisableCorrection {
                args += ["--appleocr-disable-correction"]
            }
        }

        // Page correction
        if settings.rotatePages { args += ["--rotate-pages"] }
        if settings.deskew { args += ["--deskew"] }
        if settings.cleanPages { args += ["--clean"] }
        if settings.removeBackground { args += ["--remove-background"] }

        // Existing-text handling (mutually exclusive by construction).
        args += [settings.textHandling.argument]

        // Performance. Only non-default values are emitted so the command stays
        // minimal and OCRmyPDF's own defaults keep applying.
        if let jobs = settings.jobs, jobs > 0 {
            args += ["--jobs", String(jobs)]
        }
        if settings.optimizeLevel != 1, (0...3).contains(settings.optimizeLevel) {
            args += ["--optimize", String(settings.optimizeLevel)]
        }
        if let dpi = settings.oversampleDPI, dpi > 0 {
            args += ["--oversample", String(dpi)]
        }

        args += [inputPath, outputPath]
        return args
    }

    /// The language codes that will actually be emitted, after engine
    /// constraints are applied. Automatic detection is Apple Vision-only; if it
    /// is somehow requested with Tesseract, the `-l` flag is omitted entirely
    /// and OCRmyPDF falls back to its own default (English).
    static func effectiveLanguageCodes(settings: OCRSettings) -> [String] {
        guard settings.language.isSupported(by: settings.engine) else { return [] }
        return settings.language.languageCodes(custom: settings.customLanguage)
    }

    /// A human-readable rendering of the command for the "show command" UI.
    /// Quoting here is for display only — execution always uses the structured
    /// argument array above.
    static func displayCommand(executablePath: String, arguments: [String]) -> String {
        ([executablePath] + arguments)
            .map { shellQuoted($0) }
            .joined(separator: " ")
    }

    private static func shellQuoted(_ argument: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_./=+:@%,"))
        // A leading "=" or "~" is expanded by zsh even without other special
        // characters, so such arguments are quoted despite the safe set.
        if !argument.isEmpty,
           !argument.hasPrefix("="), !argument.hasPrefix("~"),
           argument.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
