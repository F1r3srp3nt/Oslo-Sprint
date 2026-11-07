import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import TokenLabCore

/// UserDefaults keys. Kept outside the main-actor store so views can use them in property wrappers.
enum StoredPreference {
    static let autoPreview = "autoPreview"
    static let appearance = "appearance"
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview, workspace, library, experiments, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .workspace: return "Prompt Workspace"
        case .library: return "Context Library"
        case .experiments: return "Experiments"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .workspace: return "text.alignleft"
        case .library: return "books.vertical"
        case .experiments: return "flask"
        case .settings: return "gearshape"
        }
    }
    var shortcutKey: Character {
        switch self {
        case .overview: return "1"
        case .workspace: return "2"
        case .library: return "3"
        case .experiments: return "4"
        case .settings: return "5"
        }
    }
}

/// UI state and actions. All persistence and selection rules live in TokenLabCore.
@MainActor final class AppStore: ObservableObject {
    @Published var session = ProjectSession() {
        didSet {
            if session.document.draft != oldValue.document.draft || session.document.settings != oldValue.document.settings {
                previewInputsChanged()
            }
        }
    }
    @Published var selectedSection: AppSection? = .overview
    @Published var selectedLibraryID: UUID?
    @Published var selectedExperimentID: UUID?
    @Published private(set) var report: SelectionReport?
    @Published private(set) var previewError: String?
    @Published private(set) var isPreviewing = false
    @Published var errorMessage: String?
    @Published var status = "Local session. Nothing is saved until you choose Save Project."

    let encodings: EncodingStore
    /// Set once the user has already confirmed discarding changes while closing the window.
    var allowTerminationWithoutPrompt = false

    private var previewGeneration = 0
    private var autoPreviewTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(encodings: EncodingStore? = nil) {
        self.encodings = encodings ?? EncodingStore()
        self.encodings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    // MARK: Derived state

    var document: ProjectDocument {
        get { session.document }
        set { session.document = newValue }
    }
    var hasUnsavedChanges: Bool { session.hasUnsavedChanges }
    var windowSubtitle: String { session.displayName + (hasUnsavedChanges ? " — Edited" : "") }

    var autoPreviewEnabled: Bool { UserDefaults.standard.object(forKey: StoredPreference.autoPreview) as? Bool ?? true }

    /// Descriptor of the project's counter, if it is available right now.
    var activeCounterDescriptor: TokenCounterDescriptor? {
        try? encodings.resolver().counter(for: document.settings.counter).descriptor
    }

    /// The last preview, only if it was produced from exactly the current inputs, settings and counter.
    var currentReport: SelectionReport? {
        guard let report, let counter = activeCounterDescriptor,
              report.isCurrent(draft: document.draft, settings: document.settings, counter: counter) else { return nil }
        return report
    }
    var hasStaleReport: Bool { report != nil && currentReport == nil }
    var workspaceIsEmpty: Bool {
        document.draft.instructions.isEmpty && document.draft.blocks.allSatisfy { $0.text.isEmpty }
    }

    /// Live per-text count for editor hints, using the project's counter when it is loaded.
    /// Large texts are not re-tokenized on every keystroke; they use the current preview's count instead.
    func liveCountLabel(_ text: String, decision: BlockDecision? = nil) -> String {
        guard let counter = try? encodings.resolver().counter(for: document.settings.counter) else { return "– tokens" }
        let descriptor = counter.descriptor
        if descriptor.kind == .approximation { return "≈ \(counter.count(text)) est. tokens" }
        if text.utf8.count <= 20_000 { return "\(counter.count(text)) \(descriptor.encoding) tokens" }
        if let decision { return "\(decision.standaloneTokens) \(descriptor.encoding) tokens" }
        return "– \(descriptor.encoding) tokens (updates with preview)"
    }

    // MARK: Preview

    func preview() {
        autoPreviewTask?.cancel()
        let draft = document.draft, settings = document.settings
        previewGeneration += 1
        let generation = previewGeneration
        isPreviewing = true
        Task { [weak self] in
            guard let self else { return }
            let result: Result<SelectionReport, Error>
            do {
                let counter = try await self.encodings.counter(for: settings.counter)
                result = await Task.detached(priority: .userInitiated) {
                    Result { try SelectionEngine.run(draft, settings: settings, counter: counter) }
                }.value
            } catch {
                result = .failure(error)
            }
            self.finishPreview(generation: generation, result: result)
        }
    }

    private func finishPreview(generation: Int, result: Result<SelectionReport, Error>) {
        guard generation == previewGeneration else { return } // a newer preview superseded this one
        isPreviewing = false
        switch result {
        case .success(let report):
            self.report = report
            previewError = nil
        case .failure(let error):
            report = nil
            previewError = error.localizedDescription
        }
    }

    private func previewInputsChanged() {
        previewError = nil
        autoPreviewTask?.cancel()
        guard autoPreviewEnabled else { return }
        autoPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.preview()
        }
    }

    // MARK: Workspace

    func addWorkspaceBlock() {
        guard document.draft.blocks.count < SelectionEngine.maxBlocks else { return fail("The workspace is limited to \(SelectionEngine.maxBlocks) blocks.") }
        document.draft.blocks.append(ContextBlock())
        selectedSection = .workspace
    }

    func removeWorkspaceBlock(_ id: UUID) {
        document.draft.blocks.removeAll { $0.id == id }
    }

    func duplicateWorkspaceBlock(_ id: UUID) {
        guard let index = document.draft.blocks.firstIndex(where: { $0.id == id }) else { return }
        guard document.draft.blocks.count < SelectionEngine.maxBlocks else { return fail("The workspace is limited to \(SelectionEngine.maxBlocks) blocks.") }
        var copy = document.draft.blocks[index].independentCopy(origin: document.draft.blocks[index].libraryOrigin)
        copy.title += " (copy)"
        document.draft.blocks.insert(copy, at: index + 1)
    }

    func moveWorkspaceBlock(_ id: UUID, by offset: Int) {
        guard let index = document.draft.blocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard document.draft.blocks.indices.contains(target) else { return }
        document.draft.blocks.swapAt(index, target)
    }

    func canMoveWorkspaceBlock(_ id: UUID, by offset: Int) -> Bool {
        guard let index = document.draft.blocks.firstIndex(where: { $0.id == id }) else { return false }
        return document.draft.blocks.indices.contains(index + offset)
    }

    func copyToLibrary(_ id: UUID) {
        guard let block = document.draft.blocks.first(where: { $0.id == id }) else { return }
        guard document.library.count < ProjectDocument.maxLibraryItems else { return fail("The library is limited to \(ProjectDocument.maxLibraryItems) items.") }
        var copy = block.independentCopy()
        copy.required = false
        document.library.append(copy)
        status = "Copied “\(block.title)” to the Context Library."
    }

    // MARK: Library

    func newLibraryItem() {
        guard document.library.count < ProjectDocument.maxLibraryItems else { return fail("The library is limited to \(ProjectDocument.maxLibraryItems) items.") }
        let item = ContextBlock(title: "New context")
        document.library.append(item)
        selectedLibraryID = item.id
    }

    func duplicateLibraryItem(_ id: UUID) {
        guard let index = document.library.firstIndex(where: { $0.id == id }) else { return }
        guard document.library.count < ProjectDocument.maxLibraryItems else { return fail("The library is limited to \(ProjectDocument.maxLibraryItems) items.") }
        var copy = document.library[index].independentCopy()
        copy.title += " (copy)"
        document.library.insert(copy, at: index + 1)
        selectedLibraryID = copy.id
    }

    func deleteLibraryItem(_ id: UUID) {
        document.library.removeAll { $0.id == id }
        if selectedLibraryID == id { selectedLibraryID = nil }
    }

    /// Insert an independent copy of a library item into the workspace.
    func useLibraryItem(_ id: UUID) {
        guard let item = document.library.first(where: { $0.id == id }) else { return }
        guard document.draft.blocks.count < SelectionEngine.maxBlocks else { return fail("The workspace is limited to \(SelectionEngine.maxBlocks) blocks.") }
        document.draft.blocks.append(item.independentCopy(origin: item.id))
        status = "Added a copy of “\(item.title)” to the workspace. Editing it will not change the library item."
    }

    func workspaceUses(ofLibraryItem id: UUID) -> Int {
        document.draft.blocks.filter { $0.libraryOrigin == id }.count
    }

    func libraryBinding(_ id: UUID) -> Binding<ContextBlock>? {
        guard let initial = document.library.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.document.library.first { $0.id == id } ?? initial },
            set: { [weak self] newValue in
                guard let self, let index = self.document.library.firstIndex(where: { $0.id == id }) else { return }
                self.document.library[index] = newValue
            })
    }

    // MARK: Experiments

    func saveExperiment() {
        guard let report = currentReport else { return fail("Update the preview first. Only a current preview can be saved as an experiment.") }
        guard document.experiments.count < ProjectDocument.maxExperiments else { return fail("A project is limited to \(ProjectDocument.maxExperiments) experiments.") }
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short
        let experiment = Experiment(name: "\(report.settings.strategy.displayName) — \(formatter.string(from: Date()))", snapshot: report)
        document.experiments.insert(experiment, at: 0)
        selectedExperimentID = experiment.id
        status = "Saved experiment “\(experiment.name)”. Save the project to keep it."
    }

    func experimentBinding(_ id: UUID) -> Binding<Experiment>? {
        guard let initial = document.experiments.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in self?.document.experiments.first { $0.id == id } ?? initial },
            set: { [weak self] newValue in
                guard let self, let index = self.document.experiments.firstIndex(where: { $0.id == id }) else { return }
                self.document.experiments[index] = newValue
            })
    }

    func deleteExperiment(_ id: UUID) {
        document.experiments.removeAll { $0.id == id }
        if selectedExperimentID == id { selectedExperimentID = nil }
    }

    /// Replace the workspace inputs and settings with an experiment's saved inputs.
    func restoreInputs(from id: UUID) {
        guard let experiment = document.experiments.first(where: { $0.id == id }) else { return }
        guard Dialogs.confirm(title: "Replace the workspace with this experiment’s inputs?",
                              message: "The current instructions, context blocks and selection settings will be replaced by the ones saved in “\(experiment.name)”. The library and other experiments are not changed.",
                              confirmTitle: "Replace Workspace") else { return }
        document.draft = experiment.snapshot.input
        document.settings = experiment.snapshot.settings
        selectedSection = .workspace
        status = "Workspace restored from “\(experiment.name)”."
    }

    func reproduce(_ id: UUID) async -> ReproductionResult {
        guard let experiment = document.experiments.first(where: { $0.id == id }) else { return .differs(["Experiment not found."]) }
        if case .bpe(let encoding) = experiment.snapshot.settings.counter {
            _ = try? await encodings.load(encoding)
        }
        let resolver = encodings.resolver()
        return await Task.detached(priority: .userInitiated) { ReproductionCheck.run(experiment, resolver: resolver) }.value
    }

    // MARK: Clipboard and exports

    func copyToPasteboard(_ text: String, what: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied \(what) to the clipboard."
    }

    func copySelectedPrompt() {
        guard let report = currentReport else { return }
        copyToPasteboard(report.selectedPrompt, what: "the selected prompt")
    }

    func exportReport() {
        guard let report = currentReport else { return fail("There is no current preview to export.") }
        export(report, suggestedName: "Selection-Report.json", findings: SecretScanner.scan(report), what: "Report")
    }

    func exportExperiment(_ id: UUID) {
        guard let experiment = document.experiments.first(where: { $0.id == id }) else { return }
        var project = ProjectDocument(); project.experiments = [experiment]
        let findings = SecretScanner.scan(project)
        export(experiment, suggestedName: "Experiment.json", findings: findings, what: "Experiment")
    }

    private func export<T: Encodable>(_ value: T, suggestedName: String, findings: [SecretFinding], what: String) {
        if !findings.isEmpty && !Dialogs.confirmPossibleSecrets(findings, action: "Export") { status = "Export cancelled."; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: url, options: .atomic)
            status = "\(what) exported to \(url.lastPathComponent). It contains prompt text in plain JSON."
        } catch {
            fail("Could not export: \(error.localizedDescription)")
        }
    }

    // MARK: Project files

    /// Ask about unsaved changes before replacing or closing the project. Returns true to proceed.
    func confirmUnsavedChanges(before action: String) -> Bool {
        ProjectSession.mayProceed(
            hasUnsavedChanges: hasUnsavedChanges,
            ask: { Dialogs.askAboutUnsavedChanges(projectName: session.displayName, action: action) },
            save: { save() })
    }

    func newProject() {
        guard confirmUnsavedChanges(before: "starting a new project") else { return }
        replaceSession(ProjectSession(), status: "New untitled project.")
    }

    func loadExample() {
        guard confirmUnsavedChanges(before: "loading the example project") else { return }
        replaceSession(.untitled(SampleProject.make()), status: "Example loaded. It is synthetic and untitled; save it to keep changes.")
        selectedSection = .workspace
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let opened: (session: ProjectSession, loaded: ProjectCodec.Loaded)
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= ProjectCodec.maxFileBytes else { throw LabError.invalid("Project files are limited to 20 MB.") }
            opened = try ProjectSession.opening(data: Data(contentsOf: url), url: url)
        } catch {
            return fail("“\(url.lastPathComponent)” could not be opened. Your current project was not changed.\n\n\(error.localizedDescription)")
        }
        // Validation happened first, so a bad file never costs the user their current work.
        guard confirmUnsavedChanges(before: "opening “\(url.lastPathComponent)”") else { return }
        if opened.loaded.wasMigrated {
            replaceSession(opened.session, status: "Converted “\(url.lastPathComponent)” from schema \(opened.loaded.sourceSchemaVersion). It is open as untitled so the original file is not overwritten.")
        } else {
            replaceSession(opened.session, status: "Opened \(url.lastPathComponent).")
        }
    }

    /// Save to the current file, or ask for a location. Returns true only if the project was written.
    @discardableResult func save() -> Bool {
        if let url = session.fileURL { return write(to: url) }
        return saveAs()
    }

    @discardableResult func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = (session.fileURL?.lastPathComponent) ?? "Untitled Project.json"
        guard panel.runModal() == .OK, let url = panel.url else { status = "Save cancelled."; return false }
        return write(to: url)
    }

    private func write(to url: URL) -> Bool {
        let snapshot = document
        let findings = SecretScanner.scan(snapshot)
        if !findings.isEmpty && !Dialogs.confirmPossibleSecrets(findings, action: "Save") {
            status = "Save cancelled."
            return false
        }
        do {
            let data = try ProjectCodec.encode(snapshot)
            try data.write(to: url, options: .atomic)
            session.didSave(snapshot, to: url)
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch {
            fail("Could not save the project. Nothing was overwritten.\n\n\(error.localizedDescription)")
            return false
        }
    }

    private func replaceSession(_ newSession: ProjectSession, status: String) {
        session = newSession
        report = nil
        previewError = nil
        selectedLibraryID = nil
        selectedExperimentID = nil
        self.status = status
    }

    /// Close the main window after resolving unsaved changes (window close button and ⌘W).
    func requestCloseWindow(_ window: NSWindow?) {
        guard confirmUnsavedChanges(before: "closing the window") else { return }
        allowTerminationWithoutPrompt = true
        window?.close()
    }

    private func fail(_ message: String) {
        errorMessage = message
    }
}
