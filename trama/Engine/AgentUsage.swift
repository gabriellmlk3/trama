import Foundation

enum AgentUsage {
    static let defaultWindow = 200_000
    private static let locale = Locale(identifier: "pt_BR")

    static func percent(used: Int, window: Int) -> Int {
        Int((Double(used) / Double(max(window, 1)) * 100).rounded())
    }

    static func label(used: Int, window: Int) -> String? {
        guard used > 0 else { return nil }
        return "Contexto \(percent(used: used, window: window))% · \(compact(used)) de \(compact(window))"
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
