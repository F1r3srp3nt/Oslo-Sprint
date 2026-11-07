import Foundation

public enum ContextCategory: String, Codable, CaseIterable, Identifiable {
    case reference = "Reference", conversation = "Conversation", code = "Code", toolOutput = "Tool output"
    public var id: String { rawValue }
}

public struct ContextBlock: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var text: String
    public var category: ContextCategory
    public var priority: Int
    public var required: Bool
    public init(id: UUID = UUID(), title: String = "Untitled context", text: String = "", category: ContextCategory = .reference, priority: Int = 2, required: Bool = false) {
        self.id = id; self.title = title; self.text = text; self.category = category
        self.priority = priority; self.required = required
    }
}

public struct Draft: Codable, Equatable {
    public var instructions: String = ""
    public var blocks: [ContextBlock] = []
    public var budget: Int = 1000
    public init() {}
}

public struct BlockDecision: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var kept: Bool
    public var reason: String
}

public struct OptimizationReport: Codable, Equatable {
    public var input: Draft
    public var original: String
    public var optimized: String
    public var before: Int
    public var after: Int
    public var overBudget: Bool
    public var decisions: [BlockDecision]
    public var counter: String = "UTF-8 bytes / 4 estimate; excludes message overhead"
    public var saved: Int { before - after }
    public var savingsPercent: Int { before == 0 ? 0 : Int((Double(saved) / Double(before) * 100).rounded()) }
}

public enum QualityReview: String, Codable, CaseIterable, Identifiable {
    case notRun = "Not evaluated", passed = "Manually reviewed: pass", failed = "Manually reviewed: fail"
    public var id: String { rawValue }
}

public struct Experiment: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name: String
    public var createdAt = Date()
    public var report: OptimizationReport
    public var review: QualityReview = .notRun
    public var notes = ""
    public init(name: String, report: OptimizationReport) { self.name = name; self.report = report }
}

public struct ProjectDocument: Codable, Equatable {
    public var schemaVersion = 1
    public var draft = Draft()
    public var library: [ContextBlock] = []
    public var experiments: [Experiment] = []
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1 else { throw LabError.invalid("Unsupported project version.") }
        try Optimizer.validate(draft)
        guard library.count <= 500, experiments.count <= 500 else { throw LabError.invalid("Project exceeds the 500-item library or experiment limit.") }
        guard Set(library.map(\.id)).count == library.count,
              Set(experiments.map(\.id)).count == experiments.count else { throw LabError.invalid("Project contains duplicate identifiers.") }
        for block in library {
            guard (1...3).contains(block.priority) else { throw LabError.invalid("Context priorities must be between 1 and 3.") }
        }
        for experiment in experiments {
            // Persisted reports must agree with their source inputs, not supplied metrics.
            guard try Optimizer.run(experiment.report.input) == experiment.report else {
                throw LabError.invalid("An experiment report does not match its inputs.")
            }
        }
    }
}

public enum LabError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
