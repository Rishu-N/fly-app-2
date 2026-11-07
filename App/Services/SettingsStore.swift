import Foundation
import Observation
import PlannerCore
import Security

/// User preferences, persisted as one small JSON blob in the App Group defaults (so the widget
/// extension can read the theme and lead time). Changes are reported to the composition root so
/// reminders / Live Activity / widgets resync immediately.
@MainActor
@Observable
final class SettingsStore {
    var settings: PlannerSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
            onChange?(oldValue, settings)
        }
    }

    var theme: DialTheme {
        didSet {
            guard theme != oldValue else { return }
            AppGroup.defaults.set(theme.rawValue, forKey: AppGroup.themeKey)
            onChange?(settings, settings)
        }
    }

    var hasOnboarded: Bool {
        didSet { AppGroup.defaults.set(hasOnboarded, forKey: "onboarded") }
    }

    @ObservationIgnored var onChange: (@MainActor (_ old: PlannerSettings, _ new: PlannerSettings) -> Void)?

    init() {
        if let data = AppGroup.defaults.data(forKey: AppGroup.settingsKey),
           let decoded = try? JSONDecoder().decode(PlannerSettings.self, from: data) {
            settings = decoded
        } else {
            settings = PlannerSettings()
        }
        theme = DialTheme.stored
        hasOnboarded = AppGroup.defaults.bool(forKey: "onboarded")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            AppGroup.defaults.set(data, forKey: AppGroup.settingsKey)
        }
    }
}

/// Minimal Keychain wrapper for the OpenAI API key. Device-only, available after first unlock
/// (so background requests can read it), never synced, never logged.
enum KeychainStore {
    private static let service = "app.dayflight.assistant"
    private static let account = "openai-api-key"

    static func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func saveKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteKey()
        guard !trimmed.isEmpty else { return true }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// "••••abcd" for display.
    static func maskedKey() -> String? {
        guard let key = loadKey(), key.count > 4 else { return nil }
        return "••••" + key.suffix(4)
    }
}
