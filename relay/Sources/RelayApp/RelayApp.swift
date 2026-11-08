import AppKit
import RelayAdapters
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
    @State private var selection: AppSection? = .assistant

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(badge(for: section))
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            ZStack {
                Theme.background.ignoresSafeArea()
                detail
            }
        }
        .alert("Relay", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
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
        switch selection ?? .assistant {
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
            Divider()
            HStack(spacing: 6) {
                Circle().fill(Theme.color(model.readiness)).frame(width: 7, height: 7)
                Text(model.readiness.summary).font(.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            if model.wybeRunning {
                HStack(spacing: 6) {
                    Circle().fill(Theme.simulation).frame(width: 7, height: 7)
                    Text("Wybe simulation running").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
