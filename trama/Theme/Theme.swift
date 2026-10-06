import AppKit
import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0C0D10)
    static let panel = Color(hex: 0x0F1014)
    static let loom = Color(hex: 0x0E0F13)
    static let field = Color(hex: 0x121318)
    static let surface = Color(hex: 0x15171C)
    static let surface2 = Color(hex: 0x1A1C22)
    static let line = Color(hex: 0x1F2228)
    static let line2 = Color(hex: 0x2A2D34)
    static let thread = Color(hex: 0x3A3E47)
    static let ring = Color(hex: 0x9A9EA8)

    static let text = Color(hex: 0xECEDEF)
    static let text2 = Color(hex: 0xD5D7DC)
    static let text3 = Color(hex: 0xB4B8C0)
    static let faded = Color(hex: 0x8B909A)

    static let ember = Color(hex: 0xFF8A4C)
    static let emberLight = Color(hex: 0xFFB07F)
    static let emberText = Color(hex: 0xFFC9A8)
    static let emberDark = Color(hex: 0x1A0D05)
    static let waveBackground = Color(hex: 0x1A1415)

    static let iris = Color(hex: 0xA9B4FF)
    static let irisText = Color(hex: 0xC9CDF9)
    static let ok = Color(hex: 0x62D394)
    static let okText = Color(hex: 0x8FE0B0)
    static let danger = Color(hex: 0xEF6F6C)
    static let dangerText = Color(hex: 0xF4A3A1)
    static let wait = Color(hex: 0xF2C14E)
    static let waitText = Color(hex: 0xF5D98A)

    static let lanes: [Color] = [
        ember, iris, ok, wait, Color(hex: 0x5FD1D1), Color(hex: 0xC792EA), Color(hex: 0x7C9CFF), danger,
    ]

    static func lane(_ index: Int) -> Color {
        lanes[((index % lanes.count) + lanes.count) % lanes.count]
    }

    static let ansi: [UInt32] = [
        0x1A1C22, 0xEF6F6C, 0x62D394, 0xF2C14E, 0x7C9CFF, 0xC792EA, 0x5FD1D1, 0xD5D7DC,
        0x4A4E57, 0xF4A3A1, 0x8FE0B0, 0xF5D98A, 0xA9B4FF, 0xDDB6F2, 0x9DE3E3, 0xECEDEF,
    ]

    static func serif(_ size: CGFloat) -> Font {
        if NSFont(name: "Instrument Serif", size: size) != nil {
            return .custom("Instrument Serif", size: size)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct GhostButton: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 12.5))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: compact ? 28 : 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Theme.surface2 : Theme.surface)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct EmberButton: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 12.5, weight: .semibold))
            .foregroundStyle(Theme.emberDark)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: compact ? 28 : 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.ember.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .contentShape(Rectangle())
    }
}

struct ToneButton: ButtonStyle {
    let color: Color
    let text: Color
    var height: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(text)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(configuration.isPressed ? 0.2 : 0.12))
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct IconButton: ButtonStyle {
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.text3)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Theme.surface2 : Theme.surface)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.text3
    var background: Color = Theme.surface

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(background))
            .overlay(Capsule().stroke(Theme.line2, lineWidth: 1))
    }
}

struct StatusNote<Content: View>: View {
    enum Tone { case ok, wait, neutral }
    let icon: String
    var tone: Tone = .neutral
    @ViewBuilder let content: () -> Content

    var tint: Color {
        switch tone {
        case .ok: return Theme.ok
        case .wait: return Theme.wait
        case .neutral: return Theme.faded
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            content()
        }
        .font(Theme.mono(11.5))
        .foregroundStyle(Theme.text3)
        .lineLimit(1)
        .frame(height: 26)
    }
}

extension StatusNote where Content == Text {
    init(icon: String, tone: Tone = .neutral, text: String) {
        self.init(icon: icon, tone: tone) { Text(text) }
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(Theme.faded)
    }
}

struct KeyCap: View {
    let text: String
    var dark = false

    var body: some View {
        Text(text)
            .font(Theme.mono(10.5))
            .tracking(2)
            .foregroundStyle(dark ? Theme.emberDark : Theme.faded)
            .padding(.leading, 7)
            .padding(.trailing, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(dark ? Theme.emberDark.opacity(0.14) : Theme.surface2)
            )
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 7
    var halo = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(color.opacity(halo ? 0.2 : 0))
                    .frame(width: size + 6, height: size + 6)
            )
    }
}

struct TramaLogo: View {
    var size: CGFloat = 22

    var body: some View {
        Image("TramaMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct MarkerThread: View {
    let highlighted: Bool
    let dashed: Bool

    var body: some View {
        if dashed {
            Path { p in
                p.move(to: CGPoint(x: 1, y: 0))
                p.addLine(to: CGPoint(x: 1, y: 26))
            }
            .stroke(Theme.thread, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            .frame(width: 2, height: 26)
        } else {
            RoundedRectangle(cornerRadius: 1)
                .fill(highlighted ? Theme.ember : Color(hex: 0x4A4E57))
                .frame(width: 2, height: 26)
                .shadow(color: highlighted ? Theme.ember.opacity(0.7) : Color.clear, radius: 4)
        }
    }
}

struct CollapsibleSection<Trailing: View, Content: View>: View {
    let title: String
    let collapseLabel: String
    @AppStorage private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let trailing: Trailing
    private let content: Content

    init(
        title: String,
        collapseLabel: String,
        storageKey: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.collapseLabel = collapseLabel
        self._expanded = AppStorage(wrappedValue: true, storageKey)
        self.trailing = trailing()
        self.content = content()
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(animation) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.faded)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    SectionLabel(text: title)
                    Spacer(minLength: 0)
                    trailing
                        .opacity(expanded ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Recolher \(collapseLabel)" : "Expandir \(collapseLabel)")

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -10)).combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity.combined(with: .offset(y: -6)).combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            }
        }
        .clipped()
    }
}

extension CollapsibleSection where Trailing == EmptyView {
    init(
        title: String,
        collapseLabel: String,
        storageKey: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, collapseLabel: collapseLabel, storageKey: storageKey, trailing: { EmptyView() }, content: content)
    }
}

/// ScrollView com esmaecimento desfocado no topo (efeito de borda nativo do macOS 26).
/// O blur é aplicado pelo sistema sobre o conteúdo que rola por baixo da barra do topo.
struct BlurScrollView<Content: View>: View {
    var height: CGFloat = 36
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
        }
        .scrollEdgeEffectHidden(false, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaBar(edge: .top, spacing: 0) {
            Rectangle()
                .fill(Theme.background.opacity(0.01))
                .frame(height: height)
        }
    }
}
