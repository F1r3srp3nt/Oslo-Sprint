import RelayAdapters
import RelayCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyEntry = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Settings", subtitle: "Speech services, reasoning and challenge connections.")
                elevenLabsPanel
                speechBehaviourPanel
                reasoningPanel
                wybePanel
            }
            .padding(18)
        }
    }

    private var elevenLabsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ElevenLabs — speech input and output").font(.headline)
                    Spacer()
                    StatusPill(text: model.connectionStatus.label, color: Theme.color(model.connectionStatus))
                }
                Text("ElevenLabs only converts speech to text and text to speech. It does not decide what Relay does.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)

                LabeledRow(label: "API key") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            SecureField("Paste your ElevenLabs API key", text: $keyEntry)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 360)
                            Button("Save to Keychain") {
                                model.saveAPIKey(keyEntry)
                                keyEntry = ""
                            }
                            .disabled(keyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        HStack(spacing: 10) {
                            Text("Stored: \(model.apiKeyDisplay)").font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                            Button("Test connection") { model.testConnection() }
                                .disabled(model.apiKeyDisplay == "Not set" || model.connectionStatus == .checking)
                            Button("Remove", role: .destructive) { model.removeAPIKey() }
                                .disabled(model.apiKeyDisplay == "Not set")
                        }
                        Text("Stored only in your macOS Keychain under Relay's own entry. Never written to logs, exports or files. "
                             + "\u{201C}Connected\u{201D} is shown only after a real request to ElevenLabs succeeds.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                LabeledRow(label: "Voice ID") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Voice ID from your ElevenLabs voice library", text: $model.elevenLabs.voiceID)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                            Button("Use docs example voice") {
                                model.elevenLabs.voiceID = ElevenLabsConfiguration.documentationExampleVoiceID
                            }
                        }
                        Text("Without a voice ID, replies stay text-only.").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                LabeledRow(label: "Models") {
                    HStack {
                        TextField("Speech to text", text: $model.elevenLabs.speechToTextModel).textFieldStyle(.roundedBorder)
                        TextField("Text to speech", text: $model.elevenLabs.textToSpeechModel).textFieldStyle(.roundedBorder)
                        TextField("Output format", text: $model.elevenLabs.outputFormat).textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: 560)
                }
                Text("Requests go to \(model.elevenLabs.baseURL.absoluteString): POST /v1/speech-to-text (your recording, only while you hold the talk button), "
                     + "POST /v1/text-to-speech/{voice} (reply text), GET /v1/user (connection test).")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var speechBehaviourPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Speech behaviour").font(.headline)
                Toggle("Speak replies automatically when speech output is configured", isOn: $model.autoSpeak)
                Toggle("Send the training language as a transcription hint", isOn: $model.sendLanguageHint)
                Text("Recordings are temporary files deleted after transcription. Push-to-talk never records in the background.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var reasoningPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reasoning").font(.headline)
                Text("Engine: \(model.reasonerName)")
                Text("Commands and procedure questions are handled by deterministic rules and keyword matching over the loaded "
                     + "procedure. Answers are always quoted from the document; anything else is escalated. Flexible, open-ended "
                     + "question answering would need a separate language-model provider, which is not part of this milestone.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Text("Relay cannot run programs, browse files or change system settings.").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var wybePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wybe Night Shift").font(.headline)
                Text("Live connection: not configured. The official command list, API and credentials must come from the organisers "
                     + "(join page: nightshift-board.wybe.me/join). Until then only the labelled simulation runs.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
