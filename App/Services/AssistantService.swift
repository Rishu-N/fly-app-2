import Foundation
import Observation
import PlannerCore
import UIKit

/// Hosts the on-device agent loop, persists the conversation, keeps a request alive briefly
/// when the app is backgrounded, and posts "ready to review" when it finishes off-screen.
@MainActor
@Observable
final class AssistantService {
    let session: AssistantSession
    private(set) var availableModels: [String] = []
    private(set) var isLoadingModels = false

    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let notifications: NotificationScheduler
    @ObservationIgnored private let transport: OpenAIHTTPTransport
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// App-private (not the App Group): the widget never needs the conversation.
    private static var transcriptURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("assistant-transcript.json")
    }

    init(store: TaskStore, settingsStore: SettingsStore, notifications: NotificationScheduler) {
        self.settingsStore = settingsStore
        self.notifications = notifications
        let transport = OpenAIHTTPTransport()
        self.transport = transport
        let transcript: AssistantTranscript? = {
            guard let data = try? Data(contentsOf: Self.transcriptURL) else { return nil }
            return try? JSONDecoder().decode(AssistantTranscript.self, from: data)
        }()
        let env = AssistantEnvironment(
            transport: transport,
            apiKey: { KeychainStore.loadKey() },
            settings: { [weak settingsStore] in settingsStore?.settings ?? PlannerSettings() },
            uses24HourClock: {
                let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
                return !format.contains("a")
            }
        )
        session = AssistantSession(store: store, environment: env, transcript: transcript)
        session.onTranscriptChange = { [weak self] in self?.scheduleSave() }
        session.onModelFallback = { [weak self] model in self?.settingsStore.settings.assistant.model = model }
        session.onTurnFinished = { [weak self] needsReview in self?.turnFinished(needsReview: needsReview) }
    }

    var hasKey: Bool { KeychainStore.loadKey() != nil }

    func send(_ text: String) {
        beginBackgroundWindowIfNeeded()
        session.send(text)
    }

    func answer(_ itemID: UUID, _ text: String) {
        beginBackgroundWindowIfNeeded()
        session.answer(itemID, with: text)
    }

    /// Fetch `GET /models` for the picker in Settings.
    func refreshModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        guard let endpoint = try? AssistantEndpoint(baseURLString: settingsStore.settings.assistant.baseURL, apiKey: KeychainStore.loadKey() ?? "") else { return }
        let models = (try? await transport.listModels(endpoint: endpoint)) ?? []
        availableModels = models.filter { id in
            let m = id.lowercased()
            return !["embedding", "whisper", "tts", "dall-e", "moderation", "image", "transcribe", "audio", "realtime"].contains(where: m.contains)
        }
    }

    func clearHistory() {
        session.clear()
        try? FileManager.default.removeItem(at: Self.transcriptURL)
    }

    // MARK: Persistence (debounced, off-main encode)

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            var transcript = self.session.transcript
            // Cap stored history so the file stays small.
            if transcript.items.count > 300 { transcript.items.removeFirst(transcript.items.count - 300) }
            if transcript.wire.count > 200 { transcript.wire.removeFirst(transcript.wire.count - 200) }
            let url = Self.transcriptURL
            Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(transcript) { try? data.write(to: url, options: [.atomic]) }
            }
        }
    }

    // MARK: Background

    private func beginBackgroundWindowIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "assistant-request") { [weak self] in
            self?.session.stop()
            self?.endBackgroundWindow()
        }
    }

    private func endBackgroundWindow() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func turnFinished(needsReview: Bool) {
        if UIApplication.shared.applicationState != .active, needsReview {
            notifications.postAssistantReady(summary: "Tap to review the proposed changes.")
        }
        endBackgroundWindow()
    }
}
