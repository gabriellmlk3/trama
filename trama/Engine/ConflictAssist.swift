import Foundation

public struct ConflictHint: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case identical, spacing, oursOnly, theirsOnly, bothAdded
    }

    public var kind: Kind
    public var resolution: ConflictResolution

    public var reason: String {
        switch kind {
        case .identical: return "os dois lados ficaram iguais"
        case .spacing: return "os lados só diferem em espaços"
        case .oursOnly: return "só a sua versão mudou em relação à base"
        case .theirsOnly: return "só a versão que chegou mudou em relação à base"
        case .bothAdded: return "os dois lados acrescentaram linhas"
        }
    }

    public var action: String {
        switch resolution {
        case .ours: return "usar a sua"
        case .theirs: return "usar a que chegou"
        case .both, .bothReversed: return "manter as duas"
        case .custom: return "aplicar"
        }
    }
}

extension ConflictHunk {
    static func stripped(_ lines: [String]) -> [String] {
        lines.map { $0.filter { !$0.isWhitespace } }.filter { !$0.isEmpty }
    }

    public var differsOnlyInSpacing: Bool {
        ours != theirs && Self.stripped(ours) == Self.stripped(theirs)
    }

    public var hint: ConflictHint? {
        if ours == theirs { return ConflictHint(kind: .identical, resolution: .ours) }
        if differsOnlyInSpacing { return ConflictHint(kind: .spacing, resolution: .ours) }
        guard let base else { return nil }
        if base == ours { return ConflictHint(kind: .theirsOnly, resolution: .theirs) }
        if base == theirs { return ConflictHint(kind: .oursOnly, resolution: .ours) }
        if base.isEmpty, !ours.isEmpty, !theirs.isEmpty { return ConflictHint(kind: .bothAdded, resolution: .both) }
        return nil
    }
}

public struct InlineChanges: Equatable, Sendable {
    public var ours: [Int: Range<Int>] = [:]
    public var theirs: [Int: Range<Int>] = [:]
    public var spacingOurs: Set<Int> = []
    public var spacingTheirs: Set<Int> = []

    public init() {}
}

public enum InlineDiff {
    public static func changes(ours: [String], theirs: [String]) -> InlineChanges {
        var out = InlineChanges()
        guard !ours.isEmpty, !theirs.isEmpty else { return out }
        let matches = lcsMatches(ours, theirs)
        var i = 0
        var j = 0
        var gapsOurs: [Int] = []
        var gapsTheirs: [Int] = []

        func pairGap() {
            for (a, b) in zip(gapsOurs, gapsTheirs) {
                let x = Array(ours[a])
                let y = Array(theirs[b])
                var prefix = 0
                while prefix < x.count, prefix < y.count, x[prefix] == y[prefix] { prefix += 1 }
                var suffix = 0
                while suffix < x.count - prefix, suffix < y.count - prefix, x[x.count - 1 - suffix] == y[y.count - 1 - suffix] { suffix += 1 }
                if prefix + suffix > 0 {
                    out.ours[a] = prefix..<(x.count - suffix)
                    out.theirs[b] = prefix..<(y.count - suffix)
                }
                if x != y, x.filter({ !$0.isWhitespace }) == y.filter({ !$0.isWhitespace }) {
                    out.spacingOurs.insert(a)
                    out.spacingTheirs.insert(b)
                }
            }
            gapsOurs = []
            gapsTheirs = []
        }

        for (a, b) in matches {
            while i < a { gapsOurs.append(i); i += 1 }
            while j < b { gapsTheirs.append(j); j += 1 }
            pairGap()
            i = a + 1
            j = b + 1
        }
        while i < ours.count { gapsOurs.append(i); i += 1 }
        while j < theirs.count { gapsTheirs.append(j); j += 1 }
        pairGap()
        return out
    }

    private static func lcsMatches(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard a.count * b.count <= 90_000 else {
            return (0..<min(a.count, b.count)).filter { a[$0] == b[$0] }.map { ($0, $0) }
        }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var out: [(Int, Int)] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                out.append((i, j))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return out
    }
}

extension ConflictDocument {
    public func summary(_ resolutions: [Int: ConflictResolution]) -> String {
        var ours = 0, theirs = 0, both = 0, edited = 0
        for h in hunks {
            switch resolutions[h.id] {
            case .ours: ours += 1
            case .theirs: theirs += 1
            case .both, .bothReversed: both += 1
            case .custom: edited += 1
            case nil: break
            }
        }
        var parts: [String] = []
        if ours > 0 { parts.append("\(ours) da sua versão") }
        if theirs > 0 { parts.append("\(theirs) da que chegou") }
        if both > 0 { parts.append("\(both) com as duas") }
        if edited > 0 { parts.append("\(edited) \(plural(edited, "editado", "editados"))") }
        return parts.joined(separator: " · ")
    }

    public func warnings(_ resolutions: [Int: ConflictResolution]) -> [String] {
        guard let content = try? render(resolutions) else { return [] }
        var out: [String] = []
        let markers = content.components(separatedBy: "\n").filter { $0.hasPrefix("<<<<<<< ") || $0.hasPrefix(">>>>>>> ") || $0 == "<<<<<<<" || $0 == ">>>>>>>" }
        if !markers.isEmpty {
            out.append("sobraram \(markers.count) \(plural(markers.count, "marcador de conflito", "marcadores de conflito")) no texto (<<<<<<< ou >>>>>>>)")
        }
        guard Self.balancedLanguage(path) else { return out }
        let allOurs = Dictionary(uniqueKeysWithValues: hunks.map { ($0.id, ConflictResolution.ours) })
        let allTheirs = Dictionary(uniqueKeysWithValues: hunks.map { ($0.id, ConflictResolution.theirs) })
        guard let a = try? render(allOurs), let b = try? render(allTheirs),
              Self.bracketBalance(a).allSatisfy({ $0 == 0 }), Self.bracketBalance(b).allSatisfy({ $0 == 0 }) else { return out }
        let names = ["parênteses ( )", "colchetes [ ]", "chaves { }"]
        for (i, delta) in Self.bracketBalance(content).enumerated() where delta != 0 {
            out.append("\(names[i]) ficaram desbalanceados (\(delta > 0 ? "\(delta) abrindo a mais" : "\(-delta) fechando a mais")) · confira o resultado")
        }
        return out
    }

    static func balancedLanguage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["swift", "js", "jsx", "ts", "tsx", "kt", "kts", "java", "c", "h", "m", "mm", "cpp", "hpp", "cs", "go", "rs", "json", "css", "scss", "php", "dart"].contains(ext)
    }

    static func bracketBalance(_ text: String) -> [Int] {
        var counts = [0, 0, 0]
        for ch in text {
            switch ch {
            case "(": counts[0] += 1
            case ")": counts[0] -= 1
            case "[": counts[1] += 1
            case "]": counts[1] -= 1
            case "{": counts[2] += 1
            case "}": counts[2] -= 1
            default: break
            }
        }
        return counts
    }

    public func surroundings(of hunkID: Int, lines count: Int = 6) -> (before: [String], after: [String]) {
        guard let index = segments.firstIndex(where: { $0.id == hunkID }) else { return ([], []) }
        var before: [String] = []
        var after: [String] = []
        if index > 0, case .context(_, let l) = segments[index - 1] { before = Array(l.suffix(count)) }
        if index + 1 < segments.count, case .context(_, let l) = segments[index + 1] { after = Array(l.prefix(count)) }
        return (before, after)
    }

    public var fingerprint: String {
        var hash: UInt64 = 5381
        for h in hunks {
            for line in h.ours + ["\u{1}"] + h.theirs + ["\u{2}"] {
                for byte in line.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
                hash = (hash &* 33) &+ 10
            }
        }
        return String(hash, radix: 16)
    }
}

public struct ConflictDraft: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var hunk: Int
        public var kind: String
        public var lines: [String]?
    }

    public var file: String
    public var fingerprint: String
    public var items: [Item]
    public var savedAt: Int64

    public init(document: ConflictDocument, resolutions: [Int: ConflictResolution]) {
        file = document.path
        fingerprint = document.fingerprint
        savedAt = Int64(Date().timeIntervalSince1970)
        items = resolutions.sorted { $0.key < $1.key }.map { id, r in
            switch r {
            case .ours: return Item(hunk: id, kind: "ours", lines: nil)
            case .theirs: return Item(hunk: id, kind: "theirs", lines: nil)
            case .both: return Item(hunk: id, kind: "both", lines: nil)
            case .bothReversed: return Item(hunk: id, kind: "bothReversed", lines: nil)
            case .custom(let l): return Item(hunk: id, kind: "custom", lines: l)
            }
        }
    }

    public func resolutions(for document: ConflictDocument) -> [Int: ConflictResolution] {
        guard fingerprint == document.fingerprint else { return [:] }
        let ids = Set(document.hunks.map(\.id))
        var out: [Int: ConflictResolution] = [:]
        for item in items where ids.contains(item.hunk) {
            switch item.kind {
            case "ours": out[item.hunk] = .ours
            case "theirs": out[item.hunk] = .theirs
            case "both": out[item.hunk] = .both
            case "bothReversed": out[item.hunk] = .bothReversed
            case "custom": out[item.hunk] = .custom(item.lines ?? [])
            default: break
            }
        }
        return out
    }
}

public struct ConflictOrigin: Hashable, Sendable {
    public var hash: String
    public var author: String
    public var subject: String

    public var label: String { "\(hash) · \(author) · \(subject)" }
}

public struct ConflictOrigins: Hashable, Sendable {
    public var ours: ConflictOrigin?
    public var theirs: ConflictOrigin?
}

extension ConflictFile {
    public var generatedHint: String? {
        let name = (path as NSString).lastPathComponent
        let commands: [String: String] = [
            "Package.resolved": "swift package resolve",
            "package-lock.json": "npm install",
            "yarn.lock": "yarn install",
            "pnpm-lock.yaml": "pnpm install",
            "Podfile.lock": "pod install",
            "Cargo.lock": "cargo build",
            "Gemfile.lock": "bundle install",
            "poetry.lock": "poetry lock",
            "composer.lock": "composer update --lock",
            "go.sum": "go mod tidy",
        ]
        if let command = commands[name] {
            return "arquivo gerado · aceite um dos lados e rode `\(command)` para regenerá-lo"
        }
        if name.hasSuffix(".pbxproj") {
            return "projeto do Xcode · em geral vale manter as duas versões dos blocos (Ambas) e abrir no Xcode para conferir"
        }
        return nil
    }
}

extension Workspace {
    private func draftPath(_ wt: String, _ file: String) -> String {
        var hash: UInt64 = 5381
        for byte in (Paths.real(wt) + "|" + file).utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Paths.join(stateDir, "conflict-drafts", String(hash, radix: 16) + ".json")
    }

    public func loadConflictDraft(worktree: String, document: ConflictDocument) -> [Int: ConflictResolution] {
        guard let text = try? File.read(draftPath(worktree, document.path)),
              let draft = try? JSONDecoder().decode(ConflictDraft.self, from: Data(text.utf8)) else { return [:] }
        return draft.resolutions(for: document)
    }

    public func saveConflictDraft(worktree: String, document: ConflictDocument, resolutions: [Int: ConflictResolution]) {
        let path = draftPath(worktree, document.path)
        guard !resolutions.isEmpty else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        guard let data = try? JSON.encoder(pretty: false).encode(ConflictDraft(document: document, resolutions: resolutions)) else { return }
        try? File.write(data, to: path)
    }

    func clearConflictDraft(worktree: String, file: String) {
        try? FileManager.default.removeItem(atPath: draftPath(worktree, file))
    }

    func fillConflictBase(_ document: ConflictDocument, worktree wt: String, file: String) -> ConflictDocument {
        guard (1...3).allSatisfy({ Git.hasStage(wt, file, $0) }) else { return document }
        let dir = NSTemporaryDirectory() + "trama-merge-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var paths: [String] = []
        for stage in [2, 1, 3] {
            let r = Git.execute(wt, ["show", ":\(stage):\(file)"])
            guard r.code == 0 else { return document }
            let path = dir + "/s\(stage)"
            guard (try? File.write(r.output + "\n", to: path)) != nil else { return document }
            paths.append(path)
        }
        let merged = Git.execute(wt, ["merge-file", "-p", "--diff3", "-L", "ours", "-L", "base", "-L", "theirs"] + paths)
        guard merged.code >= 0, merged.code < 128, let regenerated = try? ConflictParser.parse(path: file, text: merged.output + "\n") else { return document }
        var pool = regenerated.hunks[...]
        var bases: [Int: [String]] = [:]
        for h in document.hunks where h.base == nil {
            guard let index = pool.firstIndex(where: { $0.ours == h.ours && $0.theirs == h.theirs }) else { continue }
            bases[h.id] = pool[index].base
            pool = pool[(index + 1)...]
        }
        guard !bases.isEmpty else { return document }
        var out = document
        out.segments = document.segments.map { segment in
            guard case .hunk(var h) = segment, let base = bases[h.id] else { return segment }
            h.base = base
            return .hunk(h)
        }
        return out
    }

    public func conflictOrigins(repo key: String, worktree: String, file: String, document: ConflictDocument) throws -> [Int: ConflictOrigins] {
        let wt = try conflictWorktree(key, worktree).path
        guard Git.isMerging(wt) else { return [:] }
        func find(_ range: String, _ lines: [String]) -> ConflictOrigin? {
            let probe = lines.first { $0.trimmingCharacters(in: .whitespaces).count >= 4 }
            var attempts: [[String]] = []
            if let probe { attempts.append(["-S" + probe.trimmingCharacters(in: .whitespaces)]) }
            attempts.append([])
            for extra in attempts {
                let args = ["log", "-n", "1"] + extra + ["--format=%h%x1f%an%x1f%s", range, "--", file]
                guard let out = try? Git.run(wt, args), !out.isEmpty else { continue }
                let p = out.components(separatedBy: "\u{1f}")
                if p.count == 3 { return ConflictOrigin(hash: p[0], author: p[1], subject: p[2]) }
            }
            return nil
        }
        var out: [Int: ConflictOrigins] = [:]
        for h in document.hunks.prefix(30) {
            let common = Set(h.ours).intersection(h.theirs)
            out[h.id] = ConflictOrigins(
                ours: find("MERGE_HEAD..HEAD", h.ours.filter { !common.contains($0) } + h.ours),
                theirs: find("HEAD..MERGE_HEAD", h.theirs.filter { !common.contains($0) } + h.theirs)
            )
        }
        return out
    }

    public func suggestConflictResolution(repo key: String, worktree: String, file: String, document: ConflictDocument, hunk id: Int) throws -> [String] {
        let wt = try conflictWorktree(key, worktree).path
        guard let hunk = document.hunks.first(where: { $0.id == id }) else { throw TramaError("não achei esse trecho em conflito") }
        let origins = (try? conflictOrigins(repo: key, worktree: worktree, file: file, document: ConflictDocument(path: document.path, segments: [.hunk(hunk)], oursLabel: "", theirsLabel: "", endsWithNewline: true)))?[id]
        let around = document.surroundings(of: id)
        func block(_ title: String, _ lines: [String]?) -> String {
            guard let lines else { return "" }
            return "\n\(title):\n" + (lines.isEmpty ? "(vazio)" : lines.joined(separator: "\n")) + "\n"
        }
        var notes: [String] = []
        if let o = origins?.ours { notes.append("Sua versão vem de: \(o.subject)") }
        if let t = origins?.theirs { notes.append("A versão que chegou vem de: \(t.subject)") }
        let prompt = """
        Resolva este conflito de merge no arquivo \(file). Responda só com as linhas finais que devem ficar no lugar do trecho em conflito, dentro de um único bloco de código (```), preservando a indentação e sem explicação. Se a melhor resolução for manter as duas versões, combine-as de forma coerente.
        \(notes.isEmpty ? "" : "\n" + notes.joined(separator: "\n"))
        \(block("Linhas antes do trecho", around.before.isEmpty ? nil : around.before))\(block("Base (ancestral comum)", hunk.base))\(block("Sua versão", hunk.ours))\(block("Versão que chegou", hunk.theirs))\(block("Linhas depois do trecho", around.after.isEmpty ? nil : around.after))
        """
        let raw = try CLITool.claude.run(wt, ["-p", prompt, "--model", "sonnet"])
        let lines = Self.fencedLines(raw)
        guard !lines.isEmpty else { throw TramaError("o Claude não devolveu uma resolução") }
        return lines
    }

    static func fencedLines(_ raw: String) -> [String] {
        var lines = raw.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.hasPrefix("```") }) {
            let rest = lines[(start + 1)...]
            let end = rest.firstIndex(where: { $0.hasPrefix("```") }) ?? lines.endIndex
            lines = Array(lines[(start + 1)..<end])
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        return lines
    }
}
