import SwiftUI
import AppKit
import TokenLabCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    /// Non-optional selection for the sidebar, so the highlight can never be cleared.
    private var sectionSelection: Binding<AppSection> {
        Binding(get: { store.selectedSection ?? .overview },
                set: { store.selectedSection = $0 })
    }

    var body: some View {
        // A plain split view rather than an adaptive NavigationSplitView: the sidebar is a
        // persistent pane that the system never collapses when a detail section needs more width.
        HSplitView {
            sidebar
                .frame(minWidth: Self.sidebarMinWidth, idealWidth: 210, maxWidth: 280, maxHeight: .infinity)
            detail
                .frame(minWidth: Self.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .background(DSBackground())
        .groupBoxStyle(DSPanelGroupBoxStyle())
        .tint(DS.accent)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.openProject() } label: { Label("Open Project", systemImage: "folder") }
                    .help("Open a project file (⌘O)")
                Button { _ = store.save() } label: { Label("Save Project", systemImage: "square.and.arrow.down") }
                    .help("Save the project (⌘S)")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(WindowCloseGuard(isEdited: store.hasUnsavedChanges) { window in
            store.requestCloseWindow(window)
        })
        .alert("Unable to complete action",
               isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    /// Window minimum (760) ≥ sidebar minimum + divider + detail minimum. Each section's own panes
    /// must fit within `detailMinWidth`.
    static let sidebarMinWidth: CGFloat = 180
    static let detailMinWidth: CGFloat = 560

    private var sidebar: some View {
        DSSidebar(groups: [
            DSSidebarGroup(title: "Project", items: [AppSection.overview, .workspace, .comparison, .library, .experiments].map(item)),
            DSSidebarGroup(title: "App", items: [item(.settings)])
        ], selection: sectionSelection, topInset: DS.Space.s, brandName: "DISTIL", brandTagline: "Context selection lab") {
            DSStatusCard(rows: [
                DSStatusRow(label: "Project", value: store.hasUnsavedChanges ? "Unsaved changes" : "Saved",
                            systemImage: store.hasUnsavedChanges ? "pencil.circle" : "checkmark.circle",
                            tone: store.hasUnsavedChanges ? .warning : .neutral),
                DSStatusRow(label: "Environment", value: "Local only", systemImage: "desktopcomputer", tone: .accent),
                DSStatusRow(label: "Model connection", value: "None · no network use", systemImage: "bolt.horizontal.circle", tone: .neutral)
            ])
            .padding(DS.Space.s)
        }
    }

    private func item(_ section: AppSection) -> DSSidebarItem<AppSection> {
        let count = badge(for: section)
        let noun: String
        switch section {
        case .workspace: noun = "context blocks"
        case .library: noun = "library items"
        case .experiments: noun = "experiments"
        default: noun = ""
        }
        return DSSidebarItem(id: section, title: section.title, symbol: section.symbol, badge: count, badgeDescription: "\(count) \(noun)")
    }

    private var detail: some View {
        let section = store.selectedSection ?? .overview
        return VStack(spacing: 0) {
            DSPageHeader(title: section.title, subtitle: section.subtitle, eyebrow: "DISTIL  /  \(section.title.uppercased())")
            Group {
                switch section {
                case .overview: OverviewView()
                case .workspace: WorkspaceView()
                case .comparison: ComparisonView()
                case .library: LibraryView()
                case .experiments: ExperimentsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(section.title)
        .navigationSubtitle(store.windowSubtitle)
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .workspace: return store.document.draft.blocks.count
        case .library: return store.document.library.count
        case .experiments: return store.document.experiments.count
        default: return 0
        }
    }
}

struct StatusBar: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.hasUnsavedChanges ? DS.warning : DS.textTertiary)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(store.hasUnsavedChanges ? "Unsaved changes" : "Saved")
                .font(.caption.weight(.medium))
                .foregroundStyle(store.hasUnsavedChanges ? DS.warning : DS.textSecondary)
            Text("·").foregroundStyle(.tertiary)
            Text(store.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(store.status)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DS.surface.opacity(0.85))
        .overlay(alignment: .top) { Rectangle().fill(DS.accent.opacity(0.16)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
