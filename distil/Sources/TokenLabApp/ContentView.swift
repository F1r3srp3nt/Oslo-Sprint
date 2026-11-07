import SwiftUI
import AppKit
import TokenLabCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSection) {
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Local only", systemImage: "desktopcomputer").font(.callout)
                    Text("No model connected · no network use").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            let section = store.selectedSection ?? .overview
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
            .navigationTitle(section.title)
            .navigationSubtitle(store.windowSubtitle)
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
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
