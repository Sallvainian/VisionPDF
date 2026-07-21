import Foundation
import Testing
@testable import VisionPDF

@Suite("CommandBuilder")
struct CommandBuilderTests {
    private func args(_ settings: OCRSettings, input: String = "/in/a.pdf", output: String = "/out/a OCR.pdf") -> [String] {
        CommandBuilder.arguments(inputPath: input, outputPath: output, settings: settings)
    }

    // MARK: Engine selection

    @Test("Apple Vision adds the plugin flag")
    func appleVisionPlugin() {
        var settings = OCRSettings()
        settings.engine = .appleVision
        let arguments = args(settings)
        #expect(arguments.starts(with: ["--plugin", "ocrmypdf_appleocr"]))
    }

    @Test("Tesseract omits the plugin flag and all appleocr options")
    func tesseractNoPlugin() {
        var settings = OCRSettings()
        settings.engine = .tesseract
        settings.appleDisableCorrection = true
        settings.appleRecognitionMode = .fast
        let arguments = args(settings)
        #expect(!arguments.contains("--plugin"))
        #expect(!arguments.contains("ocrmypdf_appleocr"))
        #expect(!arguments.contains { $0.hasPrefix("--appleocr") })
    }

    // MARK: Languages

    @Test("Single languages map to one -l flag")
    func singleLanguage() {
        var settings = OCRSettings()
        settings.language = .english
        #expect(pairs(args(settings), flag: "-l") == ["eng"])

        settings.language = .spanish
        #expect(pairs(args(settings), flag: "-l") == ["spa"])
    }

    @Test("English + Spanish becomes two separate -l flags, never eng+spa")
    func multipleLanguages() {
        var settings = OCRSettings()
        settings.language = .englishSpanish
        let arguments = args(settings)
        #expect(pairs(arguments, flag: "-l") == ["eng", "spa"])
        #expect(!arguments.contains("eng+spa"))
    }

    @Test("Custom languages split on plus, comma, and whitespace")
    func customLanguageSplitting() {
        var settings = OCRSettings()
        settings.language = .custom
        settings.customLanguage = "eng+deu, fra"
        #expect(pairs(args(settings), flag: "-l") == ["eng", "deu", "fra"])
    }

    @Test("Automatic language uses und and forces a compatible recognition mode")
    func automaticLanguage() {
        var settings = OCRSettings()
        settings.engine = .appleVision
        settings.language = .automatic
        settings.appleRecognitionMode = .pluginDefault
        let arguments = args(settings)
        #expect(pairs(arguments, flag: "-l") == ["und"])
        // Live Text (the plugin default) rejects und; accurate supports it.
        #expect(pairs(arguments, flag: "--appleocr-recognition-mode") == ["accurate"])
    }

    @Test("Automatic language keeps an explicitly compatible mode")
    func automaticLanguageKeepsFastMode() {
        var settings = OCRSettings()
        settings.engine = .appleVision
        settings.language = .automatic
        settings.appleRecognitionMode = .fast
        #expect(pairs(args(settings), flag: "--appleocr-recognition-mode") == ["fast"])
    }

    @Test("Apple Vision options are emitted when enabled")
    func appleOptionsEmitted() {
        var settings = OCRSettings()
        settings.engine = .appleVision
        settings.appleDisableCorrection = true
        settings.appleRecognitionMode = .livetext
        let arguments = args(settings)
        #expect(arguments.contains("--appleocr-disable-correction"))
        #expect(pairs(arguments, flag: "--appleocr-recognition-mode") == ["livetext"])
    }

    @Test("A custom code list containing und also forces a compatible mode")
    func mixedUndCoercion() {
        var settings = OCRSettings()
        settings.engine = .appleVision
        settings.language = .custom
        settings.customLanguage = "eng+und"
        settings.appleRecognitionMode = .livetext
        let arguments = args(settings)
        #expect(pairs(arguments, flag: "-l") == ["eng", "und"])
        #expect(pairs(arguments, flag: "--appleocr-recognition-mode") == ["accurate"])
    }

    @Test("Automatic language with Tesseract omits -l entirely")
    func automaticWithTesseract() {
        var settings = OCRSettings()
        settings.engine = .tesseract
        settings.language = .automatic
        #expect(!args(settings).contains("-l"))
    }

    // MARK: Option flags

    @Test("Page correction flags appear only when enabled")
    func correctionFlags() {
        var settings = OCRSettings()
        settings.rotatePages = true
        settings.deskew = true
        settings.cleanPages = true
        settings.removeBackground = true
        let arguments = args(settings)
        #expect(arguments.contains("--rotate-pages"))
        #expect(arguments.contains("--deskew"))
        #expect(arguments.contains("--clean"))
        #expect(arguments.contains("--remove-background"))

        let off = args(OCRSettings())
        #expect(!off.contains("--rotate-pages"))
        #expect(!off.contains("--deskew"))
        #expect(!off.contains("--clean"))
        #expect(!off.contains("--remove-background"))
    }

    @Test("Text handling choices are mutually exclusive", arguments: TextHandling.allCases)
    func textHandling(_ handling: TextHandling) {
        var settings = OCRSettings()
        settings.textHandling = handling
        let arguments = args(settings)
        let related = ["--skip-text", "--redo-ocr", "--force-ocr"]
        #expect(arguments.filter { related.contains($0) } == [handling.argument])
    }

    @Test("Performance options emit only non-defaults")
    func performanceOptions() {
        var settings = OCRSettings()
        settings.jobs = 4
        settings.optimizeLevel = 2
        settings.oversampleDPI = 300
        let arguments = args(settings)
        #expect(pairs(arguments, flag: "--jobs") == ["4"])
        #expect(pairs(arguments, flag: "--optimize") == ["2"])
        #expect(pairs(arguments, flag: "--oversample") == ["300"])

        let defaults = args(OCRSettings())
        #expect(!defaults.contains("--jobs"))
        #expect(!defaults.contains("--optimize"))
        #expect(!defaults.contains("--oversample"))
    }

    // MARK: Paths with hostile characters

    @Test(
        "Paths pass through verbatim regardless of shell metacharacters",
        arguments: [
            "/Users/me/My Documents/Report (final).pdf",
            "/tmp/bracket [v2].pdf",
            "/tmp/it's a scan.pdf",
            "/tmp/quote \" dollar $HOME; rm -rf.pdf",
            "/tmp/tick ` and && pipe |.pdf",
        ]
    )
    func hostilePaths(_ path: String) {
        let arguments = args(OCRSettings(), input: path, output: path + " OCR.pdf")
        // The exact byte-for-byte path must be the second-to-last argument.
        #expect(arguments[arguments.count - 2] == path)
        #expect(arguments.last == path + " OCR.pdf")
    }

    @Test("Input comes before output as the final two arguments")
    func argumentOrder() {
        let arguments = args(OCRSettings(), input: "/a/in.pdf", output: "/b/out.pdf")
        #expect(Array(arguments.suffix(2)) == ["/a/in.pdf", "/b/out.pdf"])
    }

    // MARK: Display command

    @Test("Display command quotes arguments that need it, for display only")
    func displayQuoting() {
        let display = CommandBuilder.displayCommand(
            executablePath: "/usr/local/bin/ocrmypdf",
            arguments: ["--skip-text", "/tmp/My File (1).pdf"]
        )
        #expect(display == "/usr/local/bin/ocrmypdf --skip-text '/tmp/My File (1).pdf'")
    }

    @Test("Display command escapes embedded single quotes")
    func displayApostrophe() {
        let display = CommandBuilder.displayCommand(
            executablePath: "ocrmypdf",
            arguments: ["/tmp/it's.pdf"]
        )
        #expect(display == "ocrmypdf '/tmp/it'\\''s.pdf'")
    }

    @Test("Display command quotes leading = and ~, which zsh would expand")
    func displayZshExpansions() {
        let display = CommandBuilder.displayCommand(
            executablePath: "ocrmypdf",
            arguments: ["-l", "=eng", "~backup.pdf"]
        )
        #expect(display == "ocrmypdf -l '=eng' '~backup.pdf'")
    }

    // MARK: Helpers

    /// Values following every occurrence of `flag`.
    private func pairs(_ arguments: [String], flag: String) -> [String] {
        var values: [String] = []
        for (index, argument) in arguments.enumerated()
        where argument == flag && index + 1 < arguments.count {
            values.append(arguments[index + 1])
        }
        return values
    }
}
