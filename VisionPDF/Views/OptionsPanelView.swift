import SwiftUI

/// Right-hand inspector: engine, language, output, and advanced OCR options.
struct OptionsPanelView: View {
    @Environment(AppModel.self) private var model

    @State private var showFolderPicker = false
    @State private var showAdvanced = false

    var body: some View {
        Form {
            engineSection
            languageSection
            outputSection
            correctionSection
            existingTextSection
            advancedSection
            commandPreviewSection
        }
        .formStyle(.grouped)
        .disabled(model.queue.isProcessing)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                model.settings.outputFolder = url
                model.settings.outputMode = .selectedFolder
            }
        }
    }

    // MARK: Engine

    private var engineSection: some View {
        Section("OCR Engine") {
            Picker("Engine", selection: engineBinding) {
                ForEach(OCREngine.allCases) { engine in
                    Label(engine.displayName, systemImage: engine.symbolName)
                        .tag(engine)
                        .selectionDisabled(
                            engine == .appleVision && !model.toolStatus.isAppleVisionAvailable
                        )
                }
            }
            .pickerStyle(.radioGroup)
            .help(
                model.toolStatus.isAppleVisionAvailable
                    ? "Apple Vision uses the ocrmypdf_appleocr plugin; Tesseract is OCRmyPDF's built-in default"
                    : (model.appleVisionUnavailableReason ?? "Apple Vision is unavailable.")
            )

            if !model.toolStatus.isAppleVisionAvailable {
                Label {
                    Text(model.appleVisionUnavailableReason ?? "Apple Vision is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Language

    private var languageSection: some View {
        @Bindable var model = model
        return Section("Language") {
            Picker("Document language", selection: $model.settings.language) {
                ForEach(LanguageChoice.allCases) { choice in
                    Text(choice.displayName)
                        .tag(choice)
                }
            }
            .help("Language(s) passed to the OCR engine with -l")

            if model.settings.language == .custom {
                TextField("Codes (e.g. eng+deu or fra)", text: $model.settings.customLanguage)
                    .textFieldStyle(.roundedBorder)
                    .help("ISO 639-2 codes. Separate multiple languages with + or commas.")
            }

            if model.settings.language == .automatic {
                if model.settings.engine == .tesseract {
                    warningLabel("Automatic detection needs Apple Vision. Tesseract will use its default language (English).")
                } else if !model.settings.appleRecognitionMode.supportsAutomaticLanguage {
                    infoLabel("Automatic detection uses the “Accurate” recognition mode; Live Text does not support it.")
                }
            }
        }
    }

    // MARK: Output

    private var outputSection: some View {
        @Bindable var model = model
        return Section("Output") {
            Picker("Save output", selection: $model.settings.outputMode) {
                ForEach(OutputMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            if model.settings.outputMode == .selectedFolder {
                LabeledContent("Folder") {
                    HStack(spacing: 6) {
                        Text(model.settings.outputFolder?.lastPathComponent ?? "None selected")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.settings.outputFolder == nil ? .red : .primary)
                            .help(model.settings.outputFolder?.path ?? "Choose an output folder")
                        Button("Choose…") {
                            showFolderPicker = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            TextField("Filename suffix", text: $model.settings.suffix)
                .textFieldStyle(.roundedBorder)
                .help("“Document.pdf” becomes “Document \(OutputNaming.sanitizedSuffix(model.settings.suffix).isEmpty ? "OCR" : OutputNaming.sanitizedSuffix(model.settings.suffix)).pdf”")

            Toggle("Allow overwriting existing files", isOn: $model.settings.allowOverwrite)
                .help("When off, processing stops instead of replacing a file that already exists.")
        }
    }

    // MARK: Page correction

    private var correctionSection: some View {
        @Bindable var model = model
        return Section("Page Correction") {
            Toggle("Rotate pages automatically", isOn: $model.settings.rotatePages)
                .help("--rotate-pages: rotate pages based on detected text orientation")
            Toggle("Deskew", isOn: $model.settings.deskew)
                .help("--deskew: straighten tilted scans before OCR")
            Toggle("Clean pages before OCR", isOn: $model.settings.cleanPages)
                .help("--clean: remove scanning artifacts before OCR (requires the separate unpaper tool; the output page images are unchanged)")
            Toggle("Remove background", isOn: $model.settings.removeBackground)
                .help("--remove-background: try to turn gray or colored page backgrounds white")
        }
    }

    // MARK: Existing text

    private var existingTextSection: some View {
        @Bindable var model = model
        return Section("Pages That Already Have Text") {
            Picker("Existing text", selection: $model.settings.textHandling) {
                ForEach(TextHandling.allCases) { handling in
                    Text(handling.displayName).tag(handling)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(model.settings.textHandling.help)
                .font(.caption)
                .foregroundStyle(model.settings.textHandling == .forceOCR ? .orange : .secondary)
        }
    }

    // MARK: Advanced

    private var advancedSection: some View {
        @Bindable var model = model
        return Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                if model.settings.engine == .appleVision {
                    Picker("Recognition mode", selection: $model.settings.appleRecognitionMode) {
                        ForEach(AppleRecognitionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .help("--appleocr-recognition-mode: Live Text gives the best quality on macOS 13+; Fast trades accuracy for speed")

                    Toggle("Disable language correction", isOn: $model.settings.appleDisableCorrection)
                        .help("--appleocr-disable-correction: turn off Apple Vision’s language model post-correction")
                }

                Picker("Parallel jobs", selection: jobsBinding) {
                    Text("Automatic").tag(0)
                    ForEach([1, 2, 4, 6, 8], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .help("--jobs: how many pages to work on at once")

                Picker("Optimize level", selection: $model.settings.optimizeLevel) {
                    Text("0 — none").tag(0)
                    Text("1 — safe (default)").tag(1)
                    Text("2 — aggressive").tag(2)
                    Text("3 — maximum").tag(3)
                }
                .help("--optimize: how aggressively to compress images in the output. Levels 2–3 need the optional pngquant tool for best results.")

                Toggle("Oversample to 300 DPI", isOn: oversampleBinding)
                    .help("--oversample 300: upscale low-resolution pages before OCR to improve recognition slightly")
            }
        }
    }

    // MARK: Command preview

    private var commandPreviewSection: some View {
        @Bindable var model = model
        return Section {
            DisclosureGroup("Command", isExpanded: $model.showCommandPreview) {
                Text(previewCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Shown for reference. The app never runs a shell — arguments are passed to OCRmyPDF as a structured list.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var previewCommand: String {
        let input = model.queue.items.first?.url
        let inputPath = input?.standardizedFileURL.path ?? "‹input.pdf›"
        let outputPath: String
        if let input {
            outputPath = OutputNaming.outputURL(
                for: input,
                mode: model.settings.outputMode,
                folder: model.settings.outputFolder,
                suffix: model.settings.suffix
            ).standardizedFileURL.path
        } else {
            outputPath = "‹output.pdf›"
        }
        let arguments = CommandBuilder.arguments(
            inputPath: inputPath,
            outputPath: outputPath,
            settings: model.settings
        )
        return CommandBuilder.displayCommand(
            executablePath: model.toolInfo?.executablePath ?? "ocrmypdf",
            arguments: arguments
        )
    }

    // MARK: Helpers

    /// Routed through the model so an explicit user pick is remembered and
    /// detection stops overriding it.
    private var engineBinding: Binding<OCREngine> {
        Binding(
            get: { model.settings.engine },
            set: { model.selectEngine($0) }
        )
    }

    private var jobsBinding: Binding<Int> {
        @Bindable var model = model
        return Binding(
            get: { model.settings.jobs ?? 0 },
            set: { model.settings.jobs = $0 == 0 ? nil : $0 }
        )
    }

    private var oversampleBinding: Binding<Bool> {
        @Bindable var model = model
        return Binding(
            get: { model.settings.oversampleDPI != nil },
            set: { model.settings.oversampleDPI = $0 ? 300 : nil }
        )
    }

    private func infoLabel(_ text: String) -> some View {
        Label {
            Text(text).font(.caption).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
    }

    private func warningLabel(_ text: String) -> some View {
        Label {
            Text(text).font(.caption).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }
}

#Preview {
    OptionsPanelView()
        .environment(AppModel())
        .frame(width: 320, height: 700)
}
