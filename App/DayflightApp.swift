import SwiftUI
import UIKit

@main
struct DayflightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.palette, model.settings.theme.palette)
                .tint(model.settings.theme.palette.now)
                .onOpenURL { model.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
}

/// Ensures the composition root (and with it the notification delegate) exists as early as
/// possible — including background launches from notification actions and Live Activity intents.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { _ = AppModel.shared }
        return true
    }
}
