import RelayAdapters
import RelayCore
import SwiftUI

/// Relay's restrained dark palette. Colour always comes with a text label, never alone.
enum Theme {
    static let background = Color(red: 0.055, green: 0.062, blue: 0.074)
    static let panel = Color(red: 0.090, green: 0.100, blue: 0.118)
    static let panelRaised = Color(red: 0.118, green: 0.130, blue: 0.153)
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color(white: 0.93)
    static let textSecondary = Color(white: 0.62)
    static let accent = Color(red: 0.36, green: 0.78, blue: 0.74)
    static let success = Color(red: 0.38, green: 0.78, blue: 0.49)
    static let warning = Color(red: 0.96, green: 0.72, blue: 0.30)
    static let danger = Color(red: 0.94, green: 0.38, blue: 0.38)
    static let simulation = Color(red: 0.64, green: 0.57, blue: 0.96)

    static func color(_ kind: LogKind) -> Color {
        switch kind {
        case .succeeded: return success
        case .failed, .rejected: return danger
        case .needsAttention: return warning
        case .heard, .understood, .planned, .attempted: return accent
        case .info: return textSecondary
        }
    }

    static func color(_ state: TaskState) -> Color {
        switch state {
        case .succeeded: return success
        case .failed: return danger
        case .needsAttention, .awaitingApproval: return warning
        case .inProgress: return accent
        case .queued, .cancelled: return textSecondary
        }
    }

    static func color(_ status: ActionResultStatus) -> Color {
        switch status {
        case .succeeded, .ambiguousConfirmedApplied: return success
        case .failed, .rejectedByEnvironment: return danger
        case .ambiguousUnresolved, .blockedPrecondition, .blockedNotAllowed, .blockedUnknownCommand: return warning
        case .stopped: return textSecondary
        }
    }

    static func color(_ status: InteractionStatus) -> Color {
        switch status {
        case .completed: return success
        case .awaitingApproval, .needsAttention: return warning
        case .failed: return danger
        case .declined, .notUnderstood: return textSecondary
        }
    }

    static func color(_ status: ToolAttemptStatus) -> Color {
        switch status {
        case .succeeded: return success
        case .failed, .unknownTool: return danger
        case .needsAttention, .awaitingApproval: return warning
        case .declined: return textSecondary
        }
    }

    static func color(_ state: CheckState) -> Color {
        switch state {
        case .passed: return success
        case .failed: return danger
        case .attention: return warning
        case .checking: return accent
        case .notChecked: return textSecondary
        }
    }

    static func label(_ state: CheckState) -> String {
        switch state {
        case let .passed(at, _): return "Passed \(at.formatted(date: .omitted, time: .shortened))"
        case .failed: return "Failed"
        case .attention: return "Needs attention"
        case .checking: return "Checking…"
        case .notChecked: return "Not tested"
        }
    }

    static func color(_ permission: MicrophonePermission) -> Color {
        switch permission {
        case .granted: return success
        case .denied, .restricted: return danger
        case .notDetermined, .unknown: return textSecondary
        }
    }

    static func color(_ readiness: ElevenLabsReadiness) -> Color {
        if !readiness.keySaved { return textSecondary }
        if readiness.speechInput.problem != nil || readiness.speechOutput.problem != nil { return warning }
        if readiness.speechInput.isPassed && (readiness.speechOutput.isPassed || !readiness.voiceIDSet) { return success }
        return warning
    }

    static func color(_ status: SpeechServiceStatus) -> Color {
        switch status {
        case .connected: return success
        case .failed: return danger
        case .checking, .configuredUnverified: return warning
        case .unconfigured: return textSecondary
        }
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var filled = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(filled ? Theme.background : Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(filled ? color : color.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

struct ModeBanner: View {
    let mode: ExecutionMode
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .simulation ? "testtube.2" : "antenna.radiowaves.left.and.right")
            Text(mode.label).font(.caption.weight(.bold)).tracking(1.2)
            Text(detail).font(.caption)
            Spacer()
        }
        .foregroundStyle(mode == .simulation ? Theme.simulation : Theme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((mode == .simulation ? Theme.simulation : Theme.warning).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.callout).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 92, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WarningBox: View {
    let warning: RenderedWarning

    var body: some View {
        let critical = warning.severity == .critical
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle")
                .foregroundStyle(critical ? Theme.danger : Theme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(critical ? "SAFETY" : "NOTE").font(.caption2.weight(.bold)).tracking(1)
                    .foregroundStyle(critical ? Theme.danger : Theme.warning)
                Text(warning.text).font(.body.weight(critical ? .semibold : .regular)).foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                if warning.isFallback {
                    Text("Shown in the original language: no translation was supplied.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background((critical ? Theme.danger : Theme.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((critical ? Theme.danger : Theme.warning).opacity(0.45)))
    }
}
