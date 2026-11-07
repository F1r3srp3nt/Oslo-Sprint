import RelayCore
import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.interactions.isEmpty { emptyState }
                        ForEach(model.interactions) { interaction in
                            InteractionCard(interaction: interaction).id(interaction.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(18)
                    .animation(.easeOut(duration: 0.2), value: model.interactions.count)
                }
                .onChange(of: model.interactions.count) { _, _ in
                    if let last = model.interactions.last?.id {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            if case .reviewing = model.voice.state { TranscriptReviewBar() }
            if case let .failed(reason) = model.voice.state { voiceErrorBar(reason) }
            InputBar(draft: $draft)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            SectionHeader(title: "Assistant", subtitle: "What Relay heard, understood, planned, attempted — and what happened.")
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    StatusPill(text: "Speech in: \(model.voice.transcriberStatus.label)", color: Theme.color(model.voice.transcriberStatus))
                    StatusPill(text: "Speech out: \(model.speechOutputLabel)", color: Theme.color(model.voice.synthesizerStatus))
                }
                StatusPill(text: "Reasoning: \(model.reasonerName)", color: Theme.accent)
            }
        }
        .padding(18)
    }

    private var emptyState: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try:").font(.headline)
                ForEach(["start", "Which gloves do I need?", "add task Check dock B lights", "run the simulation", "help"],
                        id: \.self) { example in
                    Button(example) { model.send(example, source: .typed) }
                        .buttonStyle(.link)
                }
                Text("Speech is optional. Everything works by typing.").font(.callout).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func voiceErrorBar(_ reason: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
            Text(reason).font(.callout).lineLimit(2)
            Spacer()
            Button("Dismiss") { model.dismissVoiceError() }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Theme.danger.opacity(0.12))
    }
}

struct InteractionCard: View {
    @EnvironmentObject private var model: AppModel
    let interaction: Interaction

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                LabeledRow(label: "Heard") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\u{201C}\(interaction.heard.text)\u{201D}").foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                        Text(interaction.heard.source.label).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                LabeledRow(label: "Understood") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(interaction.understanding.intent.label).foregroundStyle(Theme.textPrimary)
                        Text("\(interaction.understanding.explanation) · confidence \(Int(interaction.understanding.confidence * 100))%")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                LabeledRow(label: "Plan") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(interaction.plan.summary).foregroundStyle(Theme.textPrimary)
                        if !interaction.plan.steps.isEmpty {
                            Text(interaction.plan.steps.map(\.toolName).joined(separator: " → "))
                                .font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                LabeledRow(label: "Attempted") {
                    if interaction.attempts.isEmpty {
                        Text("Nothing").foregroundStyle(Theme.textSecondary)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(Array(interaction.attempts.enumerated()), id: \.offset) { _, attempt in
                                StatusPill(text: "\(attempt.step.toolName): \(attempt.status.rawValue)",
                                           color: Theme.color(attempt.status))
                            }
                        }
                    }
                }
                LabeledRow(label: "Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusPill(text: interaction.status.rawValue, color: Theme.color(interaction.status))
                        Text(interaction.reply).foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if interaction.status == .awaitingApproval {
                                Button("Approve") { model.approve(interaction) }.buttonStyle(.borderedProminent)
                                Button("Decline", role: .cancel) { model.decline(interaction) }
                            }
                            if model.voice.canSpeak && !interaction.reply.isEmpty {
                                Button { model.speak(interaction.reply) } label: { Label("Speak", systemImage: "speaker.wave.2") }
                                    .buttonStyle(.borderless)
                                    .disabled(model.isSpeaking || model.isRecording)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct InputBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            PushToTalkButton()
            VStack(alignment: .leading, spacing: 4) {
                if model.isRecording, let start = model.recordingStartedAt {
                    TimelineView(.periodic(from: start, by: 0.5)) { context in
                        let seconds = Int(context.date.timeIntervalSince(start))
                        Text("● Recording \(seconds / 60):\(String(format: "%02d", seconds % 60)) — release to stop")
                            .font(.callout.weight(.semibold)).foregroundStyle(Theme.danger)
                    }
                } else if model.voice.state == .transcribing {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Transcribing…").font(.callout) }
                } else {
                    TextField("Type a request or a question about the procedure", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($focused)
                        .onSubmit(send)
                }
                if !model.voice.canRecord && !model.isRecording && model.voice.state == .idle {
                    Text(model.microphoneDenied ? "Microphone access denied — text input still works."
                                                : "Voice is off until ElevenLabs is configured in Settings. Text works without it.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.isSpeaking {
                Button { model.stopSpeaking() } label: { Label("Stop playback", systemImage: "stop.fill") }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(".", modifiers: .command)
            }
            Button("Send", action: send)
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .background(Theme.panel)
        .onAppear { focused = true }
    }

    private func send() {
        let text = draft
        draft = ""
        model.send(text, source: .typed)
    }
}

struct PushToTalkButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var pressing = false
    @State private var pulse = false

    var body: some View {
        let recording = model.isRecording
        let enabled = model.voice.canRecord || recording
        ZStack {
            if recording {
                Circle()
                    .stroke(Theme.danger.opacity(0.6), lineWidth: 2)
                    .frame(width: 54, height: 54)
                    .scaleEffect(pulse ? 1.2 : 0.9)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(recording ? Theme.danger : Theme.panelRaised)
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(Theme.stroke))
            Image(systemName: recording ? "waveform" : "mic.fill")
                .foregroundStyle(recording ? Color.white : (enabled ? Theme.textPrimary : Theme.textSecondary))
        }
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .opacity(enabled ? 1 : 0.45)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !pressing else { return }
                    pressing = true
                    model.pressTalk()
                }
                .onEnded { _ in
                    guard pressing else { return }
                    pressing = false
                    model.releaseTalk()
                }
        )
        .onChange(of: recording) { _, isRecording in pulse = isRecording }
        .help(enabled ? "Hold to talk (push-to-talk)" : "Configure ElevenLabs in Settings to enable voice")
        .accessibilityLabel(recording ? "Recording. Release to stop." : "Push to talk")
        .accessibilityAddTraits(.isButton)
    }
}

struct TranscriptReviewBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case let .reviewing(original, provider) = model.voice.state {
                HStack {
                    Text("Review transcript").font(.headline)
                    Text("from \(provider)\(model.transcriptDraft != original ? " · edited" : "")")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                TextEditor(text: $model.transcriptDraft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 64)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 6))
                HStack {
                    Text("Nothing is done until you send it.").font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Discard", role: .cancel) { model.discardTranscript() }
                    Button("Send transcript") { model.submitTranscript() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.transcriptDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(14)
        .background(Theme.panelRaised.opacity(0.6))
    }
}
