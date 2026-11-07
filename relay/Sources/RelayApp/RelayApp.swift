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
            DSSidebar(groups: [DSSidebarGroup(title: "Relay", items: AppSection.allCases.map(item))],
                      selection: $selection, topInset: 30) {
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: speechSymbol).imageScale(.small).foregroundStyle(Theme.color(model.connectionStatus))
                Text("Speech: \(model.connectionStatus.label)").font(.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            if model.wybeRunning {
                HStack(spacing: 6) {
                    Image(systemName: "testtube.2").imageScale(.small).foregroundStyle(Theme.simulation)
                    Text("Wybe simulation running").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
