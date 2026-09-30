import AppKit
import Foundation

enum ClaudeTarget: String, CaseIterable, Identifiable {
    case cli
    case desktop

    static let storageKey = "claudeTarget"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cli: return "CLI embutido"
        case .desktop: return "Claude Desktop"
        }
    }

    static var current: ClaudeTarget {
        ClaudeTarget(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .cli
    }

    /// URL que o Claude Desktop trata como "nova sessão do Claude Code nesta pasta".
    static func desktopURL(folder: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/")
        guard let encoded = folder.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "claude://code/new?folder=\(encoded)&source=trama")
    }
}
