import Foundation
import SwiftUI

enum CellType {
    case inside, outside, capsule
}

struct LoomView: View {
    @EnvironmentObject var model: AppModel
    let selected: LiveTrama
    @AppStorage("loomOnlyInside") private var onlyInside = false
    @State private var sweep = 1.0

    var body: some View {
        let columns = model.visibleTramas
        let hasContext = !(model.state?.context ?? "").isEmpty
        VStack(spacing: 0) {
            LoomHeader(columns: columns, selected: selected, onlyInside: $onlyInside)
            let repos = onlyInside ? model.repos.filter { selected.repos.contains($0.name) } : model.repos
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(repos.enumerated()), id: \.element.id) { index, repo in
                                LoomRow(repo: repo, columns: columns, selected: selected, rank: index, total: repos.count + (hasContext ? 1 : 0), sweep: sweep)
                            }
                            if let context = model.state?.context, !context.isEmpty {
                                ContextRow(context: context, columns: columns, selected: selected, rank: repos.count, total: repos.count + 1, sweep: sweep)
                            }
                        }
                        LoomTail(columns: columns, selected: selected)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(minHeight: viewport.size.height)
                }
            }
            .onChange(of: selected.slug) { _ in
                sweep = 0
                withAnimation(.linear(duration: min(0.4, 0.04 * Double(repos.count + 1)))) { sweep = 1 }
            }
            .scrollIndicators(.automatic)
        }
        .background(Theme.loom)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }
}

struct LoomTail: View {
    let columns: [LiveTrama]
    let selected: LiveTrama
    var fadesIn = false

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: nameWidth)
            ForEach(columns) { t in
                VerticalThread(selected: t.slug == selected.slug, parked: t.isParked)
                    .frame(width: columnWidth)
            }
            Spacer(minLength: 0)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: fadesIn ? .black.opacity(0) : .black, location: 0),
                .init(color: fadesIn ? .black : .black.opacity(0), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LoomHeader: View {
    @EnvironmentObject var model: AppModel
    let columns: [LiveTrama]
    let selected: LiveTrama
    @Binding var onlyInside: Bool

    func abbreviate(_ t: LiveTrama) -> String {
        t.slug.count <= 6 ? t.slug : String(t.slug.prefix(5)) + "."
    }

    var body: some View {
        HStack(spacing: 0) {
            SectionLabel(text: "Repositório")
                .padding(.leading, 16)
                .frame(width: nameWidth, alignment: .leading)
            ForEach(columns) { t in
                let current = t.slug == selected.slug
                Button {
                    model.select(t.slug)
                } label: {
                    Text(abbreviate(t))
                        .font(Theme.mono(10.5, weight: current ? .medium : .regular))
                        .foregroundStyle(current ? Theme.emberLight : Theme.faded)
                        .padding(.vertical, 5)
                        .background(Theme.loom)
                        .frame(width: columnWidth, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
            SectionLabel(text: "Nesta trama")
                .padding(.leading, 4)
            Spacer()
            Button {
                onlyInside.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: onlyInside ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    Text(onlyInside ? "Só na trama" : "Todos os repos")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(onlyInside ? Theme.emberText : Theme.faded)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay(Capsule().stroke(onlyInside ? Theme.ember.opacity(0.45) : Theme.line2, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(onlyInside ? "Mostrar todos os repositórios" : "Mostrar só os repositórios desta trama")
            Button {
                Task { await model.syncPrimaries(selected.slug) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Atualizar cópias")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay(Capsule().stroke(Theme.line2, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .help("Busca o remoto e atualiza (fast-forward) a cópia principal de cada repositório desta trama")
        }
        .frame(height: 44)
        .background { LoomTail(columns: columns, selected: selected, fadesIn: true) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

struct LoomRow: View {
    @EnvironmentObject var model: AppModel
    let repo: RepoConfig
    let columns: [LiveTrama]
    let selected: LiveTrama
    let rank: Int
    var total = 1
    var sweep = 1.0

    var inside: Bool { selected.repos.contains(repo.name) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(inside ? Theme.text : Theme.faded)
                    .lineLimit(1)
                Text(repo.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
            }
            .opacity(inside ? 1 : 0.55)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(width: nameWidth, alignment: .leading)
            ForEach(columns) { t in
                LoomCell(
                    type: t.repos.contains(repo.name) ? .inside : .outside,
                    selected: t.slug == selected.slug,
                    parked: t.isParked,
                    rank: rank,
                    total: total,
                    sweep: sweep,
                    agent: t.status(for: repo.name)?.primaryAgent
                )
            }
            RepoDetail(repo: repo, trama: selected)
                .padding(.leading, 4)
                .padding(.trailing, 14)
        }
        .frame(height: rowHeight)
        .background(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0x191B20)).frame(height: 1)
        }
    }
}

struct LoomCell: View {
    let type: CellType
    let selected: Bool
    let parked: Bool
    var rank = 0
    var total = 1
    var sweep = 1.0
    var agent: Agent?

    private var climb: Animation {
        selected
            ? .spring(response: 0.25, dampingFraction: 0.8)
            : .easeOut(duration: 0.18)
    }

    var body: some View {
        ZStack {
            VerticalThread(selected: selected, parked: parked, rank: rank, total: total, sweep: sweep)
            node
            if type == .inside, let agent, agent.isWorking || agent.isWaiting {
                PulseRing(color: agent.isWaiting ? Theme.wait : Theme.iris, size: selected ? 14 : 10)
            }
        }
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity)
        .animation(climb, value: selected)
    }

    @ViewBuilder var node: some View {
        switch type {
        case .inside:
            let size: CGFloat = selected ? 14 : 10
            Circle()
                .fill(selected ? Theme.ember : Theme.loom)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Theme.ember.opacity(0.16))
                        .frame(width: 22, height: 22)
                        .scaleEffect(selected ? 1 : 0.4)
                        .opacity(selected ? 1 : 0)
                )
                .overlay(
                    Circle()
                        .strokeBorder(parked ? Theme.faded : Theme.ring, style: StrokeStyle(lineWidth: parked ? 1.5 : 2, dash: parked ? [2, 2] : []))
                        .opacity(selected ? 0 : 1)
                )
                .shadow(color: Theme.ember.opacity(selected ? 0.55 : 0), radius: 8)
        case .outside:
            Rectangle()
                .fill(Theme.loom)
                .frame(width: selected ? 38 : 22, height: selected ? 30 : 22)
        case .capsule:
            if selected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.ember)
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(45))
                    .shadow(color: Theme.ember.opacity(0.5), radius: 6)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.loom)
                    .frame(width: 9, height: 9)
                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(parked ? Theme.faded : Theme.ring, lineWidth: 1.5))
                    .rotationEffect(.degrees(45))
            }
        }
    }
}

struct PulseRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let size: CGFloat
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1.5)
            .frame(width: size, height: size)
            .scaleEffect(expanded ? 2.4 : 1)
            .opacity(expanded ? 0 : 0.8)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { expanded = true }
            }
    }
}

struct ThreadFill: Shape {
    var sweep: Double
    let rank: Int
    let total: Int

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let count = Double(max(total, 1))
        let local = min(max(sweep * count - Double(rank), 0), 1)
        return Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * local))
    }
}

struct VerticalThread: View {
    let selected: Bool
    let parked: Bool
    var rank = 0
    var total = 1
    var sweep = 1.0

    var body: some View {
        ZStack {
            if parked {
                GeometryReader { g in
                    Path { p in
                        p.move(to: CGPoint(x: g.size.width / 2, y: 0))
                        p.addLine(to: CGPoint(x: g.size.width / 2, y: g.size.height))
                    }
                    .stroke(Theme.thread, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .frame(width: 2)
            } else {
                Rectangle()
                    .fill(Theme.thread)
                    .frame(width: 1)
            }
            if selected {
                ThreadFill(sweep: sweep, rank: rank, total: total)
                    .fill(Theme.ember)
                    .frame(width: 2)
                    .background(
                        ThreadFill(sweep: sweep, rank: rank, total: total)
                            .fill(Theme.ember.opacity(0.18))
                            .frame(width: 8)
                    )
            }
        }
    }
}

struct LoomLegend: View {
    let trama: LiveTrama

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(Theme.ember).frame(width: 9, height: 9)
                Text("na trama")
            }
            HStack(spacing: 6) {
                Rectangle().fill(Color(hex: 0x4A4E57)).frame(width: 2, height: 12)
                Text("passa por baixo")
            }
            HStack(spacing: 6) {
                Rectangle().fill(Theme.faded).frame(width: 7, height: 7).rotationEffect(.degrees(45))
                Text("cápsula")
            }
            HStack(spacing: 6) {
                Circle().strokeBorder(Theme.faded, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])).frame(width: 10, height: 10)
                Text("estacionada")
            }
            Spacer()
            Text(Paths.abbreviate(trama.path))
                .font(Theme.mono(12))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.faded)
    }
}
