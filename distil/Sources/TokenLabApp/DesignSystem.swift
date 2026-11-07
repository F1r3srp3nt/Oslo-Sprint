import SwiftUI
import AppKit

// Shared visual language for the Oslo Sprint products. The same file is kept in each product so
// both stay independently buildable; keep the copies identical when changing either.
//
// Rules: colour never carries meaning alone (every status also has text and usually a symbol);
// cyan is the interface accent; green, amber and red are reserved for real states; decoration is
// static and disappears with Increase Contrast; motion respects Reduce Motion.

enum DS {
    // MARK: Colour tokens (dark first, with a readable light variant)

    static let canvas = dynamic(dark: (0.027, 0.043, 0.082), light: (0.925, 0.945, 0.972))
    static let canvasGlow = dynamic(dark: (0.051, 0.106, 0.204), light: (0.870, 0.912, 0.965))
    static let surface = dynamic(dark: (0.055, 0.086, 0.149), light: (1.000, 1.000, 1.000))
    static let surfaceRaised = dynamic(dark: (0.078, 0.118, 0.192), light: (0.960, 0.972, 0.988))
    static let surfaceSunken = dynamic(dark: (0.033, 0.054, 0.098), light: (0.972, 0.980, 0.992))
    static let accent = dynamic(dark: (0.33, 0.82, 0.96), light: (0.00, 0.42, 0.60))
    static let textPrimary = dynamic(dark: (0.93, 0.95, 0.98), light: (0.06, 0.09, 0.16))
    static let textSecondary = dynamic(dark: (0.69, 0.75, 0.85), light: (0.26, 0.31, 0.41))
    static let textTertiary = dynamic(dark: (0.52, 0.59, 0.70), light: (0.40, 0.45, 0.54))
    static let success = dynamic(dark: (0.38, 0.85, 0.57), light: (0.04, 0.48, 0.24))
    static let warning = dynamic(dark: (0.98, 0.75, 0.33), light: (0.60, 0.37, 0.00))
    static let danger = dynamic(dark: (0.98, 0.46, 0.46), light: (0.72, 0.13, 0.13))
    static let simulation = dynamic(dark: (0.72, 0.64, 0.98), light: (0.40, 0.28, 0.74))
    static let gridLine = dynamic(dark: (0.33, 0.82, 0.96), light: (0.00, 0.42, 0.60))

    /// Fine panel border. Stronger when the user asks for more contrast.
    static func border(_ contrast: ColorSchemeContrast, emphasised: Bool = false) -> Color {
        let base = emphasised ? 0.42 : 0.16
        return accent.opacity(contrast == .increased ? min(1, base * 2.6) : base)
    }

    static func secondaryText(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? textPrimary : textSecondary
    }

    // MARK: Spacing, radii, typography

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6, panel: CGFloat = 10, large: CGFloat = 14
    }

    enum Typeface {
        static let pageTitle = Font.system(size: 20, weight: .semibold)
        static let sectionTitle = Font.headline
        static let caption = Font.caption
        static let label = Font.caption2.weight(.semibold)
        static let mono = Font.system(.callout, design: .monospaced)
        static let monoSmall = Font.system(.caption, design: .monospaced)
        static let metric = Font.system(.title2, design: .monospaced).weight(.semibold)
        static let editor = Font.system(size: 13, design: .monospaced)
        static let sidebarIcon = Font.system(size: 13, weight: .medium)
    }

    /// An animation, or none when Reduce Motion is on.
    static func motion(_ reduceMotion: Bool, _ animation: Animation = .easeOut(duration: 0.14)) -> Animation? {
        reduceMotion ? nil : animation
    }

    private static func dynamic(dark: (CGFloat, CGFloat, CGFloat), light: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

// MARK: - Tones (meaningful states)

enum DSTone {
    case neutral, accent, success, warning, danger, simulation

    var color: Color {
        switch self {
        case .neutral: return DS.textSecondary
        case .accent: return DS.accent
        case .success: return DS.success
        case .warning: return DS.warning
        case .danger: return DS.danger
        case .simulation: return DS.simulation
        }
    }
}

// MARK: - Backgrounds and surfaces

/// Near-black navy canvas with a restrained blue gradient and a very faint, static technical grid.
struct DSBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            DS.canvas
            LinearGradient(colors: [DS.canvasGlow, DS.canvas], startPoint: .top, endPoint: .center)
            RadialGradient(colors: [DS.accent.opacity(0.05), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
            if contrast != .increased { DSGrid() }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct DSGrid: View {
    var spacing: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            context.stroke(path, with: .color(DS.gridLine.opacity(0.045)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

struct DSPanelModifier: ViewModifier {
    var padding: CGFloat = DS.Space.m
    var raised = false
    var highlighted = false
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .fill(raised ? DS.surfaceRaised : DS.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(DS.border(contrast, emphasised: highlighted), lineWidth: highlighted ? 1.25 : 1))
    }
}

extension View {
    /// A layered dark panel with a fine cyan border.
    func dsPanel(padding: CGFloat = DS.Space.m, raised: Bool = false, highlighted: Bool = false) -> some View {
        modifier(DSPanelModifier(padding: padding, raised: raised, highlighted: highlighted))
    }

    /// Column and field captions in tables and metric summaries.
    func dsColumnHeader() -> some View {
        font(DS.Typeface.label).textCase(.uppercase).tracking(0.6).foregroundStyle(DS.textTertiary)
    }
}

/// Panel styling for every `GroupBox` beneath the view it is applied to.
struct DSPanelGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            configuration.label
                .font(DS.Typeface.sectionTitle)
                .foregroundStyle(DS.textPrimary)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanel()
    }
}

/// Sunken background and fine border for editors and plain text fields; cyan when focused.
struct DSFieldChrome: ViewModifier {
    var focused = false
    var radius: CGFloat = 8
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(DS.surfaceSunken, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(focused ? DS.accent.opacity(0.75) : DS.border(contrast), lineWidth: focused ? 1.5 : 1))
    }
}

extension View {
    func dsFieldChrome(focused: Bool = false, radius: CGFloat = 8) -> some View {
        modifier(DSFieldChrome(focused: focused, radius: radius))
    }
}

// MARK: - Page structure

struct DSPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DS.Typeface.pageTitle).foregroundStyle(DS.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.callout).foregroundStyle(DS.secondaryText(contrast))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.m)
            accessory
        }
        .padding(.horizontal, DS.Space.xl - 4)
        .padding(.vertical, DS.Space.m + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.border(contrast)).frame(height: 1) }
    }
}

extension DSPageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Sidebar

struct DSSidebarItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let symbol: String
    var badge: Int = 0
    /// Spoken meaning of the badge, e.g. "3 need attention".
    var badgeDescription: String? = nil
}

struct DSSidebarGroup<ID: Hashable>: Identifiable {
    let title: String?
    let items: [DSSidebarItem<ID>]
    var id: String { title ?? "group-\(items.first.map { "\($0.id)" } ?? "")" }
}

/// Persistent navigation list. Click or use ↑/↓ when focused (Tab to focus); the menu shortcuts
/// keep working. Selection is shown with a tint, bold text and a cyan indicator, not colour alone.
struct DSSidebar<ID: Hashable, Footer: View>: View {
    let groups: [DSSidebarGroup<ID>]
    @Binding var selection: ID
    var topInset: CGFloat = 0
    @ViewBuilder var footer: Footer
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        if let title = group.title {
                            Text(title)
                                .font(DS.Typeface.label).textCase(.uppercase).tracking(1.1)
                                .foregroundStyle(DS.textTertiary)
                                .padding(.leading, 12).padding(.top, DS.Space.m).padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.items) { item in
                            DSSidebarRow(item: item, selected: item.id == selection, keyboardFocused: focused) { select(item.id) }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.top, topInset + DS.Space.xs)
                .padding(.bottom, DS.Space.s)
            }
            footer
        }
        .frame(maxHeight: .infinity)
        .background(DS.surface.opacity(0.6))
        .overlay(alignment: .trailing) { Rectangle().fill(DS.border(contrast)).frame(width: 1) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onMoveCommand(perform: move)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    private var order: [ID] { groups.flatMap { $0.items.map(\.id) } }

    private func select(_ id: ID) {
        withAnimation(DS.motion(reduceMotion)) { selection = id }
    }

    private func move(_ direction: MoveCommandDirection) {
        guard let index = order.firstIndex(of: selection) else { return }
        switch direction {
        case .up where index > 0: select(order[index - 1])
        case .down where index < order.count - 1: select(order[index + 1])
        default: break
        }
    }
}

struct DSSidebarRow<ID: Hashable>: View {
    let item: DSSidebarItem<ID>
    let selected: Bool
    let keyboardFocused: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(DS.Typeface.sidebarIcon)
                    .frame(width: 18)
                    .foregroundStyle(selected ? DS.accent : DS.textSecondary)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.textPrimary : DS.secondaryText(contrast))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.badge > 0 {
                    Text("\(item.badge)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(DS.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(DS.border(contrast)))
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(selected ? DS.accent.opacity(contrast == .increased ? 0.26 : 0.14)
                               : (hovering ? DS.textPrimary.opacity(0.05) : Color.clear)))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(DS.accent).frame(width: 3, height: 16).padding(.leading, 3)
                }
            }
            .overlay {
                if selected && keyboardFocused {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(DS.accent.opacity(0.8), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(item.badge > 0 ? "\(item.title), \(item.badgeDescription ?? "\(item.badge)")" : item.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Status, metrics, empty states

/// Status label: always text, usually a symbol, with the tone as reinforcement only.
struct DSBadge: View {
    let text: String
    var systemImage: String? = nil
    var tone: DSTone = .neutral
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tone == .neutral ? DS.secondaryText(contrast) : tone.color)
        .padding(.horizontal, 7).padding(.vertical, 2.5)
        .background(tone.color.opacity(tone == .neutral ? 0.10 : 0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tone.color.opacity(contrast == .increased ? 0.85 : 0.35)))
        .accessibilityElement(children: .combine)
    }
}

/// A measurement. Values use monospaced digits; the caption says what the number is (and is not).
struct DSMetric: View {
    let title: String
    let value: String
    var caption: String? = nil
    var systemImage: String? = nil
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small).foregroundStyle(DS.accent) }
                Text(title).dsColumnHeader()
            }
            Text(value)
                .font(DS.Typeface.metric).monospacedDigit()
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(DS.secondaryText(contrast)).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanel(padding: DS.Space.m, raised: true)
        .accessibilityElement(children: .combine)
    }
}

struct DSEmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        ContentUnavailableView {
            Label { Text(title).foregroundStyle(DS.textPrimary) } icon: { Image(systemName: systemImage).foregroundStyle(DS.accent) }
        } description: {
            Text(message)
        } actions: {
            actions
        }
    }
}
