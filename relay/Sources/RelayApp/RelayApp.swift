import AppKit
import RelayCore
import SwiftUI

final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run` (no app bundle): become a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct RelayApp: App {
    @NSApplicationDelegateAdaptor(RelayAppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Relay") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case assistant, tasks, training, wybe, activity, settings
    var id: Self { self }

    var title: String {
        switch self {
        case .assistant: return "Assistant"
        case .tasks: return "Tasks"
        case .training: return "Warehouse Training"
        case .wybe: return "Wybe Runner"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .assistant: return "waveform"
        case .tasks: return "checklist"
        case .training: return "shippingbox"
        case .wybe: return "moon.zzz"
        case .activity: return "list.bullet.rectangle"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: AppSection = .assistant

    var body: some View {
        // A persistent split view (not an adaptive NavigationSplitView), so the sidebar never
        // collapses when a section needs more width. The window controls stay native.
        HSplitView {
            DSSidebar(groups: [DSSidebarGroup(title: "Workspace", items: AppSection.allCases.map(item))],
                      selection: $selection, topInset: 30, brandName: "RELAY", brandTagline: "Challenge assistant") {
                sidebarFooter
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 300, maxHeight: .infinity)
            detail
                .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .background(DSBackground())
        .groupBoxStyle(DSPanelGroupBoxStyle())
        .alert("Relay", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    private func item(_ section: AppSection) -> DSSidebarItem<AppSection> {
        let count = badge(for: section)
        let meaning: String
        switch section {
        case .tasks: meaning = "\(count) need attention"
        case .wybe: meaning = "simulation running"
        default: meaning = "\(count)"
        }
        return DSSidebarItem(id: section, title: section.title, symbol: section.symbol, badge: count, badgeDescription: meaning)
    }

    private var speechSymbol: String {
        switch model.connectionStatus {
        case .connected: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .unconfigured: return "keyboard"
        default: return "circle.dashed"
        }
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .tasks: return model.attentionCount
        case .wybe: return model.wybeRunning ? 1 : 0
        default: return 0
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .assistant: AssistantView()
        case .tasks: TasksView()
        case .training: TrainingView()
        case .wybe: WybeRunnerView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }

    private var sidebarFooter: some View {
        DSStatusCard(rows: [
            DSStatusRow(label: "Speech", value: model.connectionStatus.label, systemImage: speechSymbol, tone: speechTone),
            DSStatusRow(label: "Wybe runner", value: model.wybeRunning ? "Simulation running" : "Idle · simulation only",
                        systemImage: "testtube.2", tone: model.wybeRunning ? .simulation : .neutral),
            DSStatusRow(label: "Reasoning", value: model.reasonerName.isEmpty ? "Built-in rules" : model.reasonerName,
                        systemImage: "list.bullet.indent", tone: .neutral)
        ])
        .padding(DS.Space.s)
    }

    private var speechTone: DSTone {
        switch model.connectionStatus {
        case .connected: return .success
        case .failed: return .danger
        case .checking, .configuredUnverified: return .warning
        case .unconfigured: return .neutral
        }
    }
}
