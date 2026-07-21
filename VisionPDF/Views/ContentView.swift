import SwiftUI
import UniformTypeIdentifiers

/// Main window: status header, file queue with drop target, options inspector,
/// processing bar, and collapsible log panel.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    @State private var showOptions = true
    @State private var showLogs = false
    @State private var showFileImporter = false
    @State private var showClearConfirmation = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            mainArea
            Divider()
            ProcessingBarView(showLogs: $showLogs)
            if showLogs {
                Divider()
                LogPanelView()
                    .frame(minHeight: 160, idealHeight: 220, maxHeight: 320)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: showLogs)
        .inspector(isPresented: $showOptions) {
            OptionsPanelView()
                .inspectorColumnWidth(min: 290, ideal: 320, max: 380)
        }
        .toolbar { toolbarContent }
        .navigationTitle("VisionPDF")
        .navigationSubtitle(subtitle)
        .dropDestination(for: URL.self) { urls, _ in
            model.queue.add(urls: urls) > 0
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.queue.add(urls: urls)
            }
        }
        .confirmationDialog(
            "Remove all files from the queue?",
            isPresented: $showClearConfirmation
        ) {
            Button("Clear Queue", role: .destructive) {
                model.queue.clearQueue()
            }
        } message: {
            Text("Your PDFs on disk are not affected.")
        }
        .sheet(isPresented: firstLaunchBinding) {
            FirstLaunchView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .visionPDFAddFiles)) { _ in
            showFileImporter = true
        }
    }

    private var mainArea: some View {
        Group {
            if model.queue.items.isEmpty {
                DropZoneView(isTargeted: isDropTargeted) {
                    showFileImporter = true
                }
            } else {
                QueueListView(isDropTargeted: isDropTargeted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var subtitle: String {
        let status = model.toolStatus
        if let version = status.ocrmypdfVersion {
            return "OCRmyPDF \(version) · \(status.appleVisionLabel)"
        }
        return status.appleVisionLabel
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            StatusBadgeView()
        }
        ToolbarItem(placement: .navigation) {
            Button {
                model.refreshDetection()
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .disabled(model.toolStatus == .checking)
            .help("Re-detect OCRmyPDF and the Apple Vision plugin")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showFileImporter = true
            } label: {
                Label("Add PDFs", systemImage: "plus")
            }
            .help("Add PDF files to the queue (⌘O)")

            Button {
                showClearConfirmation = true
            } label: {
                Label("Clear Queue", systemImage: "trash")
            }
            .help("Remove all files from the queue")
            .disabled(model.queue.items.isEmpty || model.queue.isProcessing)

            Button {
                showOptions.toggle()
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
            }
            .help("Show or hide OCR options")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open VisionPDF settings (⌘,)")
        }
    }

    private var firstLaunchBinding: Binding<Bool> {
        Binding(
            get: { !model.hasCompletedFirstLaunch },
            set: { showing in
                if !showing { model.hasCompletedFirstLaunch = true }
            }
        )
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .frame(width: 1040, height: 680)
}
