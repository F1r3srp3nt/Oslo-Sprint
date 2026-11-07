import SwiftUI
import AppKit
import TokenLabCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $store.selectedSection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationTitle("Token Lab")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Local prototype", systemImage: "desktopcomputer")
                    Text("No model connected").font(.caption).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            Group {
                switch store.selectedSection ?? .overview {
                case .overview: OverviewView()
                case .workspace: WorkspaceView()
                case .library: LibraryView()
                case .experiments: ExperimentsView()
                case .settings: SettingsView()
                }
            }
            .navigationTitle((store.selectedSection ?? .overview).rawValue)
            .toolbar {
                ToolbarItemGroup {
                    Button { store.openProject() } label: { Label("Open project", systemImage: "folder") }
                    Button { store.saveProject() } label: { Label("Save project", systemImage: "square.and.arrow.down") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Circle().fill(store.hasUnsavedChanges ? Color.orange : Color.secondary).frame(width: 6, height: 6)
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(12).background(.bar)
            }
        }
        .frame(minWidth: 940, minHeight: 640)
        .alert("Unable to complete action", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct MetricView: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Make room for what matters.").font(.largeTitle.bold())
                Text("Compose a prompt, choose its context, and inspect the trade-offs before using it.")
                    .foregroundStyle(.secondary)
                HStack {
                    MetricView(title: "Workspace blocks", value: "\(store.document.draft.blocks.count)")
                    MetricView(title: "Library items", value: "\(store.document.library.count)")
                    MetricView(title: "Saved experiments", value: "\(store.document.experiments.count)")
                }
                GroupBox("Start working") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your instructions stay intact. Optional context is selected using its priority and the estimated token budget.")
                        HStack {
                            Button("Open workspace") { store.selectedSection = .workspace }.buttonStyle(.borderedProminent)
                            Button("Load example project") { store.loadExample() }
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Prototype capabilities") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Ready: context selection, exact deduplication, decision log and project export", systemImage: "checkmark.circle")
                        Label("Next: model-specific token counts and relevance ranking", systemImage: "circle.dashed")
                        Label("Not implemented: model calls, cost measurement or automatic quality evaluation", systemImage: "circle.dashed")
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Token counts are rough UTF-8 byte estimates. Reduction alone does not establish answer quality or monetary savings.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Compose → select → review").font(.title2.bold())
                        Text("Preview selection without calling a model.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Preview optimisation") { store.preview() }.buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                }
                HStack {
                    MetricView(title: "Original estimate", value: store.currentReport.map { String($0.before) } ?? "—")
                    MetricView(title: "Selected estimate", value: store.currentReport.map { String($0.after) } ?? "—")
                    MetricView(title: "Estimated reduction", value: store.currentReport.map { "\($0.savingsPercent)%" } ?? "—")
                }
                GroupBox("Protected instructions and current request") {
                    TextEditor(text: $store.document.draft.instructions).font(.system(.body, design: .monospaced))
                        .frame(minHeight: 110).padding(4).accessibilityLabel("Protected instructions and current request")
                }
                HStack {
                    Text("Context blocks").font(.headline)
                    Spacer()
                    Text("Estimated token budget")
                    TextField("Budget", value: $store.document.draft.budget, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                        .accessibilityLabel("Estimated token budget")
                    Button { store.document.draft.blocks.append(ContextBlock()) } label: { Label("Add context", systemImage: "plus") }
                        .disabled(store.document.draft.blocks.count >= 500)
                }
                if store.document.draft.blocks.isEmpty {
                    Text("Add a context block or reuse one from Context Library.").foregroundStyle(.secondary).padding(.vertical)
                }
                ForEach($store.document.draft.blocks) { $block in
                    ContextEditor(block: $block, onLibrary: { store.addToLibrary(block) }, onDelete: {
                        store.document.draft.blocks.removeAll { $0.id == block.id }
                    })
                }
                if let report = store.currentReport { ReportView(report: report) }
                else {
                    GroupBox {
                        Text("Run Preview optimisation after editing to see the current selection. Stale results are hidden.")
                            .foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(28)
        }
    }
}

struct ContextEditor: View {
    @Binding var block: ContextBlock
    var onLibrary: (() -> Void)? = nil
    var onDelete: () -> Void
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Context title", text: $block.title).textFieldStyle(.roundedBorder)
                    Picker("Category", selection: $block.category) {
                        ForEach(ContextCategory.allCases) { category in Text(category.rawValue).tag(category) }
                    }.labelsHidden().frame(width: 130).accessibilityLabel("Context category")
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.help("Remove this context")
                }
                TextEditor(text: $block.text).font(.system(.body, design: .monospaced)).frame(minHeight: 85)
                    .accessibilityLabel("Context text")
                HStack {
                    Toggle("Required", isOn: $block.required).toggleStyle(.checkbox)
                    Picker("Priority", selection: $block.priority) {
                        Text("Low").tag(1); Text("Medium").tag(2); Text("High").tag(3)
                    }.frame(width: 180)
                    Spacer()
                    Text("≈ \(Optimizer.estimate(block.text)) tokens").font(.caption).foregroundStyle(.secondary)
                    if let onLibrary { Button("Copy to library", action: onLibrary) }
                }
            }.padding(6)
        }
    }
}

struct ReportView: View {
    @EnvironmentObject private var store: AppStore
    let report: OptimizationReport
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Selection preview").font(.headline)
                Spacer()
                Button("Save experiment") { store.saveExperiment() }
                Button("Export report…") { store.exportReport() }
            }
            if report.overBudget {
                Label("Required content exceeds the budget. It has been kept intact.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            GroupBox("Selected prompt") {
                ScrollView {
                    Text(report.optimized.isEmpty ? "No content fits the current budget." : report.optimized)
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(minHeight: 100, maxHeight: 280)
            }
            ForEach(report.decisions) { decision in
                HStack(alignment: .top) {
                    Image(systemName: decision.kept ? "checkmark.circle" : "minus.circle").foregroundStyle(decision.kept ? Color.green : Color.secondary)
                    VStack(alignment: .leading) {
                        Text("\(decision.kept ? "Keep" : "Exclude"): \(decision.title.isEmpty ? "Untitled context" : decision.title)")
                        Text(decision.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Review exclusions for lost information. Answer quality has not been evaluated.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
