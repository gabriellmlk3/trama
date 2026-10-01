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

struct BranchThread: View {
    let overview: GitOverview
    let status: RepoStatus

    @State private var drawn = false

    private let labelWidth: CGFloat = 116
    private let topY: CGFloat = 50
    private let bottomY: CGFloat = 116
    private let step: CGFloat = 46

    var key: String {
        "\(overview.head?.hash ?? "")-\(overview.aheadCount)-\(overview.behindCount)-\(overview.changes.isEmpty)"
    }

    var behindShown: [Commit] { Array(overview.behind.prefix(2).reversed()) }
    var aheadShown: [Commit] { Array(overview.ahead.prefix(4).reversed()) }
    var forkX: CGFloat { labelWidth + 18 }
    var agent: Agent? { status.agents.first(where: { $0.isWorking }) }

    func topX(_ i: Int) -> CGFloat { forkX + CGFloat(i) * step }
    func bottomX(_ j: Int) -> CGFloat { forkX + CGFloat(j + 1) * step }

    var body: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("O fio desta branch")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("cada ponto é um commit")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                canvas
                    .frame(height: 152)
                    .id(key)
            }
        }
        .frame(minWidth: 380)
        .layoutPriority(1)
    }

    var canvas: some View {
        GeometryReader { geo in
            let topLast = topX(behindShown.count)
            let hasAhead = !aheadShown.isEmpty
            let bottomLast = hasAhead ? bottomX(aheadShown.count - 1) : forkX
            let dirtyX = (hasAhead ? bottomLast : forkX) + step
            ZStack(alignment: .topLeading) {
                lane(label: "origin/\(overview.base)", y: topY)
                lane(label: "trama", y: bottomY, ember: true)

                Path { p in
                    p.move(to: CGPoint(x: labelWidth - 6, y: topY))
                    p.addLine(to: CGPoint(x: min(geo.size.width - 150, topLast + 34), y: topY))
                }
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.thread, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(.easeOut(duration: 0.7), value: drawn)

                Path { p in
                    guard hasAhead || !overview.changes.isEmpty else { return }
                    p.move(to: CGPoint(x: forkX, y: topY))
                    p.addCurve(
                        to: CGPoint(x: forkX + 22, y: bottomY),
                        control1: CGPoint(x: forkX, y: topY + 34),
                        control2: CGPoint(x: forkX + 4, y: bottomY)
                    )
                    p.addLine(to: CGPoint(x: hasAhead ? bottomLast : forkX + 22, y: bottomY))
                }
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.ember, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .shadow(color: Theme.ember.opacity(0.35), radius: 4)
                .animation(.easeInOut(duration: 0.95).delay(0.25), value: drawn)

                if overview.changes.count > 0 {
                    Path { p in
                        p.move(to: CGPoint(x: hasAhead ? bottomLast : forkX + 22, y: bottomY))
                        p.addLine(to: CGPoint(x: dirtyX, y: bottomY))
                    }
                    .stroke(Theme.emberLight.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .opacity(drawn ? 1 : 0)
                    .animation(.easeIn(duration: 0.3).delay(1.1), value: drawn)
                }

                ThreadNode(style: .hollow, appeared: drawn, delay: 0.1)
                    .position(x: topX(0), y: topY)
                ForEach(Array(behindShown.enumerated()), id: \.offset) { i, c in
                    ThreadNode(style: i == behindShown.count - 1 ? .baseTip : .hollow, appeared: drawn, delay: 0.25 + Double(i) * 0.1)
                        .position(x: topX(i + 1), y: topY)
                        .help(c.subject)
                }
                ForEach(Array(aheadShown.enumerated()), id: \.offset) { j, c in
                    let isHead = j == aheadShown.count - 1
                    ThreadNode(style: isHead ? .head : .commit, appeared: drawn, delay: 0.55 + Double(j) * 0.1)
                        .position(x: bottomX(j), y: bottomY)
                        .help(c.subject)
                }
                if !hasAhead {
                    ThreadNode(style: .head, appeared: drawn, delay: 0.3)
                        .position(x: topX(0), y: topY)
                }
                if overview.changes.count > 0 {
                    ThreadNode(style: .dirty, appeared: drawn, delay: 1.0)
                        .position(x: dirtyX, y: bottomY)
                }

                annotations(topLast: topLast, bottomLast: bottomLast, dirtyX: dirtyX, hasAhead: hasAhead, width: geo.size.width)
                    .opacity(drawn ? 1 : 0)
                    .animation(.easeIn(duration: 0.4).delay(0.8), value: drawn)
            }
        }
        .onAppear { drawn = true }
    }

    func lane(label: String, y: CGFloat, ember: Bool = false) -> some View {
        Text(label)
            .font(Theme.mono(11))
            .foregroundStyle(ember ? Theme.emberLight : Theme.faded)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: labelWidth - 22, alignment: .leading)
            .position(x: 14 + (labelWidth - 22) / 2, y: y)
    }

    @ViewBuilder func annotations(topLast: CGFloat, bottomLast: CGFloat, dirtyX: CGFloat, hasAhead: Bool, width: CGFloat) -> some View {
        if let tip = overview.baseTip, !behindShown.isEmpty {
            nodeLabel(tip.hash, x: topLast - 14, y: topY - 22, color: Theme.waitText)
        }
        if let mb = overview.mergeBase, hasAhead {
            nodeLabel("saiu daqui · \(mb.hash)", x: forkX + 14, y: topY + 22)
        }
        if overview.behindCount > 0 {
            sideChip("↓\(overview.behindCount) · \(overview.base) andou", tone: Theme.wait, text: Theme.waitText)
                .position(x: min(width - 76, topLast + 100), y: topY)
        }
        if overview.aheadCount > 0 {
            sideChip("↑\(overview.aheadCount) à frente", tone: Theme.ember, text: Theme.emberLight)
                .position(x: min(width - 52, (overview.changes.isEmpty ? bottomLast : dirtyX) + 62), y: bottomY)
        }
        if let agent, hasAhead {
            Text("agente aqui")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.irisText)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Theme.iris.opacity(0.14)))
                .overlay(Capsule().stroke(Theme.iris.opacity(0.4), lineWidth: 1))
                .position(x: bottomLast - 6, y: bottomY - 26)
                .help(agent.message ?? "")
        }
        if let head = overview.head {
            if hasAhead {
                nodeLabel("HEAD · \(head.hash)", x: bottomLast - 10, y: bottomY + 22)
            } else if overview.baseTip != nil, !behindShown.isEmpty {
                nodeLabel("HEAD · \(head.hash)", x: topX(0) + 14, y: topY + 22)
            } else {
                nodeLabel("HEAD · \(head.hash)", x: topX(0) - 10, y: topY - 22)
            }
        }
    }

    func nodeLabel(_ text: String, x: CGFloat, y: CGFloat, color: Color = Theme.text3) -> some View {
        Text(text)
            .font(Theme.mono(11))
            .foregroundStyle(color)
            .fixedSize()
            .offset(x: x, y: y - 8)
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
