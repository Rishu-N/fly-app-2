import PlannerCore
import SwiftUI

struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var input = ""
    @State private var template: PromptTemplate?
    @State private var showConsent = false
    @State private var pendingSend: String?
    @FocusState private var composerFocused: Bool

    private var service: AssistantService { model.assistantService }
    private var session: AssistantSession { model.assistantService.session }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if session.items.isEmpty {
                            EmptyAssistantState(onTemplate: { template = $0 })
                        }
                        ForEach(session.items) { item in
                            ChatItemView(item: item, onAnswer: { id, text in send(answer: text, to: id) })
                                .id(item.id)
                        }
                        if session.isRunning {
                            StreamingBubble(text: session.streamingText, status: session.statusLine)
                                .id("streaming")
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: session.items.count) { _, _ in
                    withAnimation(Motion.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: session.streamingText) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if session.usage.total > 0 {
                        Text("\(formatTokens(session.usage.total)) tokens")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.text3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New conversation", systemImage: "square.and.pencil") { service.clearHistory() }
                        Button("Assistant settings", systemImage: "gearshape") { model.showSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $template) { t in
                TemplateFormView(template: t) { text in
                    template = nil
                    send(text)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showConsent) {
                ConsentSheet {
                    model.settings.settings.assistant.consentGiven = true
                    showConsent = false
                    if let text = pendingSend { pendingSend = nil; send(text) }
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            MiniPlayer()
            if !session.items.isEmpty, !session.isRunning, session.pendingQuestion == nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(PromptTemplate.library) { t in
                            Button {
                                template = t
                            } label: {
                                Label(t.title, systemImage: t.symbol)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(palette.surface, in: Capsule())
                                    .foregroundStyle(palette.text1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(session.pendingQuestion != nil ? "Type an answer…" : "Ask to add, move or plan…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .submitLabel(.send)
                    .onSubmit { send(input) }
                Button {
                    if session.isRunning { session.stop() } else { send(input) }
                } label: {
                    Image(systemName: session.isRunning ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(palette.onNow)
                        .background(canSend || session.isRunning ? palette.now : palette.text3.opacity(0.5), in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(!canSend && !session.isRunning)
                .padding(6)
                .accessibilityLabel(session.isRunning ? "Stop" : "Send")
            }
            .floatingGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
    }

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isRunning else { return }
        guard model.settings.settings.assistant.consentGiven else {
            pendingSend = trimmed
            showConsent = true
            return
        }
        input = ""
        service.send(trimmed)
    }

    private func send(answer: String, to id: UUID) {
        service.answer(id, answer)
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}

// MARK: - Empty state

private struct EmptyAssistantState: View {
    let onTemplate: (PromptTemplate) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(palette.now)
                    .symbolEffect(.bounce, options: .nonRepeating)
                Text("Plan out loud.")
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(palette.text1)
                Text("Ask me to add, move or plan your blocks. I'll ask if something's unclear, and nothing changes until you tap Apply.")
                    .font(.subheadline)
                    .foregroundStyle(palette.text2)
            }
            if !model.assistantService.hasKey, model.settings.settings.assistant.baseURL.contains("openai.com") {
                Button {
                    model.showSettings = true
                } label: {
                    Label("Connect your OpenAI account", systemImage: "key.fill")
                }
                .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow, height: 48))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(PromptTemplate.library) { t in
                    Button { onTemplate(t) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: t.symbol)
                                .font(.title3)
                                .foregroundStyle(palette.now)
                            Text(t.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.text1)
                            Text(t.subtitle)
                                .font(.caption)
                                .foregroundStyle(palette.text2)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .padding(14)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Items

private struct ChatItemView: View {
    let item: ChatItem
    let onAnswer: (UUID, String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        switch item.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(.body)
                    .foregroundStyle(palette.text1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.nowSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        case .assistant(let text):
            Text(LocalizedStringKey(text))
                .font(.body)
                .foregroundStyle(palette.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .question(let q):
            QuestionCard(question: q, itemID: item.id, onAnswer: onAnswer)
        case .proposal(let p):
            ProposalCard(proposal: p)
        case .notice(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(palette.text3)
                .frame(maxWidth: .infinity)
        case .error(let message, let retryable):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(palette.warning)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).font(.subheadline).foregroundStyle(palette.text1)
                    HStack {
                        if retryable {
                            Button("Retry") { model.assistantService.session.retry() }
                                .buttonStyle(.bordered)
                        }
                        if message.contains("Settings") {
                            Button("Open Settings") { model.showSettings = true }
                                .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct StreamingBubble: View {
    let text: String
    let status: String?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !text.isEmpty {
                Text(text).font(.body).foregroundStyle(palette.text1)
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(status ?? "Writing…").font(.caption).foregroundStyle(palette.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}

/// Clarifying question → option chips + "Just decide for me" + free text in the composer.
private struct QuestionCard: View {
    let question: AssistantQuestion
    let itemID: UUID
    let onAnswer: (UUID, String) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(question.text, systemImage: "questionmark.bubble.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.text1)
            if let answer = question.answer {
                Label(answer, systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(palette.text2)
            } else {
                FlowChips(options: question.options + ["Just decide for me"]) { choice in
                    onAnswer(itemID, choice == "Just decide for me" ? "You decide — pick sensible defaults and tell me what you assumed." : choice)
                }
                if question.allowFreeText {
                    Text("Or type your own answer below.").font(.caption).foregroundStyle(palette.text3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(palette.now.opacity(question.answer == nil ? 0.5 : 0), lineWidth: 1))
    }
}

private struct FlowChips: View {
    let options: [String]
    let onTap: (String) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(options, id: \.self) { option in
            Button(option) { onTap(option) }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(option == "Just decide for me" ? palette.surface2 : palette.nowSoft, in: Capsule())
                .foregroundStyle(option == "Just decide for me" ? palette.text2 : palette.text1)
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Consent (App Review 5.1.2(i))

private struct ConsentSheet: View {
    let onAccept: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundStyle(palette.now)
            Text("Before you start").font(.title2.weight(.bold))
            Text("To answer, Dayflight sends your message and the relevant part of your schedule (task titles, times, categories) directly from this iPhone to \(host). Notes are only sent if you turn that on in Settings. There is no Dayflight server, and nothing changes in your calendar until you tap Apply.")
                .font(.subheadline)
                .foregroundStyle(palette.text2)
            Spacer()
            Button("Continue", action: onAccept)
                .buttonStyle(PillButtonStyle(fill: palette.now, foreground: palette.onNow))
            Button("Not now") { dismiss() }
                .frame(maxWidth: .infinity)
                .foregroundStyle(palette.text2)
        }
        .padding(24)
    }

    private var host: String {
        URL(string: model.settings.settings.assistant.baseURL)?.host ?? "your AI provider"
    }
}
