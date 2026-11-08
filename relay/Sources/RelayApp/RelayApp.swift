import AppKit
import RelayAdapters
import RelayCore
import SwiftUI

@MainActor final class RelayAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Apply the stored appearance before the first window draws (Futuristic by default).
        DSAppearance.apply(.stored)
    }

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
    @AppStorage(DSAppearance.storageKey) private var appearance = DSAppearance.futuristic.rawValue

    init() {
        // Futuristic is the default; earlier builds always forced dark, so nothing explicit is lost.
        DSAppearance.migrateStoredPreference()
    }

    var body: some Scene {
        WindowGroup("Relay") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .dsAppearance(DSAppearance.resolve(appearance))
                .tint(DS.accent)
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
        // A fixed-width sidebar beside the detail pane in one HStack (no AppKit split view or
        // adaptive NavigationSplitView), so no section can collapse or blank the sidebar. The
        // window controls stay native.
        HStack(spacing: 0) {
            DSSidebar(groups: [DSSidebarGroup(title: "Workspace", items: AppSection.allCases.map(item))],
                      selection: $selection, topInset: 30, brandName: "RELAY", brandTagline: "Challenge assistant") {
                sidebarFooter
            }
            .frame(width: 228)
            .frame(maxHeight: .infinity)
            detail
                // Themed defaults for every screen; explicit styles (primary, link, plain) win.
                .buttonStyle(.dsSecondary)
                .textFieldStyle(.ds)
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
        switch speechTone {
        case .success: return "checkmark.circle"
        case .danger: return "exclamationmark.triangle"
        case .neutral: return "keyboard"
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
            DSStatusRow(label: "Speech", value: model.readiness.summary, systemImage: speechSymbol, tone: speechTone),
            DSStatusRow(label: "Wybe runner", value: model.wybeRunning ? "Simulation running" : "Idle · simulation only",
                        systemImage: "testtube.2", tone: model.wybeRunning ? .simulation : .neutral),
            DSStatusRow(label: "Reasoning", value: model.reasonerName.isEmpty ? "Built-in rules" : model.reasonerName,
                        systemImage: "list.bullet.indent", tone: .neutral),
            DSStatusRow(label: "Build", value: BuildInfo.current.summary, systemImage: "shippingbox", tone: .neutral)
        ])
        .padding(DS.Space.s)
    }

    /// Derived from the separate readiness checks: a saved key alone never reads as "connected".
    private var speechTone: DSTone {
        let r = model.readiness
        if !r.keySaved { return .neutral }
        if r.speechInput.problem != nil || r.speechOutput.problem != nil { return .danger }
        if r.speechInput.isPassed && (r.speechOutput.isPassed || !r.voiceIDSet) { return .success }
        return .warning
    }
}
