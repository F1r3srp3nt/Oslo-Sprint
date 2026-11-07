import SwiftUI
import TokenLabCore

/// Runs the same input through four fixed configurations and shows them side by side.
struct ComparisonView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedBlock: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.runComparison() } label: { Label("Run Comparison", systemImage: "arrow.clockwise") }
                    .help("Run all four configurations on the current input (⇧⌘R)")
                Button { store.saveComparison() } label: { Label("Save as Experiments", systemImage: "flask") }
                    .disabled(store.currentComparison == nil)
                    .help("Save four linked, reproducible experiment snapshots")
            }
        }
        .onAppear {
            if store.currentComparison == nil && !store.isComparing && !store.workspaceIsEmpty { store.runComparison() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Same input, four configurations").font(.title3.weight(.semibold))
                if store.isComparing { ProgressView().controlSize(.small) }
                Spacer()
            }
            Text("Budget \(store.document.settings.budget) · counter: \(store.activeCounterDescriptor?.displayName ?? store.document.settings.counter.shortName) · exact dedupe before budget: \(store.document.settings.deduplicateBeforeBudget ? "on" : "off"). Only the strategy differs between columns.")
                .font(.caption).foregroundStyle(.secondary)
            Label("Token counts are input estimates, not measured cost. Keyword matches do not show that a block is useful or an answer correct. Answer quality is “Not evaluated” until answers are recorded and reviewed in Experiments.",
                  systemImage: "exclamationmark.shield")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    @ViewBuilder private var content: some View {
        if let entries = store.currentComparison {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 18) {
                    summaryGrid(entries)
                    matrix(entries)
                    if let id = selectedBlock { reasons(for: id, entries) }
                    savedGroups
                }
                .padding(14)
            }
        } else if let error = store.comparisonError {
            ContentUnavailableView {
                Label("Comparison unavailable", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button("Open Settings") { store.selectedSection = .settings }
                Button("Try Again") { store.runComparison() }
            }
        } else if store.workspaceIsEmpty {
            ContentUnavailableView {
                Label("Nothing to compare", systemImage: "rectangle.split.3x1")
            } description: {
                Text("Write a task and add context in the Prompt Workspace, or load a demonstration.")
            } actions: {
                Menu("Load Demonstration") {
                    ForEach(DemoDataset.ID.allCases) { id in Button(id.title) { store.loadDemo(id) } }
                }
                .fixedSize()
            }
        } else {
            ContentUnavailableView {
                Label(store.hasStaleComparison ? "Comparison out of date" : "Not run yet", systemImage: "arrow.clockwise")
            } description: {
                Text(store.hasStaleComparison
                     ? "The input, settings or counter changed. Old results are hidden so they cannot be mistaken for the current input."
                     : "Run all four configurations on the current input.")
            } actions: {
                Button("Run Comparison") { store.runComparison() }.buttonStyle(.borderedProminent).disabled(store.isComparing)
            }
        }
    }

    // MARK: Summary

    private func summaryGrid(_ entries: [ComparisonEntry]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                ForEach(entries) { Text($0.variant.label).font(.subheadline.weight(.semibold)).frame(minWidth: 150, alignment: .leading) }
            }
            Divider()
            row("Input tokens", entries) { "\($0.selectedTokens)" }
            row("Counter", entries) { $0.counter.kind == .approximation ? "\($0.counter.encoding) (estimate)" : $0.counter.encoding }
            row("Est. change vs full", entries) { report in
                report.estimatedReduction == 0 ? "—" : "−\(report.estimatedReduction) (\(percentString(report.estimatedReductionPercent)))"
            }
            row("Retained / excluded", entries) { "\($0.keptCount) / \($0.removedCount)" }
            row("Budget", entries) { report in
                if !report.budgetEnforced { return report.overBudget ? "not applied · over by \(report.overBudgetBy)" : "not applied · within" }
                return report.overBudget ? "over by \(report.overBudgetBy) (protected content)" : "within \(report.budget)"
            }
            GridRow {
                Text("Answer quality").foregroundStyle(.secondary)
                ForEach(entries) { _ in Pill(text: "Not evaluated", color: .secondary) }
            }
        }
        .font(.callout)
    }

    private func row(_ title: String, _ entries: [ComparisonEntry], _ value: @escaping (SelectionReport) -> String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            ForEach(entries) { Text(value($0.report)).monospacedDigit().textSelection(.enabled) }
        }
    }

    // MARK: Block × variant matrix

    private func matrix(_ entries: [ComparisonEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Decisions by block").font(.headline)
            Text("Select a block to read each configuration’s reason. Keyword scores come from the task-relevance column.")
                .font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Block").font(.caption.weight(.semibold))
                    Text("Priority").font(.caption.weight(.semibold))
                    Text("Keyword score").font(.caption.weight(.semibold))
                    ForEach(entries) { Text($0.variant.strategy.shortName).font(.caption.weight(.semibold)) }
                }
                Divider()
                ForEach(Array(store.document.draft.blocks.enumerated()), id: \.element.id) { index, block in
                    let relevance = entries.last?.report.decisions.first(where: { $0.id == block.id })?.relevance
                    GridRow {
                        Button {
                            selectedBlock = selectedBlock == block.id ? nil : block.id
                        } label: {
                            HStack(spacing: 4) {
                                if block.required { Image(systemName: "lock.fill").foregroundStyle(.blue).font(.caption) }
                                Text("\(index + 1). \(block.title.isEmpty ? "Untitled context" : block.title)").lineLimit(1)
                            }
                            .frame(minWidth: 200, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedBlock == block.id ? Color.accentColor : Color.primary)
                        .accessibilityHint("Shows the reasons for this block")
                        Text(block.required ? "Required" : ContextPriority.label(block.priority)).font(.caption).foregroundStyle(.secondary)
                        Text(relevance.map { String(format: "%.2f", $0.score) } ?? "—").font(.caption.monospacedDigit())
                            .help(relevance.map { $0.matchedTerms.isEmpty ? "No task terms found" : $0.matchedTerms.map(\.term).joined(separator: ", ") } ?? "")
                        ForEach(entries) { entry in
                            if let decision = entry.report.decisions.first(where: { $0.id == block.id }) {
                                Label(decision.kind.label, systemImage: decision.kind.symbol)
                                    .font(.caption).foregroundStyle(decision.kind.color)
                                    .help(decision.reason)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reasons(for id: UUID, _ entries: [ComparisonEntry]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    if let decision = entry.report.decisions.first(where: { $0.id == id }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.variant.label).font(.caption.weight(.semibold))
                            DecisionRow(decision: decision, tokenUnit: entry.report.counter.kind == .approximation ? "est." : "tok.")
                        }
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Reasons for “\(store.document.draft.blocks.first(where: { $0.id == id })?.title ?? "")”")
        }
    }

    // MARK: Saved comparisons

    @ViewBuilder private var savedGroups: some View {
        let groups = Dictionary(grouping: store.document.experiments.filter { $0.comparison != nil }) { $0.comparison!.groupID }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved comparisons").font(.headline)
                ForEach(groups.keys.sorted { (groups[$0]?.first?.createdAt ?? .distantPast) > (groups[$1]?.first?.createdAt ?? .distantPast) }, id: \.self) { key in
                    let members = groups[key] ?? []
                    Button {
                        store.selectedExperimentID = members.first?.id
                        store.selectedSection = .experiments
                    } label: {
                        HStack {
                            Text(members.first?.comparison?.groupName ?? "Comparison")
                            Spacer()
                            Text("\(members.filter { $0.evaluation.isEvaluated }.count) of \(members.count) evaluated")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
