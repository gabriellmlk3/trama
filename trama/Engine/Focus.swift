import Foundation

private struct FocusFile: Codable {
    static let currentVersion = 1

    var version = FocusFile.currentVersion
    var trama: String
    var since: Int64

    enum CodingKeys: String, CodingKey {
        case version = "versao", trama, since = "desde"
    }

    init(trama: String, since: Int64) {
        self.trama = trama
        self.since = since
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? FocusFile.currentVersion
        trama = try c.decode(String.self, forKey: .trama)
        since = try c.decodeIfPresent(Int64.self, forKey: .since) ?? 0
    }
}

extension Workspace {
    var focusPath: String { Paths.join(stateDir, "foco.json") }

    public func focusedSlug() -> String? {
        guard let text = try? File.read(focusPath),
              let file = try? JSONDecoder().decode(FocusFile.self, from: Data(text.utf8)),
              file.version <= FocusFile.currentVersion else { return nil }
        return file.trama
    }

    func focusedTrama() -> Trama? {
        guard let slug = focusedSlug(), let t = try? tramas().first(where: { $0.slug == slug }), !t.isArchived else { return nil }
        return t
    }

    @discardableResult
    public func focus(_ slug: String) throws -> (trama: Trama, warnings: [Warning]) {
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        let previous = focusedTrama()
        try withLock {
            let data = try JSON.encoder().encode(FocusFile(trama: t.slug, since: nowUnix()))
            try File.write(data + Data("\n".utf8), to: focusPath)
        }
        var warnings = applyFocusPathRules(t)
        var batches: [AutomationBatch] = []
        if let previous, previous.slug != t.slug {
            batches.append(AutomationBatch(trama: previous, event: .unfocus))
        }
        batches.append(AutomationBatch(trama: t, event: .focus))
        warnings += runAutomations(batches, logOwner: t.slug)
        return (t, warnings)
    }

    @discardableResult
    public func clearFocus() throws -> [Warning] {
        let previous = focusedTrama()
        try withLock {
            if Paths.exists(focusPath) { try FileManager.default.removeItem(atPath: focusPath) }
        }
        var warnings = applyFocusPathRules(nil)
        if let previous {
            warnings += fire(.unfocus, previous)
        }
        return warnings
    }

    func refocusIfNeeded(_ t: Trama) -> [Warning] {
        guard focusedSlug() == t.slug else { return [] }
        return applyFocusPathRules(t)
    }
}
