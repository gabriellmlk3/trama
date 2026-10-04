import Foundation
import SwiftUI

struct AttentionItem: Identifiable {
    let id: String
    let icon: String
    let tone: Color
    let title: String
    let detail: String
    let target: AppModel.Screen
}

extension AppModel {
    var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        let tramas = visibleTramas.filter { $0.isActive }
        for agent in activeAgents where agent.isWaiting {
            guard let t = tramas.first(where: { $0.slug == agent.trama }) else { continue }
            let who = agent.isRoot ? "O agente" : "O agente de \(aliases([agent.repo]).joined())"
            items.append(AttentionItem(
                id: "agent-\(agent.session)",
                icon: "hand.raised.fill",
                tone: Theme.wait,
                title: "\(who) espera por você",
                detail: "\(t.title) · \(agent.message ?? "precisa de uma resposta")",
                target: .trama(t.slug)
            ))
        }
        for t in tramas {
            for s in t.status {
                if s.conflict == "conflito" {
                    items.append(AttentionItem(
                        id: "conflict-\(t.slug)-\(s.repo)",
                        icon: "exclamationmark.triangle.fill",
                        tone: Theme.danger,
                        title: "Conflito em \(s.alias)",
                        detail: "\(t.title) · resolva para seguir",
                        target: .trama(t.slug)
                    ))
                } else if s.exists, s.behind > 0 {
                    items.append(AttentionItem(
                        id: "behind-\(t.slug)-\(s.repo)",
                        icon: "arrow.down.circle",
                        tone: Theme.iris,
                        title: "\(s.alias) está \(s.behind) \(plural(s.behind, "commit", "commits")) atrás de \(s.base)",
                        detail: t.title,
                        target: .trama(t.slug)
                    ))
                }
            }
        }
        if !findings.isEmpty {
            items.append(AttentionItem(
                id: "findings",
                icon: "tray.full",
                tone: Theme.ember,
                title: "\(findings.count) \(plural(findings.count, "achado", "achados")) em Achados & perdidos",
                detail: "Branches e worktrees fora de qualquer trama",
                target: .findings
            ))
        }
        return items
    }
}

struct HomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.visibleTramas.isEmpty {
            EmptyStateView()
        } else {
            VStack(spacing: 0) {
                homeScroll
                if !model.repos.isEmpty {
                    HomeAgentBar()
                }
            }
        }
    }

    private var homeScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeHero()
                VStack(alignment: .leading, spacing: 34) {
                    HomeAttention()
                    HomeActive()
                    HomeParked()
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .padding(.bottom, 44)
                .frame(maxWidth: 1180, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}

struct HomeAgentBar: View {
    var body: some View {
        HomeAgentBox()
            .padding(.horizontal, 40)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.panel)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
    }
}

struct HomeAgentPulse: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HomeAgentPulseDot(state: model.homeAgent?.state, reduceMotion: reduceMotion)
    }
}

struct HomeAgentPulseDot: View {
    let state: String?
    let reduceMotion: Bool

    private var working: Bool { state == AgentState.working }
    private var waiting: Bool { state == AgentState.waiting }
    private var color: Color { working ? Theme.iris : waiting ? Theme.wait : Theme.ember }
    private var help: String {
        working ? "O agent geral está trabalhando" : waiting ? "O agent geral espera por você" : "Agent geral"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !(working || waiting))) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let beat = (sin(t * (working ? 5 : 1.8)) + 1) / 2
            let animated = (working || waiting) && !reduceMotion
            ZStack {
                Circle()
                    .stroke(color.opacity(animated ? 0.5 * (1 - beat) : 0), lineWidth: 1.5)
                    .frame(width: 12 + 10 * CGFloat(beat), height: 12 + 10 * CGFloat(beat))
                Image(systemName: "sparkle")
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                    .opacity(animated ? 0.65 + 0.35 * beat : 1)
                    .scaleEffect(animated ? 1 + 0.12 * CGFloat(beat) : 1)
            }
            .frame(width: 22, height: 22)
        }
        .help(help)
    }
}

struct HomeAgentBox: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            HomeAgentPulse()
            TextField("Descreva o que precisa mudar e o agent propõe a trama", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(empty ? Theme.ember.opacity(0.4) : Theme.ember))
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .help("Abrir o agent geral com este pedido")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .frame(maxWidth: 1100)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line2, lineWidth: 1))
    }

    private func send() {
        guard !empty else { return }
        model.askHomeAgent(text)
        text = ""
    }
}

struct HomeHero: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Bom dia"
        case 12..<18: return "Boa tarde"
        default: return "Boa noite"
        }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: Date())
    }

    private var strands: [Strand] {
        var list = model.visibleTramas.prefix(8).map { t -> Strand in
            let agents = model.agents(for: t.slug)
            if t.isParked { return Strand(color: Theme.thread, dashed: true) }
            if t.conflicts > 0 { return Strand(color: Theme.danger, dashed: false) }
            if agents.contains(where: { $0.isWaiting }) { return Strand(color: Theme.wait, dashed: false) }
            if agents.contains(where: { $0.isWorking }) { return Strand(color: Theme.iris, dashed: false) }
            return Strand(color: Theme.ember, dashed: false)
        }
        while list.count < 4 { list.append(Strand(color: Theme.line2, dashed: false)) }
        return list
    }

    private var summary: String {
        let active = model.active.count
        let waiting = model.waitingCount
        var parts = ["\(active) \(plural(active, "trama tecendo", "tramas tecendo"))"]
        if waiting > 0 {
            parts.append("\(waiting) \(plural(waiting, "agente espera", "agentes esperam")) por você")
        } else if !model.activeAgents.isEmpty {
            parts.append("tudo andando sem te chamar")
        }
        return parts.joined(separator: " · ")
    }

    private var dirtyRepos: Int {
        model.active.reduce(0) { $0 + $1.status.filter { $0.changed > 0 }.count }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WeaveCanvas(strands: strands, animated: !reduceMotion)
                .mask(LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.9)], startPoint: .leading, endPoint: .trailing))
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(dateText.uppercased())
                        .font(Theme.mono(10.5))
                        .tracking(1.4)
                        .foregroundStyle(Theme.faded)
                    Spacer()
                    Button {
                        model.showingNewTrama = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("Tecer nova trama")
                            KeyCap(text: "⌘N", dark: true)
                        }
                    }
                    .buttonStyle(EmberButton())
                    .disabled(model.repos.isEmpty)
                }
                (Text(greeting).foregroundColor(Theme.text) + Text(".").foregroundColor(Theme.ember))
                    .font(Theme.serif(58))
                    .padding(.top, 14)
                Text(summary)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text3)
                    .padding(.top, 2)
                HStack(spacing: 34) {
                    HomeStat(value: model.active.count, label: "tecendo", tone: Theme.ember)
                    HomeStat(value: model.waitingCount, label: "esperando você", tone: Theme.wait)
                    HomeStat(value: dirtyRepos, label: "repos com alterações", tone: Theme.iris)
                    HomeStat(value: model.parked.count, label: "estacionadas", tone: Theme.faded)
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, 40)
            .padding(.top, 52)
            .padding(.bottom, 34)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeStat: View {
    let value: Int
    let label: String
    let tone: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(value)")
                .font(Theme.serif(34))
                .foregroundStyle(value > 0 ? tone : Theme.thread)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
        }
    }
}

struct Strand {
    let color: Color
    let dashed: Bool
}

struct WeaveCanvas: View {
    let strands: [Strand]
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { context in
            Canvas { gc, size in
                let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
                let gap: CGFloat = 16
                let columns = Int(size.width / gap) + 1

                var warp = Path()
                for i in 0..<columns {
                    let x = CGFloat(i) * gap
                    warp.move(to: CGPoint(x: x, y: 0))
                    warp.addLine(to: CGPoint(x: x, y: size.height))
                }
                gc.stroke(warp, with: .color(Theme.line2.opacity(0.55)), lineWidth: 1)

                for (s, strand) in strands.enumerated() {
                    let phase = Double(s) * 1.7
                    let amplitude = 9 + CGFloat(s % 3) * 5
                    let baseY = size.height * (0.22 + 0.62 * CGFloat(s + 1) / CGFloat(strands.count + 1))
                    func y(_ x: CGFloat) -> CGFloat {
                        baseY
                            + CGFloat(sin(Double(x) / 95 + phase + t * 0.45)) * amplitude
                            + CGFloat(sin(Double(x) / 38 + phase * 2 + t * 0.3)) * amplitude * 0.3
                    }
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y(0)))
                    var x: CGFloat = 4
                    while x <= size.width {
                        path.addLine(to: CGPoint(x: x, y: y(x)))
                        x += 4
                    }
                    if !strand.dashed {
                        gc.stroke(path, with: .color(strand.color.opacity(0.14)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    }
                    gc.stroke(
                        path,
                        with: .color(strand.color.opacity(strand.dashed ? 0.7 : 0.95)),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: strand.dashed ? [5, 6] : [])
                    )
                    var over = Path()
                    for i in 0..<columns where (i + s) % 2 == 0 {
                        let cx = CGFloat(i) * gap
                        let cy = y(cx)
                        over.move(to: CGPoint(x: cx, y: cy - 3.2))
                        over.addLine(to: CGPoint(x: cx, y: cy + 3.2))
                    }
                    gc.stroke(over, with: .color(Theme.thread), style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                }
            }
        }
    }
}

struct HomeSectionHeader: View {
    let title: String
    var count: Int?
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(Theme.serif(26))
                .foregroundStyle(Theme.text)
            if let count {
                Text("\(count)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faded)
            }
            Spacer()
            if let note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
            }
        }
    }
}

struct HomeAttention: View {
    @EnvironmentObject var model: AppModel
    private let limit = 5

    var body: some View {
        let items = model.attentionItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "Pede atenção", count: items.count)
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        AttentionRow(item: item)
                    }
                    if items.count > limit {
                        Rectangle().fill(Theme.line).frame(height: 1)
                        Text("+ \(items.count - limit) \(plural(items.count - limit, "item", "itens")) a mais")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.faded)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line2, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct AttentionRow: View {
    @EnvironmentObject var model: AppModel
    let item: AttentionItem
    @State private var hovering = false

    var body: some View {
        Button {
            switch item.target {
            case .trama(let slug): model.select(slug)
            case .findings: model.screen = .findings
            case .home: model.screen = .home
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(item.tone)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(item.tone.opacity(0.13)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Theme.text2 : Theme.thread)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(hovering ? Theme.surface2 : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct HomeActive: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let tramas = model.active
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(title: "Tecendo agora", count: tramas.count)
            if tramas.isEmpty {
                Text("Nenhuma trama ativa. Retome uma estacionada ou tece uma nova.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faded)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(tramas) { t in
                        HomeTramaCard(trama: t)
                    }
                }
            }
        }
    }
}

struct HomeTramaCard: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    @State private var hovering = false

    private var agents: [Agent] { model.agents(for: trama.slug) }

    private var tone: Color {
        if trama.conflicts > 0 { return Theme.danger }
        if agents.contains(where: { $0.isWaiting }) { return Theme.wait }
        if agents.contains(where: { $0.isWorking }) { return Theme.iris }
        return Theme.ember
    }

    private var summary: String {
        let changed = trama.status.reduce(0) { $0 + $1.changed }
        let ahead = trama.status.reduce(0) { $0 + $1.ahead }
        let behind = trama.status.reduce(0) { $0 + $1.behind }
        var parts: [String] = []
        if changed > 0 { parts.append("\(changed) \(plural(changed, "alteração", "alterações"))") }
        if ahead > 0 { parts.append("\(ahead) à frente") }
        if behind > 0 { parts.append("\(behind) atrás") }
        return parts.isEmpty ? "Tudo em dia" : parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            model.select(trama.slug)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trama.title)
                            .font(Theme.serif(25))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(trama.branch)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.faded)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    TramaIndicator(trama: trama, agents: agents)
                        .padding(.top, 4)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(trama.status.prefix(7)) { s in
                        RepoThread(status: s)
                    }
                    if trama.status.count > 7 {
                        Text("+\(trama.status.count - 7)")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.faded)
                            .padding(.bottom, 2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 58, alignment: .bottom)
                HStack {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    Text(relativeTime(trama.updatedAt))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(
                    LinearGradient(
                        colors: [tone.opacity(hovering ? 0.12 : 0.06), Theme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hovering ? tone.opacity(0.5) : Theme.line2, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .offset(y: hovering ? -2 : 0)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Abrir no Claude") { model.openClaudeInAll(trama) }
            Button("Estacionar") { Task { await model.park(trama.slug) } }
            Button("Mostrar no Finder") { Terminal.reveal(trama.path) }
            Button("Copiar nome da branch") { Terminal.copy(trama.branch) }
        }
    }
}

struct RepoThread: View {
    let status: RepoStatus

    private var color: Color {
        if status.conflict == "conflito" { return Theme.danger }
        if status.changed > 0 { return Theme.ember }
        if status.ahead > 0 { return Theme.iris }
        if status.behind > 0 { return Theme.wait }
        return Theme.thread
    }

    private var height: CGFloat {
        18 + CGFloat(min(status.changed + status.ahead, 10)) * 3.2
    }

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: height)
                .shadow(color: color.opacity(color == Theme.thread ? 0 : 0.55), radius: 4)
            Text(status.alias)
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.faded)
                .lineLimit(1)
                .frame(maxWidth: 46)
        }
        .help(help)
    }

    private var help: String {
        var parts = [status.alias]
        if status.changed > 0 { parts.append("\(status.changed) alterações") }
        if status.ahead > 0 { parts.append("\(status.ahead) à frente") }
        if status.behind > 0 { parts.append("\(status.behind) atrás") }
        if status.conflict == "conflito" { parts.append("em conflito") }
        return parts.joined(separator: " · ")
    }
}

struct HomeParked: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let tramas = model.parked
        if !tramas.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "Estacionadas", count: tramas.count, note: "fios guardados, prontos para retomar")
                VStack(spacing: 0) {
                    ForEach(Array(tramas.enumerated()), id: \.element.id) { index, t in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        ParkedRow(trama: t)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct ParkedRow: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            MarkerThread(highlighted: false, dashed: true)
            Button {
                model.select(trama.slug)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trama.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                    Text(model.aliases(trama.repos).joined(separator: " · "))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(relativeTime(trama.parkedAt))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
            Button("Retomar…") { model.resuming = trama }
                .buttonStyle(GhostButton(compact: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(hovering ? Theme.surface2.opacity(0.6) : Color.clear)
        .onHover { hovering = $0 }
    }
}
