import Combine
import PlannerCore
import SwiftUI
import UIKit

/// Time-of-day colour field behind the current-task card (UI-2 §2.6).
///
/// Cheap by construction: a 3×3 `MeshGradient`, ≤ 15 fps, only while visible, never under
/// Reduce Motion / Low Power Mode / serious thermal state, frozen while the task is paused.
struct AuroraField: View {
    enum Tone { case normal, endingSoon, overrun, paused, idle }

    var tone: Tone
    var enabled: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var animating: Bool {
        enabled && visible && !reduceMotion && !lowPower && tone != .paused
            && ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }

    var body: some View {
        let stops = DayPhase.at(Date()).stops(dark: scheme == .dark)
        Group {
            if enabled {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !animating)) { context in
                    mesh(stops: stops, t: animating ? context.date.timeIntervalSinceReferenceDate : 0)
                }
            } else {
                palette.surface
            }
        }
        .saturation(tone == .paused ? 0.35 : 1)
        .opacity(tone == .idle ? 0.5 : 1)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
    }

    private func mesh(stops: [Color], t: TimeInterval) -> some View {
        // Centre + edge midpoints drift slowly (amplitude ≤ 0.06, ~20 s period).
        let a = Float(sin(t * .pi / 10) * 0.06)
        let b = Float(cos(t * .pi / 13) * 0.05)
        let accent: Color = {
            switch tone {
            case .endingSoon: return palette.warning
            case .overrun: return palette.danger
            default: return stops[2]
            }
        }()
        let blendCenter = tone == .endingSoon || tone == .overrun ? accent.opacity(0.55) : stops[2]
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5 + a, 0], [1, 0],
                [0, 0.5 - b], [0.5 + b, 0.5 + a], [1, 0.5 + b],
                [0, 1], [0.5 - a, 1], [1, 1],
            ],
            colors: [
                stops[0], stops[0], stops[1],
                stops[3], blendCenter, stops[1],
                stops[3], stops[2], stops[2],
            ]
        )
    }
}
