import Foundation
import PlannerCore

/// Shared container between the app and the widget extension.
///
/// The group id is derived from the app's bundle id (`group.<app bundle id>`), so there is a
/// single place to configure identifiers: `APP_BUNDLE_ID` in `Config/Base.xcconfig`.
enum AppGroup {
    static let themeKey = "dial.theme"
    static let settingsKey = "planner.settings.v1"

    static var appBundleID: String {
        let id = Bundle.main.bundleIdentifier ?? "app.dayflight"
        return id.hasSuffix(".widgets") ? String(id.dropLast(".widgets".count)) : id
    }

    static var identifier: String { "group." + appBundleID }

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // Fallback (e.g. App Group not provisioned yet): app-private storage still works.
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var dataDirectory: URL { containerURL.appendingPathComponent("Data", isDirectory: true) }
    static var widgetSnapshotURL: URL { containerURL.appendingPathComponent("widget-snapshot.json") }

    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}

/// What the widgets render. Written by the app (only when it changes), read by the widget
/// timeline provider. Small: tasks from yesterday through tomorrow.
struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var tasks: [PlanTask]
    var theme: String
    var defaultLeadMinutes: Int

    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: AppGroup.widgetSnapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys] // byte-stable → stable content hash
        return try encoder.encode(self)
    }
}

enum DeepLink {
    static let scheme = "dayflight"
    static let now = URL(string: "dayflight://now")!
    static let plan = URL(string: "dayflight://plan")!
    static let assistant = URL(string: "dayflight://assistant")!
    static func task(_ id: UUID) -> URL { URL(string: "dayflight://task/\(id.uuidString)")! }
}
