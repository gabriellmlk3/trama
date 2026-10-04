import Foundation
import SwiftUI

enum NodeStyle {
    case hollow, baseTip, commit, merge, head, dirty
}

struct ThreadNode: View {
    let style: NodeStyle
    let appeared: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch style {
            case .hollow:
                Circle().fill(Theme.loom).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Theme.ring, lineWidth: 2))
            case .baseTip:
                Circle().fill(Theme.wait).frame(width: 12, height: 12)
                    .shadow(color: Theme.wait.opacity(0.5), radius: 6)
            case .commit:
                Circle().fill(Theme.ember).frame(width: 9, height: 9)
            case .merge:
                Circle().fill(Theme.loom).frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(Theme.emberLight, lineWidth: 2.5))
                    .overlay(Circle().fill(Theme.ember).frame(width: 4, height: 4))
            case .head:
                Circle().fill(Theme.ember.opacity(pulse ? 0 : 0.35))
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulse ? 2.3 : 1)
                Circle().fill(Theme.ember).frame(width: 15, height: 15)
                    .shadow(color: Theme.ember.opacity(0.6), radius: 8)
            case .dirty:
                Circle().fill(Theme.loom).frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(Theme.emberLight, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5])))
            }
        }
        .scaleEffect(appeared ? 1 : 0.2)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(delay), value: appeared)
        .onAppear {
            guard style == .head, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct BaseMenu: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let current: String
    @State private var branches: [String] = []

    var body: some View {
        AppMenu(width: 260) {
            HStack(spacing: 5) {
                Text("a partir de")
                    .foregroundStyle(Theme.faded)
                Text("origin/\(current)")
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.text2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.faded)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
        } content: {
            branches.map { b in
                MenuAction(b, checked: b == current) {
                    guard b != current else { return }
                    Task { await model.setBase(trama.slug, base: b) }
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(model.busy)
        .help("Escolher a branch em que esta trama se baseia (vale para todos os repositórios)")
        .task(id: trama.slug) {
            branches = await model.baseCandidates(repos: trama.repos, excluding: trama.branch)
        }
    }
}

struct BranchThread: View {
    let overview: GitOverview
    let status: RepoStatus
    var trama: LiveTrama?
    let repo: String
    let worktree: String
    let compare: String?
    let onCompare: (String?) -> Void
    @State private var picking = false

    private static let maxThreadHeight: CGFloat = 340

    var key: String {
        "\(overview.head?.hash ?? "")-\(overview.baseLabel)-\(overview.aheadCount)-\(overview.behindCount)-\(overview.changes.isEmpty)"
    }

    var body: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("O fio desta branch")
                        .font(.system(size: 12.5, weight: .semibold))
                    if let trama {
                        BaseMenu(trama: trama, current: overview.base)
                    }
                    Spacer()
                    Button {
                        picking = true
                    } label: {
                        Label(compare == nil ? "Comparar" : "vs \(overview.baseLabel)", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                    }
                    .buttonStyle(GhostButton(compact: true))
                    .help("Escolher qualquer branch para comparar com o fio")
                    if compare != nil {
                        Button("Base padrão") { onCompare(nil) }
                            .buttonStyle(GhostButton(compact: true))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                let column = BranchThreadColumn(overview: overview, status: status)
                ScrollView(.vertical) {
                    column
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.bottom)
                .frame(height: min(column.contentHeight, Self.maxThreadHeight))
                .id(key)
            }
        }
        .sheet(isPresented: $picking) {
            BranchPickerSheet(repo: repo, worktree: worktree, into: overview.branch, title: "Comparar \(overview.branch) com…") { onCompare($0) }
        }
        .frame(minWidth: 300)
        .layoutPriority(1)
    }
}

struct ThreadRow: Identifiable {
    enum Lane { case base, trama }

    var id: Int
    var lane: Lane
    var style: NodeStyle
    var tag: String?
    var hash: String?
    var subject: String
    var tone: Color = Theme.text3
    var showsAgent = false
    var plain = false
}

struct BranchThreadColumn: View {
    let overview: GitOverview
    let status: RepoStatus

    @State private var drawn = false

    private var headOnly: Bool { !hasAhead && !hasDirty && behindShown.isEmpty }
    private var baseX: CGFloat { headOnly ? 40 : 24 }
    private let tramaX: CGFloat = 60
    private var textX: CGFloat { headOnly ? 72 : 92 }
    private let headerHeight: CGFloat = 58
    private let rowHeight: CGFloat = 36

    var behindShown: [Commit] { Array(overview.behind.prefix(5).reversed()) }
    var aheadShown: [Commit] { Array(overview.ahead.reversed()) }
    var behindHidden: Int { max(0, overview.behindCount - behindShown.count) }
    var aheadHidden: Int { max(0, overview.aheadCount - aheadShown.count) }
    var agent: Agent? { status.agents.first(where: { $0.isWorking }) }
    var hasAhead: Bool { !aheadShown.isEmpty }
    var hasDirty: Bool { !overview.changes.isEmpty }

    var rows: [ThreadRow] {
        var out: [ThreadRow] = []
        func add(_ lane: ThreadRow.Lane, _ style: NodeStyle, tag: String? = nil, hash: String? = nil, subject: String = "", tone: Color = Theme.text3, agent: Bool = false, plain: Bool = false) {
            out.append(ThreadRow(id: out.count, lane: lane, style: style, tag: tag, hash: hash, subject: subject, tone: tone, showsAgent: agent, plain: plain))
        }
        let fork = overview.mergeBase
        if hasAhead || !behindShown.isEmpty {
            add(.base, .hollow, tag: "saiu daqui", hash: fork?.hash, subject: fork?.subject ?? "")
        } else if let head = overview.head {
            add(.base, .head, tag: "HEAD", hash: head.hash, subject: head.subject, tone: Theme.emberLight)
        }
        if behindHidden > 0 {
            add(.base, .hollow, subject: "… e mais \(behindHidden) \(plural(behindHidden, "commit", "commits")) na base", plain: true)
        }
        if aheadHidden > 0 {
            add(.trama, .commit, subject: "… e mais \(aheadHidden) \(plural(aheadHidden, "commit anterior", "commits anteriores"))", plain: true)
        }
        for (i, c) in behindShown.enumerated() {
            let tip = i == behindShown.count - 1
            add(.base, tip ? .baseTip : .hollow, hash: c.hash, subject: c.subject, tone: tip ? Theme.waitText : Theme.text3)
        }
        for (j, c) in aheadShown.enumerated() {
            let isHead = j == aheadShown.count - 1
            add(.trama, isHead ? .head : (c.isMerge ? .merge : .commit), tag: isHead ? "HEAD" : (c.isMerge ? "merge" : nil), hash: c.hash, subject: c.subject, tone: isHead || c.isMerge ? Theme.emberLight : Theme.text3, agent: isHead && agent != nil)
        }
        if hasDirty {
            let n = overview.changes.count
            add(.trama, .dirty, subject: "\(n) \(plural(n, "alteração", "alterações")) sem commit", tone: Theme.emberLight)
        }
        return out
    }

    var contentHeight: CGFloat { headerHeight + CGFloat(rows.count) * rowHeight + 14 }

    func y(_ index: Int) -> CGFloat { headerHeight + (CGFloat(index) + 0.5) * rowHeight }
    func x(_ lane: ThreadRow.Lane) -> CGFloat { lane == .base ? baseX : tramaX }

    var body: some View {
        let list = rows
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                legend
                    .opacity(drawn ? 1 : 0)
                    .animation(.easeIn(duration: 0.4).delay(0.2), value: drawn)
                lines(list)
                ForEach(list) { row in
                    if !row.plain {
                        ThreadNode(style: row.style, appeared: drawn, delay: 0.1 + Double(row.id) * 0.1)
                            .position(x: x(row.lane), y: y(row.id))
                    }
                    rowText(row)
                        .frame(width: max(40, geo.size.width - textX - 14), alignment: .leading)
                        .position(x: textX + max(40, geo.size.width - textX - 14) / 2, y: y(row.id))
                        .opacity(drawn ? 1 : 0)
                        .animation(.easeIn(duration: 0.35).delay(0.3 + Double(row.id) * 0.1), value: drawn)
                }
            }
            .onAppear { drawn = true }
        }
        .frame(height: contentHeight)
    }

    var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendLine(color: Theme.thread, name: overview.baseLabel, note: overview.behindCount > 0 ? "↓\(overview.behindCount) andou" : nil, tone: Theme.waitText)
            legendLine(color: Theme.ember, name: "trama", note: overview.aheadCount > 0 ? "↑\(overview.aheadCount) à frente" : nil, tone: Theme.emberLight)
        }
        .padding(.leading, 14)
        .padding(.top, 10)
    }

    func legendLine(color: Color, name: String, note: String?, tone: Color) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(color).frame(width: 16, height: 3)
            Text(name)
                .font(Theme.mono(11))
                .foregroundStyle(color == Theme.ember ? Theme.emberLight : Theme.faded)
                .lineLimit(1)
                .truncationMode(.middle)
            if let note {
                Text(note)
                    .font(Theme.mono(11))
                    .foregroundStyle(tone)
            }
        }
    }

    func lines(_ list: [ThreadRow]) -> some View {
        let baseRows = list.filter { $0.lane == .base }
        let tramaRows = list.filter { $0.lane == .trama }
        let forkY = y(0)
        return ZStack {
            Path { p in
                guard let last = baseRows.last, baseRows.count > 1 else { return }
                p.move(to: CGPoint(x: baseX, y: forkY))
                p.addLine(to: CGPoint(x: baseX, y: y(last.id)))
            }
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(Theme.thread, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .animation(.easeOut(duration: 0.7), value: drawn)

            Path { p in
                guard let last = tramaRows.last(where: { $0.style != .dirty }) ?? tramaRows.last, hasAhead || hasDirty else { return }
                p.move(to: CGPoint(x: baseX, y: forkY))
                p.addCurve(
                    to: CGPoint(x: tramaX, y: forkY + 28),
                    control1: CGPoint(x: baseX, y: forkY + 20),
                    control2: CGPoint(x: tramaX, y: forkY + 8)
                )
                p.addLine(to: CGPoint(x: tramaX, y: hasAhead ? y(last.id) : forkY + 28))
            }
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(Theme.ember, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .shadow(color: Theme.ember.opacity(0.35), radius: 4)
            .animation(.easeInOut(duration: 0.95).delay(0.25), value: drawn)

            Path { p in
                guard hasDirty, let dirty = tramaRows.last else { return }
                p.move(to: CGPoint(x: tramaX, y: hasAhead ? y(dirty.id - 1) : forkY + 28))
                p.addLine(to: CGPoint(x: tramaX, y: y(dirty.id)))
            }
            .stroke(Theme.emberLight.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .opacity(drawn ? 1 : 0)
            .animation(.easeIn(duration: 0.3).delay(1.1), value: drawn)
        }
    }

    func rowText(_ row: ThreadRow) -> some View {
        HStack(spacing: 7) {
            if let tag = row.tag {
                Text(tag)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(row.style == .head ? Theme.emberText : Theme.text3)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill((row.style == .head ? Theme.ember : Theme.faded).opacity(0.14)))
                    .fixedSize()
            }
            if let hash = row.hash {
                Text(hash)
                    .font(Theme.mono(11))
                    .foregroundStyle(row.tone)
                    .fixedSize()
            }
            Text(row.subject)
                .font(.system(size: 11.5))
                .foregroundStyle(row.style == .dirty ? Theme.emberLight : Theme.faded)
                .lineLimit(1)
                .truncationMode(.tail)
            if row.showsAgent, let agent {
                Text("agente aqui")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.irisText)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(Theme.iris.opacity(0.14)))
                    .overlay(Capsule().stroke(Theme.iris.opacity(0.4), lineWidth: 1))
                    .fixedSize()
                    .help(agent.message ?? "")
            }
        }
    }
}
