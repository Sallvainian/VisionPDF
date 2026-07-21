import SwiftUI
import UniformTypeIdentifiers

/// The Settings window (⌘,): OCRmyPDF location and detection on one tab,
/// default processing behavior on the other.
struct SettingsView: View {
    var body: some View {
        TabView {
            ToolSettingsTab()
                .tabItem {
                    Label("OCRmyPDF", systemImage: "wrench.and.screwdriver")
                }
            DefaultsSettingsTab()
                .tabItem {
                    Label("Defaults", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - OCRmyPDF tab

private struct ToolSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var showExecutablePicker = false

    var body: some View {
        Form {
            Section("Executable") {
                LabeledContent("Path") {
                    Text(model.toolInfo?.executablePath ?? model.executableOverride ?? "Not found")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(model.toolInfo == nil ? .red : .primary)
                }

                HStack {
                    Button("Browse…") {
                        showExecutablePicker = true
                    }
                    .help("Choose the ocrmypdf executable manually")

                    Button("Re-detect") {
                        model.refreshDetection()
                    }
                    .disabled(model.toolStatus == .checking)
                    .help("Search the standard install locations and your login-shell PATH again")

                    if model.executableOverride != nil {
                        Button("Use Automatic Detection") {
                            model.setExecutableOverride(nil)
                        }
                        .help("Forget the manual path and detect automatically")
                    }
                }
            }

            Section("Status") {
                LabeledContent("OCRmyPDF version") {
                    Text(model.toolInfo?.version ?? "—")
                        .textSelection(.enabled)
                }
                LabeledContent("Apple Vision plugin") {
                    Text(model.toolStatus.appleVisionLabel)
                        .foregroundStyle(model.toolStatus.isAppleVisionAvailable ? Color.green : Color.secondary)
                }
                if let reason = model.appleVisionUnavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("VisionPDF never installs software. Install OCRmyPDF yourself, for example:  uv tool install --with ocrmypdf-appleocr ocrmypdf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showExecutablePicker,
            allowedContentTypes: [.unixExecutable, .executable, .item]
        ) { result in
            if case .success(let url) = result {
                model.setExecutableOverride(url)
            }
        }
    }
}

// MARK: - Defaults tab

private struct DefaultsSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Defaults") {
                Picker("OCR engine", selection: Binding(
                    get: { model.settings.engine },
                    set: { model.selectEngine($0) }
                )) {
                    ForEach(OCREngine.allCases) { engine in
                        Text(engine.displayName)
                            .tag(engine)
                            .selectionDisabled(
                                engine == .appleVision && !model.toolStatus.isAppleVisionAvailable
                            )
                    }
                }
                Picker("Language", selection: $model.settings.language) {
                    ForEach(LanguageChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                if model.settings.language == .custom {
                    TextField("Custom language codes", text: $model.settings.customLanguage)
                }
                Picker("Save output", selection: $model.settings.outputMode) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                TextField("Filename suffix", text: $model.settings.suffix)
                    .help("“Document.pdf” becomes “Document ‹suffix›.pdf”")
            }

            Section("Processing") {
                Toggle("Continue after errors", isOn: $model.settings.continueAfterErrors)
                    .help("Keep processing the rest of the queue when a file fails")
                Toggle("Allow overwriting existing files", isOn: $model.settings.allowOverwrite)
                Toggle("Reveal the generated command", isOn: $model.showCommandPreview)
                    .help("Expand the Command section in the options panel, showing the equivalent command line")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
