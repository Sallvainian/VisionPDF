import Foundation
import Observation

/// Composition root: owns tool detection state, user settings (persisted to
/// UserDefaults), and the processing queue.
@MainActor
@Observable
final class AppModel {
    private(set) var toolStatus: ToolStatus = .unknown
    private(set) var toolInfo: ToolInfo?

    var settings: OCRSettings {
        didSet { persistSettings() }
    }

    /// Manual executable path chosen in Settings; wins over auto-detection.
    var executableOverride: String? {
        didSet { defaults.set(executableOverride, forKey: Keys.executableOverride) }
    }

    var showCommandPreview: Bool {
        didSet { defaults.set(showCommandPreview, forKey: Keys.showCommandPreview) }
    }

    var hasCompletedFirstLaunch: Bool {
        didSet { defaults.set(hasCompletedFirstLaunch, forKey: Keys.hasCompletedFirstLaunch) }
    }

    /// True once the user has explicitly picked an engine. Until then, Apple
    /// Vision is promoted to the default whenever the plugin is detected.
    private(set) var userChoseEngine: Bool {
        didSet { defaults.set(userChoseEngine, forKey: Keys.userChoseEngine) }
    }

    let queue: QueueController

    private let locator: ExecutableLocator
    private let detector: ToolDetector
    private let defaults: UserDefaults
    private var detectionTask: Task<Void, Never>?

    private enum Keys {
        static let settings = "settingsJSON"
        static let executableOverride = "executableOverride"
        static let showCommandPreview = "showCommandPreview"
        static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
        static let userChoseEngine = "userChoseEngine"
    }

    init(
        locator: ExecutableLocator = ExecutableLocator(),
        detector: ToolDetector = ToolDetector(),
        queue: QueueController = QueueController(),
        defaults: UserDefaults = .standard
    ) {
        self.locator = locator
        self.detector = detector
        self.queue = queue
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.settings),
           let saved = try? JSONDecoder().decode(OCRSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = OCRSettings()
        }
        self.executableOverride = defaults.string(forKey: Keys.executableOverride)
        self.showCommandPreview = defaults.bool(forKey: Keys.showCommandPreview)
        self.hasCompletedFirstLaunch = defaults.bool(forKey: Keys.hasCompletedFirstLaunch)
        self.userChoseEngine = defaults.bool(forKey: Keys.userChoseEngine)
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Keys.settings)
        }
    }

    /// Runs (or re-runs) executable and plugin detection. Safe to call from the
    /// "Check Again" button while a previous pass is still in flight.
    func refreshDetection() {
        detectionTask?.cancel()
        toolStatus = .checking
        detectionTask = Task { [weak self] in
            guard let self else { return }
            let override = self.executableOverride
            let path = await self.locator.locate(preferredPath: override)
            guard !Task.isCancelled else { return }
            guard let path else {
                self.toolStatus = .ocrmypdfMissing
                self.toolInfo = nil
                self.applyEngineAvailability()
                return
            }
            let shellPATH = await self.locator.loginShellPATH()
            let detection = await self.detector.detect(
                executablePath: path,
                loginShellPATH: shellPATH
            )
            guard !Task.isCancelled else { return }
            self.toolStatus = detection.status
            self.toolInfo = detection.toolInfo
            self.applyEngineAvailability()
        }
    }

    /// The user explicitly picked an engine; sticky across detections.
    func selectEngine(_ engine: OCREngine) {
        settings.engine = engine
        userChoseEngine = true
    }

    /// Keeps the selected engine consistent with what is actually installed:
    /// Apple Vision becomes the default whenever the plugin is detected —
    /// unless the user has explicitly chosen an engine — and is deselected
    /// when the plugin disappears.
    private func applyEngineAvailability() {
        if toolStatus.isAppleVisionAvailable {
            if !userChoseEngine {
                settings.engine = .appleVision
            }
        } else if settings.engine == .appleVision {
            settings.engine = .tesseract
        }
    }

    /// Single gate for starting a batch — shared by the Start button and the
    /// Start OCR menu item so they can never disagree.
    var canStartProcessing: Bool {
        toolInfo != nil
            && !queue.isProcessing
            && queue.pendingCount > 0
            && !(settings.outputMode == .selectedFolder && settings.outputFolder == nil)
    }

    func startProcessing() {
        guard canStartProcessing, let toolInfo else { return }
        queue.start(settings: settings, toolInfo: toolInfo)
    }

    /// Applies a manually browsed executable and re-detects.
    func setExecutableOverride(_ url: URL?) {
        executableOverride = url?.path
        refreshDetection()
    }

    var diagnosticsText: String {
        Diagnostics.summary(
            toolStatus: toolStatus,
            toolInfo: toolInfo,
            settings: settings,
            lastArguments: queue.lastArguments,
            lastExitCode: queue.lastExitCode
        )
    }

    /// Explanation for why Apple Vision cannot currently be selected, if so.
    var appleVisionUnavailableReason: String? {
        switch toolStatus {
        case .fullyAvailable:
            nil
        case .pluginUnavailable(_, let reason):
            reason
        case .ocrmypdfMissing:
            "OCRmyPDF was not found, so no OCR engine is available."
        case .detectionFailed(let reason):
            "Detection failed: \(reason)"
        case .unknown, .checking:
            "Still checking the OCRmyPDF installation…"
        }
    }
}
