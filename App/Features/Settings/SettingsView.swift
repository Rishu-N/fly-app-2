import PlannerCore
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var maskedKey = KeychainStore.maskedKey()

    var body: some View {
        @Bindable var settingsStore = model.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Reminders", isOn: $settingsStore.settings.remindersEnabled)
                    Picker("Remind me", selection: $settingsStore.settings.defaultLeadMinutes) {
                        ForEach(PlannerSettings.leadTimeChoices, id: \.self) { m in
                            Text(m == 0 ? "At start" : "\(m) min before").tag(m)
                        }
                    }
                    Toggle("Time Sensitive", isOn: $settingsStore.settings.timeSensitiveReminders)
                    Toggle("Notify when the timer ends", isOn: $settingsStore.settings.notifyWhenTimerEnds)
                    NavigationLink("Check my reminders") { ReminderDiagnosticsView() }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Time Sensitive reminders can break through Focus modes you allow.")
                }

                Section("Planning") {
                    Picker("Default length", selection: $settingsStore.settings.defaultDurationMinutes) {
                        ForEach([15, 25, 30, 45, 60, 90], id: \.self) { Text(formatDuration($0)).tag($0) }
                    }
                    Picker("Day starts", selection: $settingsStore.settings.dayStartHour) {
                        ForEach(4...12, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Picker("Day ends", selection: $settingsStore.settings.dayEndHour) {
                        ForEach(16...23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    Toggle("Auto-complete when the timer ends", isOn: $settingsStore.settings.autoCompleteWhenTimerEnds)
                }

                calendarSection

                Section("Look & feel") {
                    ThemePicker(selection: $settingsStore.theme)
                    Toggle("Ambient aurora", isOn: $settingsStore.settings.ambientBackground)
                    Toggle("Haptics", isOn: $settingsStore.settings.hapticsEnabled)
                    Toggle("Live Activities", isOn: $settingsStore.settings.liveActivitiesEnabled)
                }

                assistantSection

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Your schedule lives on this iPhone. The assistant talks directly to the AI provider you configure — there is no Dayflight server.")
                        .font(.footnote)
                        .foregroundStyle(palette.text2)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: model.settings.settings) { _, new in
                Haptics.enabled = new.hapticsEnabled
            }
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        let overlay = model.calendarOverlay
        Section {
            Toggle("Show Apple Calendar events", isOn: Binding(
                get: { overlay.isActive },
                set: { on in
                    if on, !overlay.isAuthorized {
                        Task { await overlay.requestAccess() }
                    } else {
                        overlay.enabled = on
                    }
                }
            ))
            if overlay.status == .denied || overlay.status == .restricted {
                Button("Allow calendar access in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Events show as busy time on your timeline, and quick add and the assistant work around them. Dayflight never changes your calendars.")
        }
    }

    @ViewBuilder
    private var assistantSection: some View {
        @Bindable var settingsStore = model.settings
        let service = model.assistantService
        Section {
            if let maskedKey {
                LabeledContent("OpenAI key", value: maskedKey)
                Button("Remove key", role: .destructive) {
                    KeychainStore.deleteKey()
                    self.maskedKey = nil
                    service.keyChanged()
                }
            } else {
                SecureField("Paste your OpenAI API key", text: $keyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save key") {
                    KeychainStore.saveKey(keyInput)
                    keyInput = ""
                    maskedKey = KeychainStore.maskedKey()
                    service.keyChanged()
                    Task { await service.refreshModels(force: true) }
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).count < 8)
            }

            HStack {
                TextField("Model", text: $settingsStore.settings.assistant.model)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.body.monospaced())
                Menu {
                    let live = service.availableModels
                    if !live.isEmpty {
                        Section("Available on your account") {
                            ForEach(live, id: \.self) { m in
                                Button(m) { settingsStore.settings.assistant.model = m }
                            }
                        }
                    }
                    Section("Presets") {
                        ForEach(AssistantSettings.modelPresets, id: \.self) { m in
                            Button(m) { settingsStore.settings.assistant.model = m }
                        }
                    }
                    Button("Refresh list", systemImage: "arrow.clockwise") {
                        Task { await service.refreshModels(force: true) }
                    }
                } label: {
                    if service.isLoadingModels { ProgressView() } else { Image(systemName: "chevron.up.chevron.down") }
                }
            }

            Picker("Reasoning effort", selection: $settingsStore.settings.assistant.reasoningEffort) {
                ForEach(["minimal", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            TextField("Server", text: $settingsStore.settings.assistant.baseURL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.footnote.monospaced())
            Toggle("Share task notes", isOn: $settingsStore.settings.assistant.shareNotes)
            if service.session.usage.total > 0 {
                let usage = service.session.usage
                LabeledContent("This conversation", value: "\(usage.total) tokens")
            }
            Button("Clear conversation", role: .destructive) { service.clearHistory() }
        } header: {
            Text("Assistant")
        } footer: {
            Text("Your key is stored in the iPhone Keychain and only sent to the server above. Any OpenAI-compatible server works (for example a local Ollama or LM Studio at http://192.168.x.x:11434/v1). If a model is retired, the assistant switches to an available one automatically.")
        }
        .task { await service.refreshModels() }
    }
}

private struct ThemePicker: View {
    @Binding var selection: DialTheme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(DialTheme.allCases) { theme in
                let p = theme.palette
                Button {
                    withAnimation(Motion.snappy) { selection = theme }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(p.bg)
                            Circle().trim(from: 0, to: 0.72).stroke(p.now, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(8)
                        }
                        .frame(width: 54, height: 54)
                        .overlay(Circle().stroke(selection == theme ? p.now : Color.clear, lineWidth: 2).padding(-4))
                        Text(theme.displayName).font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// "It didn't notify me" is the #1 planner complaint — show exactly what iOS will do.
struct ReminderDiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var status: UNNotificationSettings?
    @State private var pendingCount = 0

    var body: some View {
        List {
            Section {
                row("Notifications", ok: status?.authorizationStatus == .authorized, detail: authText)
                row("Time Sensitive", ok: status?.timeSensitiveSetting == .enabled, detail: status?.timeSensitiveSetting == .enabled ? "Allowed" : "Off — reminders may wait for Focus to end")
                row("Scheduled Summary", ok: status?.scheduledDeliverySetting != .enabled, detail: status?.scheduledDeliverySetting == .enabled ? "On — reminders may be delayed" : "Off")
                row("Reminders scheduled", ok: pendingCount > 0 || model.store.upcoming(from: Date(), days: 7).isEmpty, detail: "\(pendingCount) pending (iOS allows 64)")
            }
            Section {
                if status?.authorizationStatus == .notDetermined {
                    Button("Allow notifications") {
                        Task { await model.notifications.requestAuthorization(); await refresh() }
                    }
                }
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .navigationTitle("Check my reminders")
        .task { await refresh() }
    }

    private var authText: String {
        switch status?.authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied — tap Open iOS Settings"
        case .provisional: "Quiet delivery"
        case .notDetermined: "Not asked yet"
        default: "Unknown"
        }
    }

    private func row(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? palette.success : palette.warning)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(palette.text2)
            }
        }
    }

    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        status = await center.notificationSettings()
        pendingCount = await center.pendingNotificationRequests().count
    }
}
