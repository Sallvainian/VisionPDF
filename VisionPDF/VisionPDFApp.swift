import SwiftUI

@main
struct VisionPDFApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // A single Window (not a WindowGroup): the queue and tool state are
        // app-global, so multiple windows would only mislead.
        Window("VisionPDF", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 840, minHeight: 560)
                .task {
                    model.refreshDetection()
                }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add PDFs…") {
                    NotificationCenter.default.post(name: .visionPDFAddFiles, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!model.hasCompletedFirstLaunch)

                Divider()

                Button("Start OCR") {
                    model.startProcessing()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.hasCompletedFirstLaunch || !model.canStartProcessing)

                Button("Cancel Processing") {
                    model.queue.cancel()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.queue.isProcessing)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

extension Notification.Name {
    /// Menu → window signal; the window owns the file-picker state.
    static let visionPDFAddFiles = Notification.Name("VisionPDF.addFiles")
}
