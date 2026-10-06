import Foundation
import SwiftUI

enum GraphMetrics {
    static let row: CGFloat = 30
    static let lane: CGFloat = 14
    static let inset: CGFloat = 6
    static let maxLanes = 10

    static func width(lanes: Int) -> CGFloat {
        inset * 2 + CGFloat(min(max(lanes, 1), maxLanes)) * lane
    }

    static func x(_ lane: Int) -> CGFloat {
        inset + CGFloat(lane) * GraphMetrics.lane + GraphMetrics.lane / 2
    }
}

struct CommitHistoryPane: View {
    let repo: String
    let state: RepoBrowserState
    @Binding var selected: String?
    let onBranch: (String) -> Void
    let onShowChanges: () -> Void
    let onLoadMore: () -> Void

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 860
            if let hash = selected {
                if wide {
                    HStack(alignment: .top, spacing: 14) {
                        list(compact: true)
                        inspector(hash)
                            .frame(width: 400)
                    }
                } else {
                    VStack(spacing: 14) {
                        list(compact: true)
                            .frame(height: max(220, geo.size.height * 0.42))
                        inspector(hash)
                    }
                }
            } else {
                list(compact: geo.size.width < 980)
            }
        }
    }

    func list(compact: Bool) -> some View {
        CommitGraphList(state: state, selected: $selected, compact: compact, onBranch: onBranch, onShowChanges: onShowChanges, onLoadMore: onLoadMore)
    }

    func inspector(_ hash: String) -> some View {
        CommitInspector(repo: repo, hash: hash, checkout: state.checkout, onSelect: { selected = $0 }, onClose: { selected = nil }, onBranch: onBranch)
            .id(hash)
    }
}

struct CommitGraphList: View {
    let state: RepoBrowserState
    @Binding var selected: String?
    let compact: Bool
    let onBranch: (String) -> Void
    let onShowChanges: () -> Void
    let onLoadMore: () -> Void

    var graphWidth: CGFloat {
        GraphMetrics.width(lanes: state.graph.map(\.width).max() ?? 1)
    }

    var headLane: Int {
        guard let i = state.commits.firstIndex(where: \.isHead) else { return 0 }
        return state.graph[i].lane
    }

    var body: some View {
        GitCard {
            if state.commits.isEmpty {
                Text("Nenhum commit ainda neste repositório.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.faded)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !state.changes.isEmpty {
                            WorkInProgressRow(count: state.changes.count, lane: min(headLane, GraphMetrics.maxLanes - 1), graphWidth: graphWidth, action: onShowChanges)
                        }
                        ForEach(Array(state.commits.enumerated()), id: \.element.hash) { index, commit in
                            CommitGraphRow(
                                commit: commit,
                                row: state.graph[index],
                                graphWidth: graphWidth,
                                selected: selected == commit.hash,
                                compact: compact,
                                onBranch: onBranch
                            ) {
                                selected = selected == commit.hash ? nil : commit.hash
                            }
                        }
                        if state.truncated {
                            HStack(spacing: 10) {
                                Text("Mostrando os \(state.commits.count) commits mais recentes")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.faded)
                                Button("Carregar mais", action: onLoadMore)
                                    .buttonStyle(GhostButton(compact: true))
                            }
                            .padding(14)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorkInProgressRow: View {
    let count: Int
    let lane: Int
    let graphWidth: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Canvas { context, size in
                    let center = CGPoint(x: GraphMetrics.x(lane), y: size.height / 2)
                    var line = Path()
                    line.move(to: CGPoint(x: center.x, y: center.y + 5))
                    line.addLine(to: CGPoint(x: center.x, y: size.height))
                    context.stroke(line, with: .color(Theme.faded), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    let dot = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
                    context.stroke(dot, with: .color(Theme.faded), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                }
                .frame(width: graphWidth, height: GraphMetrics.row)
                Text("\(count) \(plural(count, "mudança não commitada", "mudanças não commitadas"))")
                    .font(.system(size: 12.5).italic())
                    .foregroundStyle(Theme.text3)
                Spacer(minLength: 8)
                Text("ver")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.emberLight)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.trailing, 12)
            .frame(height: GraphMetrics.row)
            .background(hovering ? Theme.surface : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CommitGraphRow: View {
    let commit: GraphCommit
    let row: GraphRow
    let graphWidth: CGFloat
    let selected: Bool
    let compact: Bool
    let onBranch: (String) -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            GraphCell(row: row, head: commit.isHead, merge: commit.isMerge)
                .frame(width: graphWidth, height: GraphMetrics.row)
            RefChips(refs: commit.refs, color: Theme.lane(row.color), limit: compact ? 1 : 2)
            Text(commit.subject)
                .font(.system(size: 12.5, weight: commit.isHead ? .medium : .regular))
                .foregroundStyle(commit.isMerge ? Theme.text3 : (commit.isHead ? Theme.text : Theme.text2))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if !compact {
                Text(commit.author)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
            Text(relativeTime(commit.timestamp))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
                .lineLimit(1)
                .frame(width: compact ? 72 : 92, alignment: .trailing)
            Text(commit.short)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.faded)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.trailing, 12)
        .frame(height: GraphMetrics.row)
        .background(selected ? Theme.surface2 : (hovering ? Theme.surface : Color.clear))
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Theme.ember).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copiar hash") { Terminal.copy(commit.hash) }
            Button("Copiar mensagem") { Terminal.copy(commit.subject) }
            Divider()
            Button("Nova branch a partir daqui…") { onBranch(commit.hash) }
        }
        .help(commit.subject)
    }
}

struct GraphCell: View {
    let row: GraphRow
    let head: Bool
    let merge: Bool

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            for s in row.top {
                context.stroke(edge(CGPoint(x: GraphMetrics.x(s.from), y: 0), CGPoint(x: GraphMetrics.x(s.to), y: mid)), with: .color(Theme.lane(s.color)), lineWidth: 2)
            }
            for s in row.bottom {
                context.stroke(edge(CGPoint(x: GraphMetrics.x(s.from), y: mid), CGPoint(x: GraphMetrics.x(s.to), y: size.height)), with: .color(Theme.lane(s.color)), lineWidth: 2)
            }
            let color = Theme.lane(row.color)
            let center = CGPoint(x: GraphMetrics.x(row.lane), y: mid)
            if head {
                let halo = Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
                context.fill(halo, with: .color(color.opacity(0.25)))
            }
            let radius: CGFloat = merge ? 4 : 5
            let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(merge ? Theme.loom : color))
            context.stroke(dot, with: .color(color), lineWidth: 2)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    func edge(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        if a.x == b.x {
            p.addLine(to: b)
        } else {
            let middle = (a.y + b.y) / 2
            p.addCurve(to: b, control1: CGPoint(x: a.x, y: middle), control2: CGPoint(x: b.x, y: middle))
        }
        return p
    }
}

struct RefChips: View {
    struct Item: Hashable {
        var name: String
        var local = false
        var remote = false
        var tag = false
        var head = false
    }

    let refs: [RefLabel]
    let color: Color
    var limit = 2

    var items: [Item] {
        let remotes = refs.filter { $0.kind == .remote }.map(\.name)
        var tracked: Set<String> = []
        var list: [Item] = []
        for r in refs where r.kind == .head || r.kind == .local {
            let mirror = remotes.first { $0.split(separator: "/", maxSplits: 1).last.map(String.init) == r.name }
            if let mirror { tracked.insert(mirror) }
            list.append(Item(name: r.name, local: r.name != "HEAD", remote: mirror != nil, head: r.kind == .head))
        }
        list += remotes.filter { !tracked.contains($0) }.map { Item(name: $0, remote: true) }
        list += refs.filter { $0.kind == .tag }.map { Item(name: $0.name, tag: true) }
        return list
    }

    var body: some View {
        let all = items
        if !all.isEmpty {
            HStack(spacing: 4) {
                ForEach(all.prefix(limit), id: \.self) { chip($0) }
                if all.count > limit {
                    Text("+\(all.count - limit)")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.faded)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface2))
                        .help(all.dropFirst(limit).map(\.name).joined(separator: "\n"))
                }
            }
            .fixedSize()
        }
    }

    func chip(_ item: Item) -> some View {
        let tint = item.tag ? Theme.faded : color
        return HStack(spacing: 4) {
            if item.head {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            }
            if item.local {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 8.5))
            }
            if item.remote {
                Image(systemName: "cloud")
                    .font(.system(size: 8.5))
            }
            if item.tag {
                Image(systemName: "tag")
                    .font(.system(size: 8.5))
            }
            Text(Self.shortened(item.name))
                .font(Theme.mono(10.5, weight: item.head ? .semibold : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(item.head ? Theme.text : Theme.text2)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(item.head ? 0.3 : 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.55), lineWidth: 1))
        .help(item.local && item.remote ? "\(item.name) · local e no remoto" : item.name)
        .fixedSize()
    }

    static func shortened(_ name: String, limit: Int = 22) -> String {
        guard name.count > limit else { return name }
        let head = (limit - 1) / 2
        return String(name.prefix(head)) + "…" + String(name.suffix(limit - 1 - head))
    }
}

struct CommitInspector: View {
    @EnvironmentObject var model: AppModel
    let repo: String
    let hash: String
    let checkout: String
    let onSelect: (String) -> Void
    let onClose: () -> Void
    let onBranch: (String) -> Void

    @State private var detail: CommitDetail?
    @State private var error: String?
    @State private var file: String?
    @State private var diff: [DiffLine] = []

    var change: FileChange? { detail?.changes.first { $0.id == file } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                if let detail {
                    if detail.changes.isEmpty {
                        GitCard {
                            Text(detail.parents.count > 1 ? "Merge sem mudanças em relação ao primeiro pai." : "Commit sem mudanças de arquivo.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.faded)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        FileList(changes: detail.changes, selectedFile: $file)
                        DiffPane(change: change, lines: diff, path: checkout)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .task(id: hash) { await loadDetail() }
        .task(id: file) { await loadDiff() }
    }

    var summary: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Text(detail?.subject ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButton(size: 24))
                    .help("Fechar o commit")
                    .accessibilityLabel("Fechar o commit")
                }
                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.waitText)
                }
                if let detail {
                    if !detail.body.isEmpty {
                        Text(detail.body)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.text3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        meta("Autor") {
                            Text(detail.author).foregroundStyle(Theme.text2)
                            Text(detail.email).foregroundStyle(Theme.faded).lineLimit(1).truncationMode(.middle)
                        }
                        meta("Data") {
                            Text(Date(timeIntervalSince1970: TimeInterval(detail.timestamp)).formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(Theme.text2)
                            Text(relativeTime(detail.timestamp)).foregroundStyle(Theme.faded)
                        }
                        meta("Commit") {
                            Text(detail.short).font(Theme.mono(11.5)).foregroundStyle(Theme.text2)
                            Button {
                                Terminal.copy(detail.hash)
                                model.showNotice("Hash copiado")
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 10.5))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.faded)
                            .help("Copiar o hash completo")
                            .accessibilityLabel("Copiar hash")
                        }
                        if !detail.parents.isEmpty {
                            meta(detail.parents.count > 1 ? "Pais" : "Pai") {
                                ForEach(detail.parents, id: \.self) { parent in
                                    Button(String(parent.prefix(7))) { onSelect(parent) }
                                        .buttonStyle(.plain)
                                        .font(Theme.mono(11.5))
                                        .foregroundStyle(Theme.irisText)
                                        .help("Ir para o commit \(parent.prefix(7))")
                                }
                            }
                        }
                    }
                    .font(.system(size: 12))
                    HStack(spacing: 8) {
                        Button {
                            onBranch(detail.hash)
                        } label: {
                            Label("Nova branch aqui", systemImage: "arrow.triangle.branch")
                        }
                        .buttonStyle(GhostButton(compact: true))
                        Spacer(minLength: 0)
                        Delta(added: detail.changes.reduce(0) { $0 + $1.added }, removed: detail.changes.reduce(0) { $0 + $1.removed })
                    }
                } else if error == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func meta<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(Theme.faded)
                .frame(width: 52, alignment: .leading)
            content()
        }
    }

    func loadDetail() async {
        let repo = repo
        let hash = hash
        do {
            let loaded = try await Core.run { try $0.commitDetail(repo, hash: hash) }
            detail = loaded
            error = nil
            file = loaded.changes.first?.id
        } catch {
            self.error = errorMessage(error)
        }
    }

    func loadDiff() async {
        guard let detail, let path = file else {
            diff = []
            return
        }
        let repo = repo
        diff = (try? await Core.run { try $0.commitFileDiff(repo, detail: detail, path: path) }) ?? []
    }
}
