import Foundation

public enum Optimizer {
    public static func estimate(_ text: String) -> Int { (text.utf8.count + 3) / 4 }
    public static func assemble(_ draft: Draft, selected: Set<UUID>? = nil) -> String {
        ([draft.instructions] + draft.blocks.filter { selected == nil || selected!.contains($0.id) }.map(\.text))
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    public static func validate(_ draft: Draft) throws {
        guard (1...1_000_000).contains(draft.budget) else { throw LabError.invalid("Budget must be between 1 and 1,000,000.") }
        guard draft.blocks.count <= 500 else { throw LabError.invalid("A workspace supports up to 500 context blocks.") }
        guard Set(draft.blocks.map(\.id)).count == draft.blocks.count else { throw LabError.invalid("Context IDs must be unique.") }
        guard draft.blocks.allSatisfy({ (1...3).contains($0.priority) }) else { throw LabError.invalid("Priority must be between 1 and 3.") }
        guard draft.instructions.utf8.count + draft.blocks.reduce(0, { $0 + $1.text.utf8.count }) <= 2_000_000 else { throw LabError.invalid("Workspace text is limited to 2 MB in this prototype.") }
    }
    public static func run(_ draft: Draft) throws -> OptimizationReport {
        try validate(draft)
        var selected = Set(draft.blocks.filter(\.required).map(\.id))
        // Byte arrays deliberately avoid Swift's canonical Unicode equality for exact duplicates.
        var seen = Set(draft.blocks.filter(\.required).map { Array($0.text.utf8) })
        var reasons: [UUID: String] = [:]
        for b in draft.blocks where b.required { reasons[b.id] = "Required: preserved verbatim" }
        let candidates = draft.blocks.enumerated().filter { !$0.element.required }.sorted {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority > $1.element.priority
        }
        for (_, block) in candidates {
            if block.text.isEmpty { reasons[block.id] = "Empty context"; continue }
            let bytes = Array(block.text.utf8)
            if seen.contains(bytes) { reasons[block.id] = "Exact duplicate of retained context"; continue }
            selected.insert(block.id)
            if estimate(assemble(draft, selected: selected)) > draft.budget {
                selected.remove(block.id); reasons[block.id] = "Excluded by budget and priority"
            } else { seen.insert(bytes); reasons[block.id] = "Retained within budget" }
        }
        let original = assemble(draft), optimized = assemble(draft, selected: selected)
        return OptimizationReport(input: draft, original: original, optimized: optimized,
            before: estimate(original), after: estimate(optimized), overBudget: estimate(optimized) > draft.budget,
            decisions: draft.blocks.map { BlockDecision(id: $0.id, title: $0.title, kept: selected.contains($0.id), reason: reasons[$0.id] ?? "") })
    }
}
