import AppKit
import Foundation
import SwiftTerm
import SwiftUI

struct BlockOutput {
    let text: AttributedString
    let plain: String
    let lineCount: Int
    let truncated: Bool

    var isEmpty: Bool { plain.isEmpty }

    static let empty = BlockOutput(text: AttributedString(), plain: "", lineCount: 0, truncated: false)
}

enum TerminalSnapshot {
    static let maxLines = 1500
    static let fontSize: CGFloat = 12

    private struct Style: Equatable {
        var foreground: SwiftUI.Color?
        var background: SwiftUI.Color?
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var dim = false
    }

    private struct Run {
        var text: String
        var style: Style
    }

    static func capture(_ terminal: SwiftTerm.Terminal) -> BlockOutput {
        var lines: [[Run]] = []
        var row = terminal.buffer.totalLinesTrimmed
        while let line = terminal.getScrollInvariantLine(row: row) {
            let runs = runs(of: line, in: terminal)
            if line.isWrapped, !lines.isEmpty {
                lines[lines.count - 1] += runs
            } else {
                lines.append(runs)
            }
            row += 1
        }
        lines = lines.map(trimmed)
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }
        while let first = lines.first, first.isEmpty {
            lines.removeFirst()
        }
        let truncated = lines.count > maxLines
        if truncated {
            lines = Array(lines.suffix(maxLines))
        }

        var text = AttributedString()
        var plain: [String] = []
        for (index, runs) in lines.enumerated() {
            if index > 0 { text.append(AttributedString("\n")) }
            for run in runs {
                text.append(attributed(run))
            }
            plain.append(runs.map(\.text).joined())
        }
        return BlockOutput(text: text, plain: plain.joined(separator: "\n"), lineCount: lines.count, truncated: truncated)
    }

    private static func runs(of line: BufferLine, in terminal: SwiftTerm.Terminal) -> [Run] {
        var runs: [Run] = []
        for column in 0..<line.count {
            let cell = line[column]
            if cell.width == 0 { continue }
            var character = terminal.getCharacter(for: cell)
            if character == "\u{0}" { character = " " }
            let style = style(of: cell.attribute)
            if var last = runs.last, last.style == style {
                last.text.append(character)
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(text: String(character), style: style))
            }
        }
        return runs
    }

    private static func trimmed(_ runs: [Run]) -> [Run] {
        var runs = runs
        while var last = runs.last {
            while last.text.last == " ", last.style.background == nil {
                last.text.removeLast()
            }
            if last.text.isEmpty {
                runs.removeLast()
            } else {
                runs[runs.count - 1] = last
                break
            }
        }
        return runs
    }

    private static func style(of attribute: Attribute) -> Style {
        var foreground = color(attribute.fg)
        var background = color(attribute.bg)
        if attribute.style.contains(.inverse) {
            let swappedForeground = background ?? Theme.loom
            background = foreground ?? Theme.text2
            foreground = swappedForeground
        }
        if attribute.style.contains(.invisible) {
            foreground = background ?? Theme.loom
        }
        return Style(
            foreground: foreground,
            background: background,
            bold: attribute.style.contains(.bold),
            italic: attribute.style.contains(.italic),
            underline: attribute.underlineStyle != .none,
            strikethrough: attribute.style.contains(.crossedOut),
            dim: attribute.style.contains(.dim)
        )
    }

    private static func color(_ color: Attribute.Color) -> SwiftUI.Color? {
        switch color {
        case .defaultColor, .defaultInvertedColor:
            return nil
        case .trueColor(let red, let green, let blue):
            return SwiftUI.Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        case .ansi256(let code):
            return SwiftUI.Color(hex: rgb(ansi256: Int(code)))
        }
    }

    static func rgb(ansi256 code: Int) -> UInt32 {
        if code < 16 { return Theme.ansi[code] }
        if code < 232 {
            let index = code - 16
            let levels = [0, 95, 135, 175, 215, 255]
            let red = levels[index / 36]
            let green = levels[index / 6 % 6]
            let blue = levels[index % 6]
            return UInt32(red << 16 | green << 8 | blue)
        }
        let gray = 8 + (code - 232) * 10
        return UInt32(gray << 16 | gray << 8 | gray)
    }

    private static func attributed(_ run: Run) -> AttributedString {
        var piece = AttributedString(run.text)
        var font = Font.system(size: fontSize, weight: run.style.bold ? .bold : .regular, design: .monospaced)
        if run.style.italic { font = font.italic() }
        piece.font = font
        if let foreground = run.style.foreground {
            piece.foregroundColor = run.style.dim ? foreground.opacity(0.6) : foreground
        } else if run.style.dim {
            piece.foregroundColor = Theme.faded
        }
        if let background = run.style.background { piece.backgroundColor = background }
        if run.style.underline { piece.underlineStyle = .single }
        if run.style.strikethrough { piece.strikethroughStyle = .single }
        return piece
    }
}
