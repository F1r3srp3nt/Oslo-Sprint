import Foundation

/// Placeholder for the real Wybe Night Shift connection.
///
/// It intentionally sends nothing. The command vocabulary, endpoints, payloads, authentication
/// and scoring of the real service are not publicly documented in a form Relay could read
/// (see docs/WYBE.md), and Relay must not guess them. Every call throws
/// `ChallengeError.contractUnavailable`, so a runner started in live mode stops before acting.
public struct LiveNightShiftAdapter: ChallengeAdapter {
    public let mode: ExecutionMode = .live
    public let name = "Wybe Night Shift (live — not configured)"
    public let supportsStatusQuery = false

    public static let missingContract = """
        The live Wybe Night Shift protocol is not implemented. Needed from the organisers (via the join \
        page https://nightshift-board.wybe.me/join after team registration): the API base URL, how the agent \
        authenticates, how to list the commands the robot understands, the observation/task format, the \
        action request/response format, whether requests are idempotent or can be status-checked, rate \
        limits, and how practice vs. final shifts are started and scored.
        """

    public init() {}

    public func discoverCapabilities() async throws -> [ActionSpec] {
        throw ChallengeError.contractUnavailable(Self.missingContract)
    }

    public func observe() async throws -> Observation {
        throw ChallengeError.contractUnavailable(Self.missingContract)
    }

    public func perform(_ request: ActionRequest) async throws -> ActionOutcome {
        throw ChallengeError.contractUnavailable(Self.missingContract)
    }

    public func status(of idempotencyKey: String) async throws -> ActionStatusAnswer { .unknown }

    /// No live score exists unless the real service reports one.
    public func scoreReport() async -> LabeledScore? { nil }
}
