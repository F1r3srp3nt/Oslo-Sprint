import SwiftUI
import TokenLabCore

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var category: ContextCategory?
    private func matches(_ block: ContextBlock) -> Bool {
        (category == nil || block.category == category) && (search.isEmpty || block.title.localizedCaseInsensitiveContains(search) || block.text.localizedCaseInsensitiveContains(search))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Reusable context").font(.title2.bold())
                    Spacer()
                    Button("New library item") { store.document.library.append(ContextBlock()) }
                        .disabled(store.document.library.count >= 500)
                }
                Text("Keep reference text, conversations, code and tool outputs organised. Inserting an item creates an independent workspace copy.").foregroundStyle(.secondary)
                HStack {
                    TextField("Search title or text", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(Optional<ContextCategory>.none)
                        ForEach(ContextCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }.frame(width: 230)
                }
                if !store.document.library.contains(where: matches) {
                    ContentUnavailableView("No context items", systemImage: "books.vertical", description: Text("Create an item or copy one from the workspace."))
                }
                ForEach($store.document.library) { $block in
                    if matches(block) {
                        VStack(alignment: .trailing) {
                            ContextEditor(block: $block, onDelete: { store.document.library.removeAll { $0.id == block.id } })
                            Button("Use in workspace") { store.useContext(block) }
                        }
                    }
                }
            }.padding(28)
        }
    }
}

struct ExperimentsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingDeletion: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Inspect the trade-offs.").font(.title2.bold())
                Text("Saved previews preserve their input and selected context. Quality labels are your manual assessment, not an automated benchmark.").foregroundStyle(.secondary)
                if store.document.experiments.isEmpty {
                    ContentUnavailableView("No experiments yet", systemImage: "chart.bar.xaxis", description: Text("Preview a workspace, then choose Save experiment."))
                }
                ForEach($store.document.experiments) { $experiment in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                TextField("Experiment name", text: $experiment.name).textFieldStyle(.roundedBorder)
                                Text(experiment.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                Button(role: .destructive) { pendingDeletion = experiment.id } label: { Image(systemName: "trash") }
                                    .help("Delete experiment")
                            }
                            HStack {
                                MetricView(title: "Original estimate", value: "\(experiment.report.before)")
                                MetricView(title: "Selected estimate", value: "\(experiment.report.after)")
                                MetricView(title: "Estimated reduction", value: "\(experiment.report.savingsPercent)%")
                            }
                            Picker("Quality review", selection: $experiment.review) {
                                ForEach(QualityReview.allCases) { Text($0.rawValue).tag($0) }
                            }
                            TextField("Review notes: what changed, what was lost?", text: $experiment.notes, axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(2...6)
                            DisclosureGroup("Original and selected prompts") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Original").font(.headline)
                                    Text(experiment.report.original).textSelection(.enabled)
                                    Divider()
                                    Text("Selected").font(.headline)
                                    Text(experiment.report.optimized).textSelection(.enabled)
                                }.font(.system(.body, design: .monospaced)).padding()
                            }
                        }.padding(8)
                    }
                }
            }.padding(28)
        }
        .confirmationDialog("Delete this experiment?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeletion { store.document.experiments.removeAll { $0.id == id } }
                pendingDeletion = nil
            }
        } message: { Text("This removes it from the current project. Existing saved files remain unchanged until you save again.") }
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "System"
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark")
                }
            }
            Section("Token counting") {
                LabeledContent("Active counter", value: "UTF-8 bytes ÷ 4 (estimate)")
                Text("Model-specific tokenization and chat-message overhead are not implemented. These estimates must not be presented as provider usage or billing figures.").foregroundStyle(.secondary)
            }
            Section("Data and privacy") {
                LabeledContent("Model connections", value: "None")
                LabeledContent("Automatic cloud sync", value: "None")
                Text("Project content stays in memory until you choose Save Project. Saved JSON includes prompt text, context and experiments in plain text. Appearance is stored locally. Closing with unsaved changes prompts you before quitting.")
            }
            Section("About this build") {
                LabeledContent("Version", value: "0.2.0 · macOS skeleton")
                Text("Token Lab is a temporary descriptive label. No company identity, logo, external accounts or previous product integrations are included.")
            }
        }.formStyle(.grouped)
    }
}
