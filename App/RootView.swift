import PlannerCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Now", systemImage: "timer", value: AppModel.AppTab.now) {
                NowView()
            }
            Tab("Plan", systemImage: "calendar.day.timeline.left", value: AppModel.AppTab.plan) {
                PlanView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayer() }
            }
            Tab("Assistant", systemImage: "sparkles", value: AppModel.AppTab.assistant) {
                AssistantView()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $model.showCapture) {
            QuickCaptureView(seed: model.captureSeed)
                .presentationDetents([.height(300), .medium])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(32)
        }
        .sheet(item: $model.editingTask) { task in
            TaskEditorView(task: task)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        .confirmationDialog(
            conflictTitle,
            // Deferred: SwiftUI may reset the binding *before* running the tapped button's action,
            // which would clear the conflict and turn "Complete current & start" into a no-op.
            isPresented: Binding(get: { model.startConflict != nil }, set: { [model] presented in
                if !presented { Task { @MainActor in model.resolveConflict(nil) } }
            }),
            titleVisibility: .visible
        ) {
            Button("Complete current & start") { model.resolveConflict(.completeOther) }
            Button("Cancel current & start", role: .destructive) { model.resolveConflict(.cancelOther) }
            Button("Keep current", role: .cancel) { model.resolveConflict(nil) }
        } message: {
            Text("Only one timer runs at a time.")
        }
        .fullScreenCover(isPresented: Binding(get: { !model.settings.hasOnboarded }, set: { model.settings.hasOnboarded = !$0 })) {
            OnboardingView()
        }
        .background(palette.bg.ignoresSafeArea())
    }

    private var conflictTitle: String {
        guard let c = model.startConflict else { return "" }
        return "“\(c.active.title)” is running"
    }
}
