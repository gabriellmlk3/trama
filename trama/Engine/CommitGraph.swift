import Foundation

public struct RefLabel: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case head, local, remote, tag
    }

    public var name: String
    public var kind: Kind
}

public struct GraphCommit: Hashable, Identifiable, Sendable {
    public var hash: String
    public var short: String
    public var parents: [String]
    public var author: String
    public var timestamp: Int64
    public var subject: String
    public var refs: [RefLabel] = []

    public var id: String { hash }
    public var isMerge: Bool { parents.count > 1 }
    public var isHead: Bool { refs.contains { $0.kind == .head } }
}

public struct GraphSegment: Hashable, Sendable {
    public var from: Int
    public var to: Int
    public var color: Int
}

public struct GraphRow: Hashable, Sendable {
    public var lane: Int
    public var color: Int
    public var top: [GraphSegment]
    public var bottom: [GraphSegment]
    public var width: Int
}

enum CommitGraph {
    static func layout(_ commits: [GraphCommit]) -> [GraphRow] {
        var lanes: [String?] = []
        var colors: [Int] = []
        var nextColor = 0
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        func openLane() -> Int {
            let slot = lanes.firstIndex(where: { $0 == nil }) ?? lanes.count
            if slot == lanes.count {
                lanes.append(nil)
                colors.append(0)
            }
            colors[slot] = nextColor
            nextColor += 1
            return slot
        }

        for commit in commits {
            let incoming = lanes.indices.filter { lanes[$0] == commit.hash }
            let lane = incoming.first ?? openLane()
            let color = colors[lane]
            let top = lanes.indices.compactMap { j -> GraphSegment? in
                guard let expected = lanes[j] else { return nil }
                return GraphSegment(from: j, to: expected == commit.hash ? lane : j, color: colors[j])
            }
            for j in incoming { lanes[j] = nil }
            lanes[lane] = commit.parents.first

            var opened: Set<Int> = []
            var merges: [Int] = []
            for parent in commit.parents.dropFirst() {
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    merges.append(existing)
                } else {
                    let slot = openLane()
                    lanes[slot] = parent
                    opened.insert(slot)
                    merges.append(slot)
                }
            }

            var bottom = lanes.indices.compactMap { j -> GraphSegment? in
                guard lanes[j] != nil, !opened.contains(j) else { return nil }
                return GraphSegment(from: j, to: j, color: colors[j])
            }
            bottom += merges.map { GraphSegment(from: lane, to: $0, color: colors[$0]) }

            while let last = lanes.last, last == nil {
                lanes.removeLast()
                colors.removeLast()
            }
            let reach = (top + bottom).flatMap { [$0.from, $0.to] }.max() ?? 0
            rows.append(GraphRow(lane: lane, color: color, top: top, bottom: bottom, width: max(lane, reach) + 1))
        }
        return rows
    }
}

extension Git {
    static let recordSeparator = "\u{1e}"
    static let fieldSeparator = "\u{1f}"

    static func history(_ dir: String, limit: Int, hasHead: Bool? = nil) -> [GraphCommit] {
        let format = ["%H", "%h", "%P", "%an", "%ct", "%D", "%s"].joined(separator: "%x1f") + "%x1e"
        var args = ["log", "--branches", "--remotes", "--tags", "--topo-order", "--decorate=full", "-n", String(limit), "--format=" + format]
        if hasHead ?? refExists(dir, "HEAD") { args.append("HEAD") }
        let r = execute(dir, args)
        guard r.code == 0 else { return [] }
        return parseHistory(r.output)
    }

    static func parseHistory(_ raw: String) -> [GraphCommit] {
        raw.components(separatedBy: recordSeparator).compactMap { record in
            let p = record.trimmingCharacters(in: .newlines).components(separatedBy: fieldSeparator)
            guard p.count >= 7 else { return nil }
            return GraphCommit(
                hash: p[0],
                short: p[1],
                parents: p[2].split(separator: " ").map(String.init),
                author: p[3],
                timestamp: Int64(p[4]) ?? 0,
                subject: p[6...].joined(separator: fieldSeparator),
                refs: parseDecorations(p[5])
            )
        }
    }

    static func parseDecorations(_ raw: String) -> [RefLabel] {
        raw.components(separatedBy: ", ").compactMap { part in
            let item = part.trimmingCharacters(in: .whitespaces)
            if item == "HEAD" { return RefLabel(name: "HEAD", kind: .head) }
            if item.hasPrefix("HEAD -> ") { return RefLabel(name: shortRefName(String(item.dropFirst(8))), kind: .head) }
            if item.hasPrefix("tag: ") { return RefLabel(name: shortRefName(String(item.dropFirst(5))), kind: .tag) }
            if item.hasPrefix("refs/heads/") { return RefLabel(name: shortRefName(item), kind: .local) }
            if item.hasPrefix("refs/remotes/"), !item.hasSuffix("/HEAD") { return RefLabel(name: shortRefName(item), kind: .remote) }
            return nil
        }
    }

    static func shortRefName(_ ref: String) -> String {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return ref
    }
}
