import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TokenLabCore

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", workspace = "Prompt Workspace", library = "Context Library", experiments = "Experiments", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .workspace: return "text.alignleft"
        case .library: return "books.vertical"
        case .experiments: return "chart.bar.xaxis"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var document = ProjectDocument()
    @Published var selectedSection: AppSection? = .overview
    @Published var report: OptimizationReport?
    @Published var errorMessage: String?
    @Published var status = "Local session. Save a project file to keep your work."
    @Published var dirty = false
    private var lastSaved = ProjectDocument()
    var currentReport: OptimizationReport? { report?.input == document.draft ? report : nil }
    var hasUnsavedChanges: Bool { document != lastSaved }
    func preview() {
        do {
            guard !Optimizer.assemble(document.draft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LabError.invalid("Add instructions or context first.") }
            report = try Optimizer.run(document.draft)
            status = "Preview ready. Review every exclusion before using the prompt."
        } catch { errorMessage = error.localizedDescription }
    }
    func saveExperiment() {
        guard let report = currentReport else { return }
        guard document.experiments.count < 500 else { errorMessage = "Experiment limit reached."; return }
        document.experiments.insert(Experiment(name: "Experiment \(document.experiments.count + 1)", report: report), at: 0)
        status = "Experiment added to this session. Save the project to keep it."
    }
    func addToLibrary(_ block: ContextBlock) {
        guard document.library.count < 500 else { errorMessage = "Library limit reached."; return }
        var copy = block; copy.id = UUID(); document.library.append(copy)
        status = "Context copied to the library. Save the project to keep it."
    }
    func useContext(_ block: ContextBlock) {
        guard document.draft.blocks.count < 500 else { errorMessage = "Workspace block limit reached."; return }
        var copy = block; copy.id = UUID(); document.draft.blocks.append(copy); selectedSection = .workspace
    }
    func confirmDiscard() -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert(); alert.messageText = "Replace unsaved work?"
        alert.informativeText = "Save your project first if you want to keep the current workspace, library and experiments."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Replace")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func newProject() {
        guard confirmDiscard() else { return }
        document = ProjectDocument(); lastSaved = document; report = nil; status = "New local session."
    }
    func loadExample() {
        guard confirmDiscard() else { return }
        var fresh = ProjectDocument()
        fresh.draft.instructions = "Write a short handover for a new team member. Use only the supplied project facts. Do not invent deadlines."
        fresh.draft.budget = 100
        fresh.draft.blocks = [
            ContextBlock(title: "Delivery requirements", text: "The prototype must run locally. It must show every removed context block. No provider account is required.", priority: 3, required: true),
            ContextBlock(title: "Current status", text: "The editor and context selector are implemented. Model-specific token counts and quality benchmarks are not implemented.", priority: 3),
            ContextBlock(title: "Repeated status", text: "The editor and context selector are implemented. Model-specific token counts and quality benchmarks are not implemented.", priority: 2),
            ContextBlock(title: "Old chat", text: "We discussed lunch plans and moving a meeting room. There were several unrelated messages about coffee and the weather.", category: .conversation, priority: 1)
        ]
        document = fresh; report = nil; selectedSection = .workspace; status = "Example loaded. Preview to inspect the selection."
    }
    func saveProject() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Token-Lab-Project.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            lastSaved = document; status = "Saved \(url.lastPathComponent)."
        } catch { errorMessage = error.localizedDescription }
    }
    func openProject() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20_000_000 else { throw LabError.invalid("Project files are limited to 20 MB.") }
            let loaded = try JSONDecoder().decode(ProjectDocument.self, from: Data(contentsOf: url))
            try loaded.validate()
            guard confirmDiscard() else { return }
            document = loaded; lastSaved = loaded; report = nil; status = "Opened \(url.lastPathComponent)."
        } catch { errorMessage = error.localizedDescription }
    }
    func exportReport() {
        guard let currentReport else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Token-Lab-Report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(currentReport).write(to: url, options: .atomic)
            status = "Report exported. It contains the original and selected prompt text."
        } catch { errorMessage = error.localizedDescription }
    }
}
