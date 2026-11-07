import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "Quit without saving?"
        alert.informativeText = "Your project has unsaved changes. Cancel and use File → Save Project to keep them."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct TokenLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    @AppStorage("appearance") private var appearance = "System"
    var body: some Scene {
        Window("Token Lab", id: "main") {
            ContentView().environmentObject(store)
                .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { store.newProject() }.keyboardShortcut("n")
                Button("Open Project…") { store.openProject() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Project…") { store.saveProject() }.keyboardShortcut("s")
                Button("Export Current Report…") { store.exportReport() }.disabled(store.currentReport == nil)
            }
        }
    }
}
