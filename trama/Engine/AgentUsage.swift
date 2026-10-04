import Foundation

enum AgentUsage {
    private static let locale = Locale(identifier: "pt_BR")

    static func label(cost: Double, tokens: Int) -> String? {
        var parts: [String] = []
        if cost > 0 { parts.append(money(cost)) }
        if tokens > 0 { parts.append("\(compact(tokens)) tokens") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(locale).precision(.fractionLength(value < 0.01 ? 4 : 2)))
    }

    static func compact(_ tokens: Int) -> String {
        switch tokens {
        case ..<1_000:
            return "\(tokens)"
        case ..<1_000_000:
            return scaled(Double(tokens) / 1_000) + " mil"
        default:
            return scaled(Double(tokens) / 1_000_000) + " mi"
        }
    }

    private static func scaled(_ value: Double) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...1)))
    }
}
