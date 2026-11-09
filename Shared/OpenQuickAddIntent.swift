import AppIntents
import Foundation

/// Opens Dayflight straight into quick add. Used by the Control Center / Lock Screen control
/// and the Action button. Compiled into both targets; only the app acts on it.
struct OpenQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add Block"
    static let description = IntentDescription("Opens Dayflight's one-line quick add.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if DAYFLIGHT_APP
        let model = AppModel.shared
        model.selectedTab = .now
        model.captureSeed = ""
        model.showCapture = true
        #endif
        return .result()
    }
}
