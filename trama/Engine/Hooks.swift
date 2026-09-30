import Foundation

public enum Hooks {
    struct Event {
        let name: String
        let async: Bool
    }

    static let events: [Event] = [
        Event(name: "SessionStart", async: false),
        Event(name: "UserPromptSubmit", async: true),
        Event(name: "PostToolUse", async: true),
        Event(name: "Notification", async: true),
        Event(name: "Stop", async: true),
        Event(name: "SessionEnd", async: true),
    ]

    public static var eventNames: [String] { events.map(\.name) }

    public static func settingsPath() -> String {
        Paths.join(Paths.home, ".claude", "settings.json")
    }

    static func command(_ executable: String) -> String {
        if executable.contains(where: { $0 == " " || $0 == "'" || $0 == "\"" }) {
            return "\"\(executable.replacingOccurrences(of: "\"", with: "\\\""))\" hook"
        }
        return executable + " hook"
    }

    private static func commandFromEntry(_ entry: Any) -> String? {
        guard let m = entry as? [String: Any], let hs = m["hooks"] as? [Any] else { return nil }
        for h in hs {
            guard let hm = h as? [String: Any], let cmd = hm["command"] as? String else { continue }
            let c = cmd.trimmingCharacters(in: .whitespaces)
            if c.contains("trama") && c.hasSuffix(" hook") {
                return c
            }
        }
        return nil
    }

    private static func read(_ path: String) throws -> (settings: [String: Any], original: Data?) {
        guard let text = try File.read(path) else { return ([:], nil) }
        let data = Data(text.utf8)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ([:], data) }
        guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TramaError("\(path) não é um JSON válido · não vou mexer nele")
        }
        return (m, data)
    }

    private static func write(_ path: String, _ settings: [String: Any], original: Data?) throws {
        if let original {
            let copy = path + ".antes-da-trama"
            if !Paths.exists(copy) {
                try File.write(original, to: copy)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try File.write(data + Data("\n".utf8), to: path)
    }

    public static func install(settings path: String = settingsPath(), executable: String) throws {
        let loaded = try read(path)
        var m = loaded.settings
        var hooks = m["hooks"] as? [String: Any] ?? [:]
        let cmd = command(executable)
        for ev in events {
            var list = (hooks[ev.name] as? [Any] ?? []).filter { commandFromEntry($0) == nil }
            var h: [String: Any] = ["type": "command", "command": cmd, "timeout": 10]
            if ev.async { h["async"] = true }
            list.append(["hooks": [h]])
            hooks[ev.name] = list
        }
        m["hooks"] = hooks
        try write(path, m, original: loaded.original)
    }

    @discardableResult
    public static func remove(settings path: String = settingsPath()) throws -> Int {
        let loaded = try read(path)
        var m = loaded.settings
        guard var hooks = m["hooks"] as? [String: Any] else { return 0 }
        var removed = 0
        for (name, value) in hooks {
            guard let list = value as? [Any] else { continue }
            let kept = list.filter { commandFromEntry($0) == nil }
            removed += list.count - kept.count
            hooks[name] = kept.isEmpty ? nil : kept
        }
        guard removed > 0 else { return 0 }
        m["hooks"] = hooks.isEmpty ? nil : hooks
        try write(path, m, original: loaded.original)
        return removed
    }

    public static func status(settings path: String = settingsPath()) throws -> [String: Bool] {
        let hooks = try read(path).settings["hooks"] as? [String: Any] ?? [:]
        var out: [String: Bool] = [:]
        for ev in events {
            let list = hooks[ev.name] as? [Any] ?? []
            out[ev.name] = list.contains { commandFromEntry($0) != nil }
        }
        return out
    }

    public static func installedCommand(settings path: String = settingsPath()) -> String? {
        guard let loaded = try? read(path),
              let hooks = loaded.settings["hooks"] as? [String: Any],
              let list = hooks["SessionStart"] as? [Any] else { return nil }
        return list.lazy.compactMap { commandFromEntry($0) }.first
    }

    @discardableResult
    public static func repointIfNeeded(settings path: String = settingsPath(), executable: String) -> Bool {
        guard let current = installedCommand(settings: path), current != command(executable) else { return false }
        return (try? install(settings: path, executable: executable)) != nil
    }
}
