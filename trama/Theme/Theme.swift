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
    static let wait = Color(hex: 0xF2C14E)
    static let waitText = Color(hex: 0xF5D98A)

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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(text)
            .padding(.horizontal, 10)
            .frame(height: 28)
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
            .foregroundStyle(dark ? Theme.emberDark : Theme.faded)
            .padding(.horizontal, 5)
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
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 24
            var h = Path()
            h.move(to: CGPoint(x: 3 * s, y: 7 * s)); h.addLine(to: CGPoint(x: 10.2 * s, y: 7 * s))
            h.move(to: CGPoint(x: 13.8 * s, y: 7 * s)); h.addLine(to: CGPoint(x: 21 * s, y: 7 * s))
            h.move(to: CGPoint(x: 3 * s, y: 12 * s)); h.addLine(to: CGPoint(x: 21 * s, y: 12 * s))
            h.move(to: CGPoint(x: 3 * s, y: 17 * s)); h.addLine(to: CGPoint(x: 10.2 * s, y: 17 * s))
            h.move(to: CGPoint(x: 13.8 * s, y: 17 * s)); h.addLine(to: CGPoint(x: 21 * s, y: 17 * s))
            ctx.stroke(h, with: .color(Color(hex: 0x4A4E57)), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
            var v = Path()
            v.move(to: CGPoint(x: 12 * s, y: 3 * s)); v.addLine(to: CGPoint(x: 12 * s, y: 9.3 * s))
            v.move(to: CGPoint(x: 12 * s, y: 14.7 * s)); v.addLine(to: CGPoint(x: 12 * s, y: 21 * s))
            ctx.stroke(v, with: .color(Theme.ember), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        }
        .frame(width: size, height: size)
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
