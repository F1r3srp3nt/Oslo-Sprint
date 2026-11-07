import XCTest
@testable import TokenLabCore

final class OptimizerTests: XCTestCase {
    func testProtectedTextSurvivesOverflow() throws {
        var draft = Draft(); draft.instructions = "def f():\n    return 1\n"; draft.budget = 1
        draft.blocks = [ContextBlock(text: "must stay", required: true)]
        let report = try Optimizer.run(draft)
        XCTAssertEqual(report.optimized, draft.instructions + "\n\nmust stay")
        XCTAssertTrue(report.overBudget)
    }
    func testRequiredDuplicateWins() throws {
        var draft = Draft(); draft.blocks = [ContextBlock(text: "same", priority: 3), ContextBlock(text: "same", required: true)]
        let report = try Optimizer.run(draft)
        XCTAssertFalse(report.decisions[0].kept); XCTAssertTrue(report.decisions[1].kept)
    }
    func testBudgetIncludesSeparatorsAndRespectsPriority() throws {
        var draft = Draft(); draft.instructions = "X"; draft.budget = 2
        draft.blocks = [ContextBlock(text: "low", priority: 1), ContextBlock(text: "high", priority: 3)]
        let report = try Optimizer.run(draft)
        XCTAssertEqual(report.optimized, "X\n\nhigh"); XCTAssertLessThanOrEqual(report.after, draft.budget)
    }
    func testRequiredCopiesAreNotDeleted() throws {
        var draft = Draft(); draft.blocks = [ContextBlock(text: "x", required: true), ContextBlock(text: "x", required: true)]
        XCTAssertEqual(try Optimizer.run(draft).optimized, "x\n\nx")
    }
    func testEmptyInputHasFiniteSavings() throws { XCTAssertEqual(try Optimizer.run(Draft()).savingsPercent, 0) }
    func testDuplicateIDsRejected() {
        var draft = Draft(); let block = ContextBlock(text: "x"); draft.blocks = [block, block]
        XCTAssertThrowsError(try Optimizer.run(draft))
    }
    func testInvalidBudgetRejected() {
        var draft = Draft(); draft.budget = 0; XCTAssertThrowsError(try Optimizer.run(draft))
    }
    func testDocumentRoundTrip() throws {
        var project = ProjectDocument(); project.draft.instructions = "Keep this."
        project.experiments = [Experiment(name: "Test", report: try Optimizer.run(project.draft))]
        let copy = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(project))
        try copy.validate(); XCTAssertEqual(copy, project)
    }
    func testTamperedMetricsRejected() throws {
        var project = ProjectDocument(); var report = try Optimizer.run(Draft()); report.after = 500
        project.experiments = [Experiment(name: "Invalid", report: report)]
        XCTAssertThrowsError(try project.validate())
    }
    func testCanonicalUnicodeIsNotExactByteDuplicate() throws {
        var draft = Draft(); draft.blocks = [ContextBlock(text: "\u{00e9}"), ContextBlock(text: "e\u{0301}")]
        XCTAssertEqual(try Optimizer.run(draft).decisions.filter(\.kept).count, 2)
    }
}
