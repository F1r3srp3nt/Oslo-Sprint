import Foundation

public enum DecisionKind: String, Codable, Sendable {
    /// Required context: always kept verbatim.
    case required
    /// Optional context kept by the strategy.
    case retained
    /// Empty text contributes nothing to the prompt.
    case emptySkipped
    /// Optional context byte-identical to retained text (only when deduplication is active).
    case duplicateRemoved
    /// Optional context that did not fit the budget.
    case excludedByBudget

    public var kept: Bool { self == .required || self == .retained }
}

public struct BlockDecision: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var category: ContextCategory
    public var priority: Int
    public var required: Bool
    public var kind: DecisionKind
    /// Human-readable explanation of why the block was kept or removed.
    public var reason: String
    /// Tokens of this block's text on its own, with the report's counter.
    public var standaloneTokens: Int
    /// For removed duplicates: the block whose identical text was kept (nil if it matched the instructions).
    public var duplicateOf: UUID?

    public var kept: Bool { kind.kept }
}

/// A complete, reproducible record of one selection run.
public struct SelectionReport: Codable, Equatable, Sendable {
    public static let currentEngineVersion = "selection-engine-2"
    public static let separator = "\n\n"

    public var engineVersion: String
    public var input: Draft
    public var settings: SelectionSettings
    public var counter: TokenCounterDescriptor
    /// Instructions plus all non-empty context, in order: the full-context prompt.
    public var originalPrompt: String
    /// Instructions plus retained context, in original order.
    public var selectedPrompt: String
    public var originalTokens: Int
    public var selectedTokens: Int
    /// Tokens for instructions plus required context alone.
    public var protectedTokens: Int
    public var decisions: [BlockDecision]

    public var budget: Int { settings.budget }
    public var budgetEnforced: Bool { settings.enforcesBudget }
    /// How far the selected prompt exceeds the budget (0 when within it).
    public var overBudgetBy: Int { max(0, selectedTokens - settings.budget) }
    public var overBudget: Bool { overBudgetBy > 0 }
    /// True when protected content alone is larger than the budget.
    public var protectedExceedsBudget: Bool { protectedTokens > settings.budget }

    /// Estimated reduction with this report's counter. Not provider usage and not a cost saving.
    public var estimatedReduction: Int { originalTokens - selectedTokens }
    public var estimatedReductionPercent: Double? {
        originalTokens == 0 ? nil : Double(estimatedReduction) / Double(originalTokens) * 100
    }

    public var keptCount: Int { decisions.filter(\.kept).count }
    public var removedCount: Int { decisions.filter { !$0.kept && $0.kind != .emptySkipped }.count }

    /// Whether this report was produced from exactly these inputs and counter. Used to hide stale previews.
    public func isCurrent(draft: Draft, settings: SelectionSettings, counter: TokenCounterDescriptor) -> Bool {
        engineVersion == Self.currentEngineVersion && input == draft && self.settings == settings && self.counter == counter
    }

    /// One-sentence honest summary of the budget situation.
    public var budgetSummary: String {
        let unit = counter.kind == .approximation ? "estimated tokens" : "\(counter.encoding) tokens"
        if budgetEnforced {
            if protectedExceedsBudget {
                return "Protected content alone is \(protectedTokens) \(unit), \(protectedTokens - budget) over the budget of \(budget). It was kept intact and not truncated; all optional context was excluded."
            }
            return "Selected prompt is \(selectedTokens) of \(budget) \(unit)."
        }
        if overBudget {
            return "This strategy does not apply the budget. The selected prompt is \(selectedTokens) \(unit), \(overBudgetBy) over the budget of \(budget)."
        }
        return "This strategy does not apply the budget. The selected prompt is \(selectedTokens) \(unit), within the budget of \(budget)."
    }
}

/// Deterministic, explainable context selection. Pure: same inputs and counter always give the same report.
public enum SelectionEngine {
    public static let maxBlocks = 500
    public static let maxTextBytes = 2_000_000

    public static func validate(_ draft: Draft) throws {
        guard draft.blocks.count <= maxBlocks else {
            throw LabError.invalid("A workspace supports up to \(maxBlocks) context blocks.")
        }
        guard Set(draft.blocks.map(\.id)).count == draft.blocks.count else {
            throw LabError.invalid("Context block identifiers must be unique.")
        }
        if let bad = draft.blocks.first(where: { !ContextPriority.range.contains($0.priority) }) {
            throw LabError.invalid("Priority must be between 1 and 3 (block “\(bad.title)” has \(bad.priority)).")
        }
        let bytes = draft.instructions.utf8.count + draft.blocks.reduce(0) { $0 + $1.text.utf8.count }
        guard bytes <= maxTextBytes else {
            throw LabError.invalid("Workspace text is limited to 2 MB in this prototype.")
        }
    }

    /// Assemble a prompt: instructions first, then the given blocks' text in their original order.
    public static func assemble(_ draft: Draft, keeping kept: Set<UUID>? = nil) -> String {
        parts(draft, keeping: kept).joined(separator: SelectionReport.separator)
    }

    static func parts(_ draft: Draft, keeping kept: Set<UUID>?) -> [String] {
        ([draft.instructions] + draft.blocks.filter { kept?.contains($0.id) ?? true }.map(\.text)).filter { !$0.isEmpty }
    }

    public static func run(_ draft: Draft, settings: SelectionSettings, counter: any TokenCounter) throws -> SelectionReport {
        try validate(draft)
        try settings.validate()

        let blocks = draft.blocks
        let title: (ContextBlock) -> String = { $0.title.isEmpty ? "Untitled context" : $0.title }
        var kinds: [UUID: DecisionKind] = [:]
        var reasons: [UUID: String] = [:]
        var duplicateOf: [UUID: UUID] = [:]

        // 1. Empty and required blocks are decided the same way under every strategy.
        for block in blocks {
            if block.text.isEmpty {
                kinds[block.id] = .emptySkipped
                reasons[block.id] = "Skipped: the block is empty and adds no text."
            } else if block.required {
                kinds[block.id] = .required
                reasons[block.id] = "Kept: marked required, preserved verbatim."
            }
        }
        let optional = blocks.enumerated().filter { kinds[$0.element.id] == nil }

        // 2. Optional exact deduplication (byte comparison; no Unicode normalisation).
        if settings.deduplicates {
            let instructionBytes = Array(draft.instructions.utf8)
            var requiredByText: [[UInt8]: ContextBlock] = [:]
            for block in blocks where block.required && !block.text.isEmpty {
                let key = Array(block.text.utf8)
                if requiredByText[key] == nil { requiredByText[key] = block }
            }
            // Keep the highest-priority optional copy; ties keep the earliest.
            let ordered = optional.sorted { a, b in
                a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset
            }
            var keptCopy: [[UInt8]: ContextBlock] = [:]
            for (_, block) in ordered {
                let key = Array(block.text.utf8)
                if !draft.instructions.isEmpty && key == instructionBytes {
                    kinds[block.id] = .duplicateRemoved
                    reasons[block.id] = "Removed: exact duplicate of the protected instructions."
                } else if let original = requiredByText[key] {
                    kinds[block.id] = .duplicateRemoved; duplicateOf[block.id] = original.id
                    reasons[block.id] = "Removed: exact duplicate of required block “\(title(original))”."
                } else if let original = keptCopy[key] {
                    kinds[block.id] = .duplicateRemoved; duplicateOf[block.id] = original.id
                    let why = original.priority > block.priority ? "higher priority" : "same priority, earlier in the prompt"
                    reasons[block.id] = "Removed: exact duplicate of “\(title(original))”, which was kept (\(why))."
                } else {
                    keptCopy[key] = block
                }
            }
        }

        // 3. Strategy-specific selection of the remaining optional blocks.
        let remaining = optional.filter { kinds[$0.element.id] == nil }
        switch settings.strategy {
        case .baseline:
            for (_, block) in remaining {
                kinds[block.id] = .retained; reasons[block.id] = "Kept: the baseline strategy retains all context."
            }
        case .exactDeduplication:
            for (_, block) in remaining {
                kinds[block.id] = .retained; reasons[block.id] = "Kept: no exact duplicate of this text is retained elsewhere."
            }
        case .budgetSelection:
            var kept = Set(blocks.filter { kinds[$0.id] == .required }.map(\.id))
            let protectedTokens = counter.countJoined(parts(draft, keeping: kept), separator: SelectionReport.separator)
            let candidates = remaining.sorted { a, b in
                a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset
            }
            for (_, block) in candidates {
                let label = ContextPriority.label(block.priority).lowercased()
                if protectedTokens > settings.budget {
                    kinds[block.id] = .excludedByBudget
                    reasons[block.id] = "Excluded: protected content alone (\(protectedTokens)) already exceeds the budget of \(settings.budget)."
                    continue
                }
                kept.insert(block.id)
                let total = counter.countJoined(parts(draft, keeping: kept), separator: SelectionReport.separator)
                if total <= settings.budget {
                    kinds[block.id] = .retained
                    reasons[block.id] = "Kept: \(label) priority; prompt total \(total) of \(settings.budget) after adding it."
                } else {
                    kept.remove(block.id)
                    kinds[block.id] = .excludedByBudget
                    reasons[block.id] = "Excluded: \(label) priority; adding it would make the prompt \(total), over the budget of \(settings.budget)."
                }
            }
        }

        let keptIDs = Set(blocks.filter { kinds[$0.id]?.kept == true }.map(\.id))
        let requiredIDs = Set(blocks.filter { kinds[$0.id] == .required }.map(\.id))
        let originalParts = parts(draft, keeping: nil)
        let selectedParts = parts(draft, keeping: keptIDs)
        let decisions = blocks.map { block in
            BlockDecision(id: block.id, title: title(block), category: block.category, priority: block.priority,
                          required: block.required, kind: kinds[block.id]!, reason: reasons[block.id]!,
                          standaloneTokens: counter.count(block.text), duplicateOf: duplicateOf[block.id])
        }
        return SelectionReport(
            engineVersion: SelectionReport.currentEngineVersion,
            input: draft, settings: settings, counter: counter.descriptor,
            originalPrompt: originalParts.joined(separator: SelectionReport.separator),
            selectedPrompt: selectedParts.joined(separator: SelectionReport.separator),
            originalTokens: counter.countJoined(originalParts, separator: SelectionReport.separator),
            selectedTokens: counter.countJoined(selectedParts, separator: SelectionReport.separator),
            protectedTokens: counter.countJoined(parts(draft, keeping: requiredIDs), separator: SelectionReport.separator),
            decisions: decisions)
    }
}
