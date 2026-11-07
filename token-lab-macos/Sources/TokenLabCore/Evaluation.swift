import Foundation

/// Overall human judgement of the selected-context answer. Stays `.notEvaluated` until a review happens.
public enum QualityVerdict: String, Codable, CaseIterable, Identifiable, Sendable {
    case notEvaluated
    case equivalent
    case acceptableWithLosses
    case degraded
    case unusable

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .notEvaluated: return "Not evaluated"
        case .equivalent: return "Equivalent to full-context answer"
        case .acceptableWithLosses: return "Acceptable, minor losses"
        case .degraded: return "Degraded"
        case .unusable: return "Unusable"
        }
    }
}

public enum CheckResult: String, Codable, CaseIterable, Identifiable, Sendable {
    case notChecked, pass, fail
    public var id: String { rawValue }
    public var label: String {
        switch self { case .notChecked: return "Not checked"; case .pass: return "Pass"; case .fail: return "Fail" }
    }
}

/// An expected fact or correctness check, judged separately for each answer.
public struct ReviewCheck: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var fullContext: CheckResult
    public var selectedContext: CheckResult
    public init(id: UUID = UUID(), text: String = "", fullContext: CheckResult = .notChecked, selectedContext: CheckResult = .notChecked) {
        self.id = id; self.text = text; self.fullContext = fullContext; self.selectedContext = selectedContext
    }
}

/// Usage numbers copied from a provider's response by the reviewer. Kept apart from local estimates.
public struct ProviderUsage: Codable, Equatable, Hashable, Sendable {
    public var provider: String
    public var model: String
    public var inputTokens: Int?
    public var outputTokens: Int?
    public init(provider: String = "", model: String = "", inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.provider = provider; self.model = model; self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }
    public var isEmpty: Bool { provider.isEmpty && model.isEmpty && inputTokens == nil && outputTokens == nil }
}

/// One model answer for one prompt variant, recorded manually (no live calls in this version).
public struct ModelRun: Codable, Equatable, Hashable, Sendable {
    public var responseText: String
    public var usage: ProviderUsage
    public init(responseText: String = "", usage: ProviderUsage = ProviderUsage()) {
        self.responseText = responseText; self.usage = usage
    }
    public var hasResponse: Bool { !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Side-by-side evaluation of the full-context and selected-context prompts for the same task.
public struct Evaluation: Codable, Equatable, Sendable {
    public var fullContextRun: ModelRun
    public var selectedContextRun: ModelRun
    public var expectedFacts: [ReviewCheck]
    public var correctnessChecks: [ReviewCheck]
    public var verdict: QualityVerdict
    public var reviewer: String
    public var reviewerNotes: String
    public var evaluatedAt: Date?

    public init() {
        fullContextRun = ModelRun(); selectedContextRun = ModelRun()
        expectedFacts = []; correctnessChecks = []
        verdict = .notEvaluated; reviewer = ""; reviewerNotes = ""; evaluatedAt = nil
    }

    /// A verdict can only be recorded once there is a selected-context answer to judge.
    public var canRecordVerdict: Bool { selectedContextRun.hasResponse }

    public var isEvaluated: Bool { verdict != .notEvaluated }

    public var statusLabel: String {
        if isEvaluated { return verdict.label }
        if fullContextRun.hasResponse || selectedContextRun.hasResponse { return "Not evaluated (answers recorded)" }
        return "Not evaluated"
    }

    /// Input-token reduction reported by the provider, only when both runs carry provider input counts.
    public var providerReportedInputReduction: (tokens: Int, percent: Double?)? {
        guard let full = fullContextRun.usage.inputTokens, let selected = selectedContextRun.usage.inputTokens else { return nil }
        return (full - selected, full == 0 ? nil : Double(full - selected) / Double(full) * 100)
    }

    /// Tally of checks for one variant: (passed, failed, notChecked).
    public func tally(selected: Bool) -> (pass: Int, fail: Int, notChecked: Int) {
        let results = (expectedFacts + correctnessChecks).map { selected ? $0.selectedContext : $0.fullContext }
        return (results.filter { $0 == .pass }.count, results.filter { $0 == .fail }.count, results.filter { $0 == .notChecked }.count)
    }

    /// Record a verdict. Moving back to `.notEvaluated` clears the timestamp.
    public mutating func setVerdict(_ verdict: QualityVerdict, at date: Date = Date()) throws {
        if verdict != .notEvaluated && !canRecordVerdict {
            throw LabError.invalid("Record the selected-context answer before giving a quality verdict.")
        }
        self.verdict = verdict
        evaluatedAt = verdict == .notEvaluated ? nil : ProjectCodec.wholeSeconds(date)
    }

    public func validate() throws {
        if isEvaluated && !canRecordVerdict {
            throw LabError.invalid("An experiment has a quality verdict but no selected-context answer.")
        }
        let ids = (expectedFacts + correctnessChecks).map(\.id)
        guard Set(ids).count == ids.count else { throw LabError.invalid("Review checks contain duplicate identifiers.") }
        for usage in [fullContextRun.usage, selectedContextRun.usage] {
            for value in [usage.inputTokens, usage.outputTokens].compactMap({ $0 }) where value < 0 {
                throw LabError.invalid("Provider-reported token counts cannot be negative.")
            }
        }
    }
}

/// A saved, self-contained snapshot of one selection run plus its manual evaluation.
/// Value semantics: later edits to the workspace never change a saved experiment.
public struct Experiment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var snapshot: SelectionReport
    public var evaluation: Evaluation

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), snapshot: SelectionReport, evaluation: Evaluation = Evaluation()) {
        self.id = id; self.name = name; self.createdAt = ProjectCodec.wholeSeconds(createdAt)
        self.snapshot = snapshot; self.evaluation = evaluation
    }

    /// Structural checks for persisted experiments. Does not re-run the engine: snapshots stay
    /// loadable even when the engine or counters change; use `ReproductionCheck` to compare.
    public func validate() throws {
        try snapshot.settings.validate()
        try SelectionEngine.validate(snapshot.input)
        guard snapshot.decisions.map(\.id) == snapshot.input.blocks.map(\.id) else {
            throw LabError.invalid("Experiment “\(name)” has decisions that do not match its saved inputs.")
        }
        guard [snapshot.originalTokens, snapshot.selectedTokens, snapshot.protectedTokens].allSatisfy({ $0 >= 0 }) else {
            throw LabError.invalid("Experiment “\(name)” contains negative token counts.")
        }
        guard snapshot.originalPrompt == SelectionEngine.assemble(snapshot.input) else {
            throw LabError.invalid("Experiment “\(name)” has an original prompt that does not match its saved inputs.")
        }
        let kept = Set(snapshot.decisions.filter(\.kept).map(\.id))
        guard snapshot.selectedPrompt == SelectionEngine.assemble(snapshot.input, keeping: kept) else {
            throw LabError.invalid("Experiment “\(name)” has a selected prompt that does not match its recorded decisions.")
        }
        try evaluation.validate()
    }
}

/// Re-runs a snapshot with the current engine and counter and reports any difference.
public enum ReproductionResult: Equatable, Sendable {
    case identical
    case differs([String])
    case counterUnavailable(String)
}

public enum ReproductionCheck {
    public static func run(_ experiment: Experiment, resolver: TokenCounterResolver) -> ReproductionResult {
        let snapshot = experiment.snapshot
        let counter: any TokenCounter
        do { counter = try resolver.counter(for: snapshot.settings.counter) }
        catch { return .counterUnavailable(error.localizedDescription) }
        let rerun: SelectionReport
        do { rerun = try SelectionEngine.run(snapshot.input, settings: snapshot.settings, counter: counter) }
        catch { return .differs(["The saved inputs no longer pass validation: \(error.localizedDescription)"]) }
        var differences: [String] = []
        if rerun.engineVersion != snapshot.engineVersion { differences.append("Engine version: saved \(snapshot.engineVersion), now \(rerun.engineVersion).") }
        if rerun.counter != snapshot.counter { differences.append("Counter: saved “\(snapshot.counter.id) \(snapshot.counter.version)”, now “\(rerun.counter.id) \(rerun.counter.version)”.") }
        if rerun.selectedPrompt != snapshot.selectedPrompt { differences.append("The selected prompt text differs.") }
        if rerun.decisions.map(\.kind) != snapshot.decisions.map(\.kind) { differences.append("Keep/remove decisions differ.") }
        if rerun.originalTokens != snapshot.originalTokens || rerun.selectedTokens != snapshot.selectedTokens {
            differences.append("Token counts differ: saved \(snapshot.originalTokens)→\(snapshot.selectedTokens), now \(rerun.originalTokens)→\(rerun.selectedTokens).")
        }
        return differences.isEmpty ? .identical : .differs(differences)
    }
}
