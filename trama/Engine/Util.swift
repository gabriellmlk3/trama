import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct TramaError: Error, LocalizedError, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
    public var description: String { message }

    public static let notInitialized = TramaError("o Trama ainda não foi configurado · rode `trama init`")
}

public func errorMessage(_ error: Error) -> String {
    if let e = error as? TramaError { return e.message }
    if let e = error as? GitError { return e.description }
    return error.localizedDescription
}

public enum Paths {
    public static var home: String {
        if let h = ProcessInfo.processInfo.environment["HOME"], !h.isEmpty {
            return h
        }
        return NSHomeDirectory()
    }

    static func expand(_ p: String) -> String {
        if p == "~" { return home }
        if p.hasPrefix("~/") { return home + String(p.dropFirst(1)) }
        return p
    }

    static func clean(_ p: String) -> String {
        var parts: [Substring] = []
        for c in p.split(separator: "/", omittingEmptySubsequences: true) {
            if c == "." { continue }
            if c == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(c)
        }
        return "/" + parts.joined(separator: "/")
    }

    public static func absolute(_ p: String) -> String {
        var x = expand(p.trimmingCharacters(in: .whitespaces))
        if !x.hasPrefix("/") {
            x = FileManager.default.currentDirectoryPath + "/" + x
        }
        return clean(x)
    }

    public static func real(_ p: String) -> String {
        guard let r = realpath(p, nil) else { return p }
        defer { free(r) }
        return String(cString: r)
    }

    public static func join(_ parts: String...) -> String {
        clean(parts.joined(separator: "/"))
    }

    public static func exists(_ p: String) -> Bool {
        FileManager.default.fileExists(atPath: p)
    }

    public static func isDirectory(_ p: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &dir) && dir.boolValue
    }

    public static func abbreviate(_ p: String) -> String {
        let h = home
        if p == h { return "~" }
        if p.hasPrefix(h + "/") { return "~" + p.dropFirst(h.count) }
        return p
    }

    public static func name(_ p: String) -> String {
        (p as NSString).lastPathComponent
    }

    public static func parent(_ p: String) -> String {
        (p as NSString).deletingLastPathComponent
    }

    static func relative(_ target: String, within base: String) -> String? {
        if target == base { return "" }
        let b = base.hasSuffix("/") ? base : base + "/"
        guard target.hasPrefix(b) else { return nil }
        return String(target.dropFirst(b.count))
    }
}

enum File {
    static func read(_ path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
    }

    static func write(_ data: Data, to path: String) throws {
        try FileManager.default.createDirectory(atPath: Paths.parent(path), withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    static func write(_ text: String, to path: String) throws {
        try write(Data(text.utf8), to: path)
    }

    static func modificationDate(_ path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let d = attrs[.modificationDate] as? Date else { return nil }
        return Int64(d.timeIntervalSince1970)
    }
}

enum JSON {
    static func encoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

private let accents: [Character: String] = [
    "á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
    "é": "e", "è": "e", "ê": "e", "ë": "e",
    "í": "i", "ì": "i", "î": "i", "ï": "i",
    "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
    "ú": "u", "ù": "u", "û": "u", "ü": "u",
    "ç": "c", "ñ": "n",
]

public func slugify(_ s: String) -> String {
    var out = ""
    var lastDash = true
    for ch in s.lowercased() {
        if let swap = accents[ch] {
            out += swap
            lastDash = false
        } else if ch.isASCII && (ch.isLetter || ch.isNumber) {
            out.append(ch)
            lastDash = false
        } else if !lastDash {
            out.append("-")
            lastDash = true
        }
    }
    while out.hasSuffix("-") { out.removeLast() }
    if out.count > 48 {
        out = String(out.prefix(48))
        while out.hasSuffix("-") { out.removeLast() }
    }
    return out
}

public func relativeTime(_ unix: Int64?, now: Date = Date()) -> String {
    guard let unix, unix > 0 else { return "" }
    let d = now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(unix)))
    switch d {
    case ..<60: return "agora"
    case ..<3600: return "há \(Int(d / 60)) min"
    case ..<86400: return "há \(Int(d / 3600)) h"
    case ..<172_800: return "ontem"
    default: return "há \(Int(d / 86400)) dias"
    }
}

public func plural(_ n: Int, _ one: String, _ many: String) -> String {
    n == 1 ? one : many
}

func truncate(_ s: String, _ n: Int) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count > n else { return t }
    return String(t.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
}

func firstLine(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if let i = t.firstIndex(of: "\n") {
        return String(t[..<i]).trimmingCharacters(in: .whitespaces)
    }
    return t
}

func nowUnix() -> Int64 {
    Int64(Date().timeIntervalSince1970)
}

enum Timestamp {
    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }

    static func string(_ d: Date = Date()) -> String {
        formatter().string(from: d)
    }

    static func unix(_ s: String) -> Int64? {
        guard let d = formatter().date(from: s) else { return nil }
        return Int64(d.timeIntervalSince1970)
    }
}

func matchGroups(_ re: NSRegularExpression, _ s: String) -> [String]? {
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    guard let m = re.firstMatch(in: s, options: [], range: range) else { return nil }
    var out: [String] = []
    for i in 0..<m.numberOfRanges {
        if let r = Range(m.range(at: i), in: s) {
            out.append(String(s[r]))
        } else {
            out.append("")
        }
    }
    return out
}

func regex(_ pattern: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: [])
}
