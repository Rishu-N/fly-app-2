import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action button control: one tap to quick add.
struct QuickAddControl: ControlWidget {
    static let kind = "app.dayflight.control.quickadd"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Add Block", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add a Block")
        .description("Opens Dayflight's quick add.")
    }
}
