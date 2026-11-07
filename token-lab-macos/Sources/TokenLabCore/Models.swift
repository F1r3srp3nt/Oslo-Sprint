import Foundation

// MARK: - Context

public enum ContextCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case reference = "Reference"
    case conversation = "Conversation"
    case code = "Code"
    case toolOutput = "Tool output"
    public var id: String { rawValue }
}

/// Priority of optional context. Higher numbers are considered first by budget selection.
public enum ContextPriority {
    public static let low = 1
    public static let medium = 2
    public static let high = 3
    public static let range = 1...3
    public static func label(_ value: Int) -> String {
        switch value {
        case low: return "Low"
        case medium: return "Medium"
        case high: return "High"
        default: return "Invalid (\(value))"
        }
    }
}

public struct ContextBlock: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var category: ContextCategory
    public var priority: Int
    /// Required blocks are always kept verbatim, regardless of strategy or budget.
    public var required: Bool
    /// When the block was inserted from the Context Library, the library item it was copied from.
    /// The copy is independent: later edits to either side do not propagate.
    public var libraryOrigin: UUID?

    public init(id: UUID = UUID(), title: String = "Untitled context", text: String = "",
                category: ContextCategory = .reference, priority: Int = ContextPriority.medium,
                required: Bool = false, libraryOrigin: UUID? = nil) {
        self.id = id; self.title = title; self.text = text; self.category = category
        self.priority = priority; self.required = required; self.libraryOrigin = libraryOrigin
    }

    /// A copy with a fresh identifier, suitable for inserting elsewhere.
    public func independentCopy(origin: UUID? = nil) -> ContextBlock {
        var copy = self
        copy.id = UUID()
        copy.libraryOrigin = origin
        return copy
    }
}

/// The task being prepared: protected instructions / current request plus candidate context.
public struct Draft: Codable, Equatable, Hashable, Sendable {
    /// Protected instructions and the current request. Always kept verbatim, first in the prompt.
    public var instructions: String
    /// Context in prompt order. Retained blocks keep this order in the selected prompt.
    public var blocks: [ContextBlock]

    public init(instructions: String = "", blocks: [ContextBlock] = []) {
        self.instructions = instructions; self.blocks = blocks
    }
}

// MARK: - Selection settings

public enum SelectionStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A. Keep every non-empty block.
    case baseline
    /// B. Remove only optional blocks whose text is byte-identical to retained text.
    case exactDeduplication
    /// C. Choose optional blocks by priority until the token budget is reached.
    case budgetSelection

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .baseline: return "Baseline"
        case .exactDeduplication: return "Exact deduplication"
        case .budgetSelection: return "Budget selection"
        }
    }

    public var summary: String {
        switch self {
        case .baseline:
            return "Retains all context. Use it as the full-context reference for comparisons."
        case .exactDeduplication:
            return "Removes optional blocks whose text is byte-for-byte identical to the instructions, a required block or a higher-priority copy. Nothing else is removed and the budget is not applied."
        case .budgetSelection:
            return "Keeps required content, then adds optional blocks from highest to lowest priority (ties in prompt order) while the estimated total stays within the budget. Exact deduplication runs first only if enabled."
        }
    }
}

public struct SelectionSettings: Codable, Equatable, Hashable, Sendable {
    public static let budgetRange = 1...1_000_000

    public var strategy: SelectionStrategy
    /// Token budget measured with `counter`. Enforced only by `.budgetSelection`; reported for all strategies.
    public var budget: Int
    /// Only used by `.budgetSelection`: remove exact duplicates before selecting by budget.
    public var deduplicateBeforeBudget: Bool
    public var counter: CounterChoice

    public init(strategy: SelectionStrategy = .budgetSelection, budget: Int = 1000,
                deduplicateBeforeBudget: Bool = false, counter: CounterChoice = .approximate(bytesPerToken: 4)) {
        self.strategy = strategy; self.budget = budget
        self.deduplicateBeforeBudget = deduplicateBeforeBudget; self.counter = counter
    }

    /// Whether this configuration performs exact deduplication.
    public var deduplicates: Bool {
        switch strategy {
        case .baseline: return false
        case .exactDeduplication: return true
        case .budgetSelection: return deduplicateBeforeBudget
        }
    }

    public var enforcesBudget: Bool { strategy == .budgetSelection }

    public func validate() throws {
        guard Self.budgetRange.contains(budget) else {
            throw LabError.invalid("Budget must be between 1 and 1,000,000 tokens (found \(budget)).")
        }
        try counter.validate()
    }
}

/// Which token counter a project uses. Stored in project files so previews and experiments are reproducible.
public enum CounterChoice: Codable, Equatable, Hashable, Sendable {
    case approximate(bytesPerToken: Int)
    case bpe(encoding: BPEEncodingID)

    public static let bytesPerTokenRange = 1...8

    public func validate() throws {
        if case .approximate(let n) = self, !Self.bytesPerTokenRange.contains(n) {
            throw LabError.invalid("Approximate counter must use 1–8 bytes per token (found \(n)).")
        }
    }

    public var shortName: String {
        switch self {
        case .approximate(let n): return "Approximate (UTF-8 bytes ÷ \(n))"
        case .bpe(let encoding): return "\(encoding.rawValue) text tokens"
        }
    }
}

// MARK: - Errors

public enum LabError: LocalizedError, Equatable {
    case invalid(String)
    case malformed(String)
    case unsupportedSchema(found: Int, supported: Int)
    case counterUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .malformed(let message): return "The file could not be read: \(message)"
        case .unsupportedSchema(let found, let supported):
            if found > supported {
                return "This project uses schema version \(found), which is newer than this app supports (\(supported)). Nothing was changed."
            }
            return "Schema version \(found) is not supported. This app reads versions 1–\(supported). Nothing was changed."
        case .counterUnavailable(let message): return message
        }
    }
}
