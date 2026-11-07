import SwiftUI
import AppKit
import TokenLabCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    /// Single-selection binding that never becomes nil, so clicking empty sidebar space
    /// cannot clear the highlight while the detail pane keeps showing a section.
    private var sectionSelection: Binding<AppSection?> {
        Binding(get: { store.selectedSection ?? .overview },
                set: { if let section = $0 { store.selectedSection = section } })
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
        List(selection: sectionSelection) {
            Section("Project") {
                ForEach([AppSection.overview, .workspace, .comparison, .library, .experiments]) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }
            Section("App") {
                Label(AppSection.settings.title, systemImage: AppSection.settings.symbol).tag(AppSection.settings)
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Sections")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Local only", systemImage: "desktopcomputer").font(.callout)
                Text("No model connected · no network use").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detail: some View {
        let section = store.selectedSection ?? .overview
        return Group {
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
                .fill(store.hasUnsavedChanges ? Color.orange : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(store.hasUnsavedChanges ? "Unsaved changes" : "Saved")
                .font(.caption.weight(.medium))
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
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}
