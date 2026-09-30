import Foundation

public enum CapsuleSection {
    public static let goal = "Objetivo"
    public static let decisions = "Decisões"
    public static let handoffs = "Handoffs"
    public static let pending = "Pendências"
    public static let journal = "Diário"
}

private let emptyMarker = "_("

public struct CapsuleItem: Codable, Hashable, Identifiable, Sendable {
    public var index: Int
    public var text: String
    public var author: String?
    public var timestamp: Int64?
    public var done: Bool
    public var from: String?
    public var to: String?
    public var raw: String

    public var id: Int { index }
}

public struct TramaCapsule: Codable, Hashable, Sendable {
    public var trama: String
    public var path: String
    public var exists: Bool
    public var title = ""
    public var goal = ""
    public var decisions: [CapsuleItem] = []
    public var handoffs: [CapsuleItem] = []
    public var pending: [CapsuleItem] = []
    public var journal: [CapsuleItem] = []
    public var updatedAt: Int64?
    public var markdown = ""

    public var openPending: [CapsuleItem] { pending.filter { !$0.done } }
    public var openHandoffs: [CapsuleItem] { handoffs.filter { !$0.done } }
}

private let reDated = regex(#"^- (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) · (.+?): (.*)$"#)
private let reJournal = regex(#"^- (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) · (.*)$"#)
private let reHandoff = regex(#"^- \[( |x|X)\] (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) · (.+?) → (.+?) · (.+?): (.*)$"#)
private let reCheckbox = regex(#"^- \[( |x|X)\] (.*)$"#)

enum CapsuleDoc {
    static func new(_ t: Trama, goal: String) -> String {
        var b = "# \(t.title)\n\n"
        b += "- **Branch:** `\(t.branch)`\n"
        b += "- **Repositórios:** \(t.repos.joined(separator: ", "))\n"
        if let task = t.task, !task.isEmpty {
            b += "- **Tarefa:** \(task)\n"
        }
        b += "\n## \(CapsuleSection.goal)\n\n"
        let o = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if o.isEmpty {
            b += "_(descreva o objetivo desta trama em uma ou duas frases · `trama objetivo \"...\"`)_\n"
        } else {
            b += o + "\n"
        }
        for s in [CapsuleSection.decisions, CapsuleSection.handoffs, CapsuleSection.pending, CapsuleSection.journal] {
            b += "\n## \(s)\n\n"
        }
        return b
    }

    static func split(_ doc: String) -> [String] {
        var d = doc
        while d.hasSuffix("\n") { d.removeLast() }
        return d.components(separatedBy: "\n")
    }

    static func join(_ lines: [String]) -> String {
        var t = lines.joined(separator: "\n")
        while t.hasSuffix("\n") { t.removeLast() }
        return t + "\n"
    }

    static func section(_ lines: [String], _ name: String) -> (start: Int, end: Int)? {
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## " + name }) else {
            return nil
        }
        var end = lines.count
        var i = start + 1
        while i < lines.count {
            if lines[i].hasPrefix("## ") {
                end = i
                break
            }
            i += 1
        }
        return (start, end)
    }

    static func cleanBody<S: Sequence>(_ body: S) -> [String] where S.Element == String {
        var out = body.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(emptyMarker) }
        while let p = out.first, p.trimmingCharacters(in: .whitespaces).isEmpty { out.removeFirst() }
        while let u = out.last, u.trimmingCharacters(in: .whitespaces).isEmpty { out.removeLast() }
        return out
    }

    static func assemble(_ lines: [String], _ start: Int, _ end: Int, _ body: [String]) -> [String] {
        var out = Array(lines[...start])
        out.append("")
        if !body.isEmpty {
            out += body
            out.append("")
        }
        out += lines[end...]
        return out
    }

    static func insert(_ doc: String, section name: String, line: String) -> String {
        var lines = split(doc)
        guard let s = section(lines, name) else {
            lines += ["", "## " + name, "", line]
            return join(lines)
        }
        let (start, end) = s
        var body = cleanBody(lines[(start + 1)..<end])
        body.append(line)
        return join(assemble(lines, start, end, body))
    }

    static func set(_ doc: String, section name: String, content: String) -> String {
        var lines = split(doc)
        let newBody = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        guard let s = section(lines, name) else {
            lines += ["", "## " + name, ""]
            lines += newBody
            return join(lines)
        }
        let (start, end) = s
        return join(assemble(lines, start, end, newBody))
    }

    static func items(_ lines: [String], _ name: String) -> [CapsuleItem] {
        guard let s = section(lines, name) else { return [] }
        let (start, end) = s
        var items: [CapsuleItem] = []
        for raw in lines[(start + 1)..<end] {
            var l = raw
            while l.hasSuffix(" ") { l.removeLast() }
            guard l.hasPrefix("- ") else { continue }
            var it = CapsuleItem(index: items.count + 1, text: "", done: false, raw: l)
            if name == CapsuleSection.handoffs, let m = matchGroups(reHandoff, l) {
                it.done = m[1] != " "
                it.timestamp = Timestamp.unix(m[2])
                it.from = m[3]
                it.to = m[4]
                it.author = m[5]
                it.text = m[6]
            } else if let m = matchGroups(reCheckbox, l) {
                it.done = m[1] != " "
                it.text = m[2]
            } else if name == CapsuleSection.journal, let m = matchGroups(reJournal, l) {
                it.timestamp = Timestamp.unix(m[1])
                it.text = m[2]
            } else if let m = matchGroups(reDated, l) {
                it.timestamp = Timestamp.unix(m[1])
                it.author = m[2]
                it.text = m[3]
            } else {
                it.text = String(l.dropFirst(2))
            }
            items.append(it)
        }
        return items
    }

    static func parse(slug: String, path: String, doc: String) -> TramaCapsule {
        let lines = split(doc)
        var c = TramaCapsule(trama: slug, path: path, exists: true)
        if let t = lines.first(where: { $0.hasPrefix("# ") }) {
            c.title = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if let s = section(lines, CapsuleSection.goal) {
            c.goal = cleanBody(lines[(s.start + 1)..<s.end]).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        c.decisions = items(lines, CapsuleSection.decisions)
        c.handoffs = items(lines, CapsuleSection.handoffs)
        c.pending = items(lines, CapsuleSection.pending)
        c.journal = items(lines, CapsuleSection.journal)
        c.markdown = doc
        return c
    }

    static func mark(_ doc: String, section name: String, _ filter: (CapsuleItem) -> Bool) -> (String, Int) {
        var lines = split(doc)
        guard let s = section(lines, name) else { return (doc, 0) }
        let (start, end) = s
        var byRaw: [String: CapsuleItem] = [:]
        for it in items(lines, name) {
            byRaw[it.raw] = it
        }
        var n = 0
        for i in (start + 1)..<end {
            var l = lines[i]
            while l.hasSuffix(" ") { l.removeLast() }
            guard let it = byRaw[l], !it.done, l.hasPrefix("- [ ] "), filter(it) else { continue }
            lines[i] = "- [x] " + l.dropFirst(6)
            n += 1
        }
        return (join(lines), n)
    }
}

extension Workspace {
    public func capsulePath(_ slug: String) -> String {
        guard let context = config.context else {
            return Paths.join(tramaPath(slug), "CAPSULA.md")
        }
        return Paths.join(context, config.capsuleFolder, slug + ".md")
    }

    public func readCapsule(_ slug: String) throws -> TramaCapsule {
        let path = capsulePath(slug)
        guard let doc = try File.read(path) else {
            return TramaCapsule(trama: slug, path: path, exists: false)
        }
        var c = CapsuleDoc.parse(slug: slug, path: path, doc: doc)
        c.updatedAt = File.modificationDate(path)
        return c
    }

    func editCapsule(_ slug: String, _ transform: (String) throws -> String) throws {
        try withLock {
            let path = capsulePath(slug)
            var doc = try File.read(path)
            if doc == nil {
                doc = CapsuleDoc.new(try trama(slug), goal: "")
            }
            let newDoc = try transform(doc ?? "")
            try File.write(newDoc, to: path)
        }
    }

    public func addDecision(_ slug: String, author: String, _ text: String) throws {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw TramaError("a decisão está vazia") }
        let line = "- \(Timestamp.string()) · \(author): \(t)"
        try editCapsule(slug) { CapsuleDoc.insert($0, section: CapsuleSection.decisions, line: line) }
    }

    public func addHandoff(_ slug: String, from: String, to: String, author: String, _ text: String) throws {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw TramaError("o handoff está vazio") }
        let o = from.isEmpty ? "trama" : from
        let line = "- [ ] \(Timestamp.string()) · \(o) → \(to) · \(author): \(t)"
        try editCapsule(slug) { CapsuleDoc.insert($0, section: CapsuleSection.handoffs, line: line) }
    }

    public func addPending(_ slug: String, _ text: String) throws {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw TramaError("a pendência está vazia") }
        try editCapsule(slug) { CapsuleDoc.insert($0, section: CapsuleSection.pending, line: "- [ ] " + t) }
    }

    public func addJournal(_ slug: String, _ text: String) throws {
        let line = "- \(Timestamp.string()) · \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        try editCapsule(slug) { CapsuleDoc.insert($0, section: CapsuleSection.journal, line: line) }
    }

    public func setGoal(_ slug: String, _ text: String) throws {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw TramaError("o objetivo está vazio") }
        try editCapsule(slug) { CapsuleDoc.set($0, section: CapsuleSection.goal, content: t) }
    }

    public func completePending(_ slug: String, _ n: Int) throws {
        try editCapsule(slug) { doc in
            let (newDoc, count) = CapsuleDoc.mark(doc, section: CapsuleSection.pending) { $0.index == n }
            if count == 0 {
                throw TramaError("não há pendência aberta com o número \(n)")
            }
            return newDoc
        }
    }

    @discardableResult
    public func confirmHandoffs(_ slug: String, to: String?, number n: Int = 0) throws -> Int {
        var total = 0
        try editCapsule(slug) { doc in
            let (newDoc, count) = CapsuleDoc.mark(doc, section: CapsuleSection.handoffs) { it in
                if n > 0 { return it.index == n }
                guard let to, !to.isEmpty else { return false }
                return it.to == to
            }
            total = count
            return newDoc
        }
        return total
    }

    @discardableResult
    public func syncCapsule(_ slug: String) throws -> Bool {
        guard let context = config.context else {
            throw TramaError("nenhum repositório de contexto configurado (`trama init --contexto <pasta>`)")
        }
        let path = capsulePath(slug)
        guard let rel = Paths.relative(path, within: context) else {
            throw TramaError("a cápsula está fora do repositório de contexto")
        }
        let out = try Git.run(context, "status", "--porcelain", "--", rel)
        if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        try Git.run(context, "add", "--", rel)
        try Git.run(context, "commit", "--quiet", "-m", "trama(\(slug)): atualiza cápsula", "--", rel)
        return true
    }
}
