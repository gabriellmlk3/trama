import Foundation

public struct ClaudeConversation: Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var modifiedAt: Date
}

public enum ClaudeSessions {
    private static let headBytes = 256 * 1024

    public static func projectDirectory(for path: String, home: String = Paths.home) -> String {
        let encoded = String(path.unicodeScalars.map { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
        return Paths.join(home, ".claude", "projects", encoded)
    }

    public static func hasHistory(at path: String, home: String = Paths.home) -> Bool {
        !conversationFiles(at: path, home: home).isEmpty
    }

    public static func conversations(at path: String, limit: Int = 8, home: String = Paths.home) -> [ClaudeConversation] {
        conversationFiles(at: path, home: home)
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { file in
                ClaudeConversation(id: file.id, title: title(ofFile: file.path) ?? "Conversa sem título", modifiedAt: file.modifiedAt)
            }
    }

    private struct ConversationFile {
        var id: String
        var path: String
        var modifiedAt: Date
    }

    private static func conversationFiles(at path: String, home: String) -> [ConversationFile] {
        let fm = FileManager.default
        var seen = Set<String>()
        var files: [ConversationFile] = []
        for candidate in [path, Paths.real(path)] {
            let dir = projectDirectory(for: candidate, home: home)
            guard seen.insert(dir).inserted else { continue }
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".jsonl") {
                let file = Paths.join(dir, name)
                let modified = (try? fm.attributesOfItem(atPath: file)[.modificationDate] as? Date) ?? .distantPast
                files.append(ConversationFile(id: String(name.dropLast(6)), path: file, modifiedAt: modified))
            }
        }
        return files
    }

    private static func title(ofFile path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headBytes) else { return nil }
        var custom: String?
        var firstPrompt: String?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "custom-title":
                if let t = object["customTitle"] as? String, !t.isEmpty { custom = t }
            case "user":
                guard firstPrompt == nil,
                      object["isMeta"] as? Bool != true,
                      let message = object["message"] as? [String: Any],
                      let text = message["content"] as? String,
                      !text.hasPrefix("<") else { continue }
                firstPrompt = text
            default:
                continue
            }
        }
        guard let raw = custom ?? firstPrompt else { return nil }
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        return line.count > 70 ? String(line.prefix(70)) + "…" : line
    }
}
