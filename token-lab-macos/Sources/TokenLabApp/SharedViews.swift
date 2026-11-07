import SwiftUI
import TokenLabCore

struct MetricTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

extension DecisionKind {
    var label: String {
        switch self {
        case .required: return "Required"
        case .retained: return "Kept"
        case .emptySkipped: return "Empty"
        case .duplicateRemoved: return "Duplicate"
        case .excludedByBudget: return "Over budget"
        }
    }
    var symbol: String {
        switch self {
        case .required: return "lock.fill"
        case .retained: return "checkmark.circle.fill"
        case .emptySkipped: return "circle.dashed"
        case .duplicateRemoved: return "doc.on.doc"
        case .excludedByBudget: return "minus.circle"
        }
    }
    var color: Color {
        switch self {
        case .required: return .blue
        case .retained: return .green
        case .emptySkipped: return .secondary
        case .duplicateRemoved: return .purple
        case .excludedByBudget: return .orange
        }
    }
}

extension ContextCategory {
    var symbol: String {
        switch self {
        case .reference: return "book"
        case .conversation: return "bubble.left.and.bubble.right"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .toolOutput: return "terminal"
        }
    }
}

struct DecisionRow: View {
    let decision: BlockDecision
    let tokenUnit: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: decision.kind.symbol).foregroundStyle(decision.kind.color).frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(decision.title).fontWeight(.medium).lineLimit(1)
                    Pill(text: decision.kind.label, color: decision.kind.color)
                    Spacer(minLength: 4)
                    Text("\(decision.standaloneTokens) \(tokenUnit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let relevance = decision.relevance {
                    RelevanceTermsView(relevance: relevance)
                }
                Text(decision.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// Shows a keyword score and exactly which task terms produced it.
struct RelevanceTermsView: View {
    let relevance: RelevanceScore
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Keyword score \(String(format: "%.2f", relevance.score))")
                .font(.caption.monospacedDigit().weight(.medium))
            if relevance.matchedTerms.isEmpty {
                Text("· no task terms found").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("·").font(.caption).foregroundStyle(.tertiary)
                Text(relevance.matchedTerms.map { "\($0.term) +\(String(format: "%.2f", $0.weight))\($0.occurrences > 1 ? " (×\($0.occurrences))" : "")" }
                        .joined(separator: ", "))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityLabel(relevance.matchedTerms.isEmpty
                            ? "Keyword score 0, no task terms found"
                            : "Keyword score \(String(format: "%.2f", relevance.score)) from \(relevance.matchedTerms.map(\.term).joined(separator: ", "))")
    }
}

/// Plain-language description of the ranking method and its limits.
struct RankingMethodView: View {
    var descriptor: RankerDescriptor = KeywordOverlapRanker().descriptor
    var taskTerms: [String]? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(descriptor.displayName) · \(descriptor.version)").font(.caption.weight(.semibold))
            if let taskTerms {
                Text(taskTerms.isEmpty ? "Task terms: none usable" : "Task terms: \(taskTerms.joined(separator: ", "))")
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(descriptor.method).font(.caption).fixedSize(horizontal: false, vertical: true)
            Text("How it combines with other settings: required blocks are always kept, whatever their score. Optional blocks are considered by keyword score, then manual priority, then prompt order, and added while the whole assembled prompt fits the budget. Retained blocks keep their original order.")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            ForEach(descriptor.limitations, id: \.self) { limitation in
                Label(limitation, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("A keyword match is not evidence that a block is useful or that an answer will be correct.")
                .font(.caption.weight(.medium)).foregroundStyle(.orange)
        }
    }
}

/// Monospaced, selectable prompt text. Very long text is shown in part, with an explicit note;
/// the copy button always copies the complete text.
struct PromptTextView: View {
    let title: String
    let text: String
    var minHeight: CGFloat = 80
    var maxHeight: CGFloat = 320
    var onCopy: (() -> Void)? = nil
    static let displayLimit = 30_000

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let onCopy {
                    Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless).controlSize(.small)
                        .help("Copy the complete text")
                }
            }
            ScrollView {
                Text(text.isEmpty ? "(empty)" : displayed)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
            if text.count > Self.displayLimit {
                Text("Showing the first \(Self.displayLimit.formatted()) of \(text.count.formatted()) characters. Copy gets the complete text.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var displayed: String {
        text.count > Self.displayLimit ? String(text.prefix(Self.displayLimit)) : text
    }
}

/// Bordered multi-line editor that works inside scroll views.
struct CodeEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 90
    var maxHeight: CGFloat = 320
    var accessibilityLabel: String
    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            .accessibilityLabel(accessibilityLabel)
    }
}

func percentString(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f%%", value)
}

/// Text-field binding for optional whole numbers (empty means "not recorded").
func optionalIntText(_ binding: Binding<Int?>) -> Binding<String> {
    Binding(
        get: { binding.wrappedValue.map(String.init) ?? "" },
        set: { newValue in
            let digits = newValue.filter { $0.isASCII && $0.isNumber }
            binding.wrappedValue = digits.isEmpty ? nil : Int(digits.prefix(12))
        })
}
