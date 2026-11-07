import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TokenLabCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var encodings: EncodingStore
    @AppStorage(StoredPreference.appearance) private var appearance = "System"
    @AppStorage(StoredPreference.autoPreview) private var autoPreview = true
    @State private var importing: BPEEncodingID?

    /// Counter choice expressed as a simple menu value.
    private enum CounterOption: Hashable { case approximate, bpe(BPEEncodingID) }

    private var counterOption: Binding<CounterOption> {
        Binding(
            get: {
                switch store.document.settings.counter {
                case .approximate: return .approximate
                case .bpe(let id): return .bpe(id)
                }
            },
            set: { option in
                switch option {
                case .approximate:
                    if case .approximate = store.document.settings.counter { return }
                    store.document.settings.counter = .approximate(bytesPerToken: 4)
                case .bpe(let id):
                    store.document.settings.counter = .bpe(encoding: id)
                }
            })
    }

    private var bytesPerToken: Binding<Int> {
        Binding(
            get: { if case .approximate(let n) = store.document.settings.counter { return n }; return 4 },
            set: { store.document.settings.counter = .approximate(bytesPerToken: min(max($0, 1), 8)) })
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("Match System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
                .pickerStyle(.radioGroup)
            }

            Section {
                Picker("Counter", selection: counterOption) {
                    Text("Approximate (UTF-8 bytes ÷ N)").tag(CounterOption.approximate)
                    ForEach(BPEEncodingID.allCases) { id in
                        Text("\(id.rawValue) text tokens\(encodings.state(id) == .notInstalled ? " — not imported" : "")").tag(CounterOption.bpe(id))
                    }
                }
                if case .approximate = store.document.settings.counter {
                    Stepper("Bytes per token: \(bytesPerToken.wrappedValue)", value: bytesPerToken, in: CounterChoice.bytesPerTokenRange)
                    Text("A rough heuristic. English prose is often near 4 bytes per token; code, other languages and emoji vary widely.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let descriptor = store.activeCounterDescriptor {
                    LabeledContent("Encoding", value: descriptor.encoding)
                    LabeledContent("Version") { Text(descriptor.version).textSelection(.enabled).multilineTextAlignment(.trailing) }
                    Text(descriptor.scope).font(.caption).foregroundStyle(.secondary)
                } else if case .bpe(let id) = store.document.settings.counter {
                    Label(encodings.state(id) == .notInstalled
                          ? "Import the \(id.rawValue) file below to use this counter."
                          : "\(id.rawValue): \(encodings.state(id).label). It loads when the preview runs.",
                          systemImage: "info.circle")
                        .font(.callout)
                }
            } header: {
                Text("Token counting for this project")
            } footer: {
                Text("Saved in the project file and recorded in every preview and experiment, so results can be reproduced. Counts never include chat message formatting or provider overhead.")
            }

            Section {
                ForEach(BPEEncodingID.allCases) { id in
                    EncodingRow(id: id, importing: importing == id, onImport: { importEncoding(id) }, onRemove: { remove(id) })
                }
            } header: {
                Text("Model tokenizer files")
            } footer: {
                Text("These vocabularies come from the open-source tiktoken project (MIT licence). They are not bundled and the app never downloads them: download a file yourself from the address shown, then import it. A file is accepted only if its SHA-256 matches the published value. Model families are listed as mapped in tiktoken 0.14.0. No offline tokenizer is published for some other providers’ current models; counting for those would need the provider’s own token-counting service through a future adapter.")
            }

            Section {
                RankingMethodView()
            } header: {
                Text("Task relevance ranking")
            } footer: {
                Text("Ranking runs locally and deterministically. It is kept separate from token counting and selection so a stronger method can replace it later; the ranker’s name and version are recorded in every report.")
            }

            Section("Preview") {
                Toggle("Update the preview automatically after edits", isOn: $autoPreview)
                Text("When off, use Prompt → Update Preview (⌘↩). Previews are always hidden as soon as inputs or settings change.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Local data") {
                LabeledContent("Projects") {
                    Text("Only the JSON files you save. No autosave, no cloud sync.").multilineTextAlignment(.trailing)
                }
                LabeledContent("Model connections", value: "None — no network requests are made")
                LabeledContent("Credentials", value: "None stored")
                LabeledContent("Preferences") {
                    HStack {
                        Text("Theme and auto-preview")
                        Button("Reset") {
                            UserDefaults.standard.removeObject(forKey: StoredPreference.appearance)
                            UserDefaults.standard.removeObject(forKey: StoredPreference.autoPreview)
                            appearance = "System"; autoPreview = true
                            store.status = "Preferences reset."
                        }
                    }
                }
                LabeledContent("Imported tokenizer files") {
                    HStack {
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: encodings.directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(encodings.directory)
                        }
                        Button("Remove All…", role: .destructive) { removeAll() }
                            .disabled(BPEEncodingID.allCases.allSatisfy { encodings.state($0) == .notInstalled })
                    }
                }
                Text(encodings.directory.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Project files are plain JSON and include all prompt text, context, answers and notes. Saving and exporting warn if text looks like an API key or private key.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About this build") {
                LabeledContent("Version", value: "0.4.0 · development build")
                LabeledContent("Project file schema", value: "\(ProjectDocument.currentSchemaVersion) (reads 1–\(ProjectDocument.currentSchemaVersion))")
                LabeledContent("Selection engine", value: SelectionReport.currentEngineVersion)
                Text("Distil is the working product name. Internal identifiers (package, module and bundle identifier) are unchanged. No company identity, logos, accounts or third-party code are included.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func importEncoding(_ id: BPEEncodingID) {
        let panel = NSOpenPanel()
        panel.message = "Choose the official \(id.spec.fileName) file."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = id
        Task {
            do {
                try await encodings.importFile(id, from: url)
                store.status = "Imported and verified \(id.rawValue)."
            } catch {
                store.errorMessage = "The file was not imported.\n\n\(error.localizedDescription)"
            }
            importing = nil
        }
    }

    private func remove(_ id: BPEEncodingID) {
        do { try encodings.remove(id); store.status = "Removed \(id.rawValue)." }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func removeAll() {
        guard Dialogs.confirm(title: "Remove all imported tokenizer files?",
                              message: "Projects that use them will need the files imported again before previews can run. Saved experiments are not changed.",
                              confirmTitle: "Remove All") else { return }
        do { try encodings.removeAll(); store.status = "Removed imported tokenizer files." }
        catch { store.errorMessage = error.localizedDescription }
    }
}

struct EncodingRow: View {
    @EnvironmentObject private var encodings: EncodingStore
    let id: BPEEncodingID
    let importing: Bool
    let onImport: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let spec = id.spec
        let state = encodings.state(id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(id.rawValue).font(.headline.monospaced())
                Pill(text: state.label, color: state == .ready ? DS.success : DS.textSecondary, systemImage: state == .ready ? "checkmark.circle" : "circle.dashed")
                Spacer()
                if importing { ProgressView().controlSize(.small) }
                Button(state == .notInstalled ? "Import File…" : "Replace…", action: onImport).disabled(importing)
                if state != .notInstalled {
                    Button("Remove", role: .destructive, action: onRemove).disabled(importing)
                }
            }
            Text("Model families: \(spec.modelFamilies.joined(separator: ", "))")
                .font(.caption)
            Text("Source: \(spec.officialFileURL)")
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            Text("SHA-256: \(spec.expectedSHA256)")
                .font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
