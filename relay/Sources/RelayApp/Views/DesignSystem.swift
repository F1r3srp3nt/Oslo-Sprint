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

    static let canvas = dynamic(dark: (0.035, 0.059, 0.098), light: (0.925, 0.945, 0.972))
    static let canvasGlow = dynamic(dark: (0.047, 0.137, 0.196), light: (0.870, 0.920, 0.955))
    static let surface = dynamic(dark: (0.059, 0.106, 0.157), light: (1.000, 1.000, 1.000))
    static let surfaceRaised = dynamic(dark: (0.082, 0.141, 0.204), light: (0.960, 0.972, 0.988))
    static let surfaceSunken = dynamic(dark: (0.031, 0.063, 0.102), light: (0.972, 0.980, 0.992))
    static let accent = dynamic(dark: (0.30, 0.83, 0.93), light: (0.00, 0.42, 0.58))
    /// Text and icons placed on a filled accent (or tone) background.
    static let onAccent = dynamic(dark: (0.027, 0.055, 0.090), light: (1.0, 1.0, 1.0))
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
        let base = emphasised ? 0.50 : 0.20
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
        static let control: CGFloat = 8, panel: CGFloat = 12, large: CGFloat = 16
    }

    enum Typeface {
        static let pageTitle = Font.system(size: 24, weight: .bold)
        /// Breadcrumbs and eyebrows above titles: monospaced capitals.
        static let eyebrow = Font.system(size: 11, weight: .bold, design: .monospaced)
        static let brand = Font.system(size: 15, weight: .heavy)
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
            context.stroke(path, with: .color(DS.gridLine.opacity(0.07)), lineWidth: 0.5)
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
    /// Breadcrumb shown above the title, e.g. "DISTIL / WORKSPACE".
    var eyebrow: String? = nil
    @ViewBuilder var accessory: Accessory
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow {
                    Text(eyebrow).font(DS.Typeface.eyebrow).tracking(1.4).foregroundStyle(DS.accent)
                        .accessibilityHidden(true)
                }
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
    init(title: String, subtitle: String, eyebrow: String? = nil) {
        self.init(title: title, subtitle: subtitle, eyebrow: eyebrow) { EmptyView() }
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
    /// Product name and descriptor shown as text at the top (no logo).
    var brandName: String? = nil
    var brandTagline: String? = nil
    @ViewBuilder var footer: Footer
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let brandName {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(brandName).font(DS.Typeface.brand).tracking(2.2).foregroundStyle(DS.textPrimary)
                            if let brandTagline {
                                Text(brandTagline).font(DS.Typeface.label).textCase(.uppercase).tracking(1.3)
                                    .foregroundStyle(DS.textTertiary)
                            }
                            Rectangle().fill(DS.accent.opacity(0.35)).frame(width: 28, height: 2).padding(.top, 6)
                        }
                        .padding(.leading, 12).padding(.bottom, DS.Space.s)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    }
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
        .onMoveCommand { move($0) }
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
                    .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.textPrimary : DS.secondaryText(contrast))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if item.badge > 0 {
                    Text("\(item.badge)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(DS.accent.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(DS.accent.opacity(0.35)))
                }
            }
            .padding(.vertical, 7)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(selected ? DS.accent.opacity(contrast == .increased ? 0.36 : 0.24)
                               : (hovering ? DS.textPrimary.opacity(0.05) : Color.clear)))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(DS.accent.opacity(0.45), lineWidth: 1)
                }
            }
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(DS.accent).frame(width: 3, height: 22).offset(x: -7)
                        .shadow(color: contrast == .increased ? .clear : DS.accent.opacity(0.7), radius: 4)
                }
            }
            .shadow(color: selected && contrast != .increased ? DS.accent.opacity(0.18) : .clear, radius: 8)
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

// MARK: - Buttons, tiles, status cards

/// Filled primary action: tone fill with dark text (high contrast on light cyan), clear pressed and
/// disabled states. Keyboard focus rings are drawn by the system.
struct DSPrimaryButtonStyle: ButtonStyle {
    var tone: DSTone = .accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: controlSize == .large ? 14 : 13, weight: .semibold))
            .foregroundStyle(DS.onAccent)
            .padding(.horizontal, controlSize == .small ? 10 : 14)
            .padding(.vertical, controlSize == .large ? 8 : (controlSize == .small ? 3 : 5))
            .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(tone.color.opacity(configuration.isPressed ? 0.75 : 1)))
            .shadow(color: isEnabled && contrast != .increased ? tone.color.opacity(0.35) : .clear, radius: 6)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

/// Rounded-square symbol tile used to anchor cards.
struct DSIconTile: View {
    let systemImage: String
    var tone: DSTone = .accent
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tone.color)
            .frame(width: size, height: size)
            .background(tone.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tone.color.opacity(0.35)))
            .accessibilityHidden(true)
    }
}

struct DSStatusRow: Identifiable {
    let label: String
    let value: String
    var systemImage: String
    var tone: DSTone = .neutral
    var id: String { label }
}

/// Small bordered status card (for example at the bottom of a sidebar): caption label, value, and a
/// symbol whose colour reinforces, but never replaces, the text.
struct DSStatusCard: View {
    let rows: [DSStatusRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.label).dsColumnHeader()
                        Text(row.value).font(.caption.weight(.semibold)).foregroundStyle(DS.textPrimary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: row.systemImage).imageScale(.small).foregroundStyle(row.tone.color)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPanel(padding: 10, raised: true)
    }
}

// MARK: - Appearance

/// App appearance. Futuristic (the dark navy skin) is the default. Light and Match System use the same
/// components with the light token variants.
enum DSAppearance: String, CaseIterable, Identifiable {
    case futuristic = "Futuristic"
    case system = "System"
    case light = "Light"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .futuristic: return "Futuristic (dark navy)"
        case .system: return "Match System"
        case .light: return "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .futuristic: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    static let storageKey = "appearance"
    private static let migrationKey = "appearanceFuturisticDefaultApplied"

    /// Reads a stored value. "Dark" was offered before Futuristic existed and shows the same skin.
    static func resolve(_ stored: String) -> DSAppearance {
        if stored == "Dark" { return .futuristic }
        return DSAppearance(rawValue: stored) ?? .futuristic
    }

    /// Run once at launch: installations that never chose, or were on the old "Match System" default,
    /// move to Futuristic. An explicit Light (or Dark) choice is kept. Choosing Match System again later
    /// is respected because this runs only once.
    static func applyFuturisticDefault(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let stored = defaults.string(forKey: storageKey)
        if stored == nil || stored == DSAppearance.system.rawValue {
            defaults.set(DSAppearance.futuristic.rawValue, forKey: storageKey)
        }
        defaults.set(true, forKey: migrationKey)
    }
}

extension View {
    /// Navy window toolbar that matches the canvas (dark toolbar text when the scheme is dark).
    func dsWindowChrome(_ appearance: DSAppearance) -> some View {
        self
            .toolbarBackground(DS.canvas, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarColorScheme(appearance.colorScheme, for: .windowToolbar)
    }
}

// MARK: - Inputs

/// Themed single-line input: sunken field with a fine border that turns cyan while focused.
/// Keeps native text editing and keyboard behaviour; only the chrome is custom.
struct DSInputModifier: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .dsFieldChrome(focused: focused, radius: DS.Radius.control)
    }
}

extension View {
    func dsInput() -> some View { modifier(DSInputModifier()) }
}

// MARK: - Sidebar layout

/// Width rules for a persistent sidebar beside a detail pane in one HStack (no split view).
enum DSSidebarLayout {
    static func width(stored: Double, windowWidth: CGFloat, range: ClosedRange<CGFloat>, detailMinimum: CGFloat) -> CGFloat {
        let upper = max(range.lowerBound, min(range.upperBound, windowWidth - detailMinimum - DSSidebarResizeHandle.thickness))
        return min(max(CGFloat(stored), range.lowerBound), upper)
    }
}

/// Drag to resize the sidebar. Also adjustable with VoiceOver (increment/decrement).
struct DSSidebarResizeHandle: View {
    static let thickness: CGFloat = 5
    @Binding var width: Double
    let range: ClosedRange<CGFloat>
    @State private var dragStart: Double?
    @State private var hovering = false
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.thickness)
            .frame(maxHeight: .infinity)
            .overlay(Rectangle().fill(DS.accent.opacity(hovering || dragStart != nil ? 0.45 : 0.16)).frame(width: 1))
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                updateCursor()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? width
                        dragStart = start
                        width = clamp(start + Double(value.translation.width))
                    }
                    .onEnded { _ in dragStart = nil; updateCursor() }
            )
            .onDisappear { if cursorPushed { NSCursor.pop(); cursorPushed = false } }
            .accessibilityElement()
            .accessibilityLabel("Sidebar width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = clamp(width + 10)
                case .decrement: width = clamp(width - 10)
                @unknown default: break
                }
            }
            .help("Drag to resize the sidebar")
    }

    /// Keep the resize cursor while hovering or dragging; push and pop stay balanced.
    private func updateCursor() {
        let wanted = hovering || dragStart != nil
        if wanted && !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
        if !wanted && cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, Double(range.lowerBound)), Double(range.upperBound))
    }
}
