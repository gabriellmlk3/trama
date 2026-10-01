import Foundation
import SwiftUI

private enum NodeStyle {
    case hollow, baseTip, commit, head, dirty
}

private struct ThreadNode: View {
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

enum ThreadLayout: String, CaseIterable {
    case horizontal, vertical

    static let storageKey = "branchThreadLayout"
}

enum ThreadLane {
    case base, trama
}

struct BranchThread: View {
    let overview: GitOverview
    let status: RepoStatus

    @AppStorage(ThreadLayout.storageKey) private var layoutName = ThreadLayout.horizontal.rawValue
    @State private var drawn = false

    private let labelWidth: CGFloat = 116
    private let topY: CGFloat = 50
    private let bottomY: CGFloat = 116
    private let step: CGFloat = 46
    private let baseX: CGFloat = 100
    private let tramaX: CGFloat = 250
    private let verticalStart: CGFloat = 58

    var layout: ThreadLayout { ThreadLayout(rawValue: layoutName) ?? .horizontal }
    var vertical: Bool { layout == .vertical }

    var key: String {
        "\(layout.rawValue)-\(overview.head?.hash ?? "")-\(overview.aheadCount)-\(overview.behindCount)-\(overview.changes.isEmpty)"
    }

    var behindShown: [Commit] { Array(overview.behind.prefix(2).reversed()) }
    var aheadShown: [Commit] { Array(overview.ahead.prefix(4).reversed()) }
    var forkA: CGFloat { vertical ? verticalStart : labelWidth + 18 }
    var startA: CGFloat { vertical ? 34 : labelWidth - 6 }
    var agent: Agent? { status.agents.first(where: { $0.isWorking }) }

    func topA(_ i: Int) -> CGFloat { forkA + CGFloat(i) * step }
    func bottomA(_ j: Int) -> CGFloat { forkA + CGFloat(j + 1) * step }

    func cross(_ lane: ThreadLane) -> CGFloat {
        switch (lane, vertical) {
        case (.base, false): return topY
        case (.trama, false): return bottomY
        case (.base, true): return baseX
        case (.trama, true): return tramaX
        }
    }

    func pt(_ along: CGFloat, _ lane: ThreadLane) -> CGPoint {
        point(along, cross(lane))
    }

    func point(_ along: CGFloat, _ cross: CGFloat) -> CGPoint {
        vertical ? CGPoint(x: cross, y: along) : CGPoint(x: along, y: cross)
    }

    var canvasHeight: CGFloat {
        guard vertical else { return 152 }
        let rows = max(behindShown.count + 1, aheadShown.count + (overview.changes.isEmpty ? 0 : 1) + 1)
        return verticalStart + CGFloat(rows) * step + 44
    }

    var body: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("O fio desta branch")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("cada ponto é um commit")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                    Picker("Layout do fio", selection: $layoutName) {
                        Image(systemName: "arrow.right").tag(ThreadLayout.horizontal.rawValue)
                        Image(systemName: "arrow.down").tag(ThreadLayout.vertical.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 70)
                    .help("Mostrar o fio na horizontal ou na vertical")
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                canvas
                    .frame(height: canvasHeight)
                    .id(key)
            }
        }
        .frame(minWidth: vertical ? 330 : 380)
        .layoutPriority(1)
    }

    var canvas: some View {
        GeometryReader { geo in
            let topLast = topA(behindShown.count)
            let hasAhead = !aheadShown.isEmpty
            let bottomLast = hasAhead ? bottomA(aheadShown.count - 1) : forkA
            let dirtyA = (hasAhead ? bottomLast : forkA) + step
            let baseEnd = vertical ? min(geo.size.height - 24, topLast + 34) : min(geo.size.width - 150, topLast + 34)
            ZStack(alignment: .topLeading) {
                laneLabels

                Path { p in
                    p.move(to: pt(startA, .base))
                    p.addLine(to: pt(baseEnd, .base))
                }
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.thread, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(.easeOut(duration: 0.7), value: drawn)

                Path { p in
                    guard hasAhead || !overview.changes.isEmpty else { return }
                    p.move(to: pt(forkA, .base))
                    p.addCurve(
                        to: pt(forkA + 22, .trama),
                        control1: point(forkA, cross(.base) + 34),
                        control2: pt(forkA + 4, .trama)
                    )
                    p.addLine(to: pt(hasAhead ? bottomLast : forkA + 22, .trama))
                }
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.ember, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .shadow(color: Theme.ember.opacity(0.35), radius: 4)
                .animation(.easeInOut(duration: 0.95).delay(0.25), value: drawn)

                if overview.changes.count > 0 {
                    Path { p in
                        p.move(to: pt(hasAhead ? bottomLast : forkA + 22, .trama))
                        p.addLine(to: pt(dirtyA, .trama))
                    }
                    .stroke(Theme.emberLight.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .opacity(drawn ? 1 : 0)
                    .animation(.easeIn(duration: 0.3).delay(1.1), value: drawn)
                }

                ThreadNode(style: .hollow, appeared: drawn, delay: 0.1)
                    .position(pt(topA(0), .base))
                ForEach(Array(behindShown.enumerated()), id: \.offset) { i, c in
                    ThreadNode(style: i == behindShown.count - 1 ? .baseTip : .hollow, appeared: drawn, delay: 0.25 + Double(i) * 0.1)
                        .position(pt(topA(i + 1), .base))
                        .help(c.subject)
                }
                ForEach(Array(aheadShown.enumerated()), id: \.offset) { j, c in
                    let isHead = j == aheadShown.count - 1
                    ThreadNode(style: isHead ? .head : .commit, appeared: drawn, delay: 0.55 + Double(j) * 0.1)
                        .position(pt(bottomA(j), .trama))
                        .help(c.subject)
                }
                if !hasAhead {
                    ThreadNode(style: .head, appeared: drawn, delay: 0.3)
                        .position(pt(topA(0), .base))
                }
                if overview.changes.count > 0 {
                    ThreadNode(style: .dirty, appeared: drawn, delay: 1.0)
                        .position(pt(dirtyA, .trama))
                }

                annotations(topLast: topLast, bottomLast: bottomLast, dirtyA: dirtyA, hasAhead: hasAhead, width: geo.size.width)
                    .opacity(drawn ? 1 : 0)
                    .animation(.easeIn(duration: 0.4).delay(0.8), value: drawn)
            }
        }
        .onAppear { drawn = true }
    }

    @ViewBuilder var laneLabels: some View {
        if vertical {
            laneLabel("origin/\(overview.base)", at: CGPoint(x: baseX, y: 14), width: 130, ember: false)
            laneLabel("trama", at: CGPoint(x: tramaX, y: 14), width: 130, ember: true)
        } else {
            laneLabel("origin/\(overview.base)", at: CGPoint(x: 14 + (labelWidth - 22) / 2, y: topY), width: labelWidth - 22, ember: false, leading: true)
            laneLabel("trama", at: CGPoint(x: 14 + (labelWidth - 22) / 2, y: bottomY), width: labelWidth - 22, ember: true, leading: true)
        }
    }

    func laneLabel(_ label: String, at center: CGPoint, width: CGFloat, ember: Bool, leading: Bool = false) -> some View {
        Text(label)
            .font(Theme.mono(11))
            .foregroundStyle(ember ? Theme.emberLight : Theme.faded)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: width, alignment: leading ? .leading : .center)
            .position(center)
    }

    @ViewBuilder func annotations(topLast: CGFloat, bottomLast: CGFloat, dirtyA: CGFloat, hasAhead: Bool, width: CGFloat) -> some View {
        if let tip = overview.baseTip, !behindShown.isEmpty {
            nodeLabel(tip.hash, along: topLast, lane: .base, color: Theme.waitText, side: .before)
        }
        if let mb = overview.mergeBase, hasAhead {
            nodeLabel("saiu daqui · \(mb.hash)", along: forkA, lane: .base, side: .after)
        }
        if overview.behindCount > 0 {
            let chip = sideChip("↓\(overview.behindCount) · \(overview.base) andou", tone: Theme.wait, text: Theme.waitText)
            if vertical {
                chip.position(x: baseX, y: topLast + 38)
            } else {
                chip.position(x: min(width - 76, topLast + 100), y: topY)
            }
        }
        if overview.aheadCount > 0 {
            let chip = sideChip("↑\(overview.aheadCount) à frente", tone: Theme.ember, text: Theme.emberLight)
            let last = overview.changes.isEmpty ? bottomLast : dirtyA
            if vertical {
                chip.position(x: tramaX, y: last + 38)
            } else {
                chip.position(x: min(width - 52, last + 62), y: bottomY)
            }
        }
        if let agent, hasAhead {
            let capsule = Text("agente aqui")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.irisText)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Theme.iris.opacity(0.14)))
                .overlay(Capsule().stroke(Theme.iris.opacity(0.4), lineWidth: 1))
                .help(agent.message ?? "")
            if vertical {
                capsule.position(x: tramaX + 56, y: bottomLast + 22)
            } else {
                capsule.position(x: bottomLast - 6, y: bottomY - 26)
            }
        }
        if let head = overview.head {
            if hasAhead {
                nodeLabel("HEAD · \(head.hash)", along: bottomLast, lane: .trama, side: .after, horizontalShift: -24)
            } else {
                nodeLabel("HEAD · \(head.hash)", along: topA(0), lane: .base, side: .before, horizontalShift: 4)
            }
        }
    }

    enum LabelSide { case before, after }

    @ViewBuilder func nodeLabel(_ text: String, along: CGFloat, lane: ThreadLane, color: Color = Theme.text3, side: LabelSide, horizontalShift: CGFloat = 0) -> some View {
        let label = Text(text)
            .font(Theme.mono(11))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.middle)
        if vertical {
            if lane == .base {
                label.frame(width: 84, alignment: .trailing).position(x: baseX - 14 - 42, y: along)
            } else {
                label.frame(width: 90, alignment: .leading).position(x: tramaX + 14 + 45, y: along)
            }
        } else {
            let y = cross(lane) + (side == .before ? -22 : 22)
            label.fixedSize().offset(x: along + (side == .before ? -14 : 14) + horizontalShift, y: y - 8)
        }
    }

    func sideChip(_ text: String, tone: Color, text color: Color) -> some View {
        Text(text)
            .font(Theme.mono(11))
            .foregroundStyle(color)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(tone.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(tone.opacity(0.5), lineWidth: 1))
    }
}
