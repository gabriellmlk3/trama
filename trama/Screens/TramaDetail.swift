import Foundation
import SwiftUI

private let nameWidth: CGFloat = 168
private let columnWidth: CGFloat = 52
private let rowHeight: CGFloat = 84

struct TramaDetailView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("capsulePanelVisible") private var capsuleVisible = true
    @AppStorage("detailMode") private var modeName = DetailMode.loom.rawValue
    @State private var refreshToken = 0
    @State private var refreshing = false
    let trama: LiveTrama

    var mode: Binding<DetailMode> {
        Binding(
            get: { DetailMode(rawValue: modeName) ?? .loom },
            set: { modeName = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TramaHeader(trama: trama)
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    DetailBar(mode: mode, capsuleVisible: $capsuleVisible, refreshing: refreshing) { refreshToken += 1 }
                    switch mode.wrappedValue {
                    case .loom:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                LoomView(selected: trama)
                                LoomLegend(trama: trama)
                            }
                        }
                        .scrollIndicators(.automatic)
                        CapsuleComposer(trama: trama)
                    case .git:
                        GitView(trama: trama, refreshToken: refreshToken, refreshing: $refreshing)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if capsuleVisible {
                    Rectangle().fill(Theme.line).frame(width: 1)
                    CapsulePanel(trama: trama)
                        .frame(width: 372)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: capsuleVisible)
            .clipped()
        }
    }
}

struct TramaHeader: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    @State private var confirmingArchive = false
    @State private var confirmingPRs = false
    @State private var mergeSource: LiveTrama?

    var base: String {
        if let b = trama.base, !b.isEmpty { return b }
        return trama.status.first?.base ?? "main"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                    Text(trama.branch)
                        .foregroundStyle(Theme.emberLight)
                        .textSelection(.enabled)
                    Text("·")
                    Text("base \(base)")
                    Text("·")
                    Text("criada \(relativeTime(trama.createdAt))")
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.faded)
                HStack(spacing: 12) {
                    Text(trama.title)
                        .font(Theme.serif(36))
                        .lineLimit(1)
                    if let task = trama.task, !task.isEmpty {
                        Chip(text: "Tarefa \(task)")
                    }
                    Chip(text: "\(trama.repos.count) de \(model.repos.count) repositórios")
                    if trama.isParked {
                        Chip(text: "estacionada \(relativeTime(trama.parkedAt))", color: Theme.waitText)
                    }
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Menu {
                    Button("Mostrar pasta no Finder") { Terminal.reveal(trama.path) }
                    Button("Copiar nome da branch") { Terminal.copy(trama.branch) }
                    if trama.context != nil || model.state?.context != nil {
                        Button("Commitar cápsula no contexto") { Task { await model.sync(trama.slug) } }
                    }
                    Button("Repositório de contexto desta trama…") {
                        if let folder = Terminal.choosePaths(multiple: false, title: "Repositório de contexto de \(trama.title)").first {
                            Task { await model.setTramaContext(trama.slug, folder) }
                        }
                    }
                    if trama.context != nil {
                        Button("Usar o contexto padrão") { Task { await model.setTramaContext(trama.slug, nil) } }
                    }
                    Divider()
                    if trama.isActive {
                        Menu("Trazer commits de outra trama") {
                            ForEach(model.visibleTramas.filter { $0.slug != trama.slug }) { other in
                                let shared = trama.repos.filter { other.repos.contains($0) }
                                Button("\(other.title) · \(shared.isEmpty ? "sem repositório em comum" : model.aliases(shared).joined(separator: ", "))") {
                                    mergeSource = other
                                }
                                .disabled(shared.isEmpty)
                            }
                        }
                        .disabled(model.visibleTramas.count < 2)
                    }
                    Button("Arquivar trama…") { confirmingArchive = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
                .help("Mais ações")

                if trama.isParked {
                    Button {
                        model.resuming = trama
                    } label: {
                        Label("Retomar trama", systemImage: "play.fill")
                    }
                    .buttonStyle(EmberButton())
                } else {
                    Button {
                        Task { await model.park(trama.slug) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10))
                            Text("Estacionar")
                            KeyCap(text: "⇧⌘P")
                        }
                    }
                    .buttonStyle(GhostButton())
                    Button {
                        confirmingPRs = true
                    } label: {
                        Label(trama.trama.prs.isEmpty ? "Abrir PRs" : "Atualizar PRs", systemImage: "arrow.triangle.pull")
                    }
                    .buttonStyle(GhostButton())
                    .help("Envia as branches e abre (ou atualiza) um PR por repositório, ligados entre si")
                    Button {
                        model.openClaudeInAll(trama)
                    } label: {
                        Label("Abrir no Claude", systemImage: "sparkle")
                    }
                    .buttonStyle(EmberButton())
                    .help("Abre uma janela do Terminal com o Claude Code em cada repositório da trama")
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 18)
        .alert("Trazer “\(mergeSource?.title ?? "")” para cá?", isPresented: Binding(get: { mergeSource != nil }, set: { if !$0 { mergeSource = nil } })) {
            Button("Fazer merge") {
                if let source = mergeSource { Task { await model.merge(source, into: trama) } }
                mergeSource = nil
            }
            Button("Cancelar", role: .cancel) { mergeSource = nil }
        } message: {
            if let source = mergeSource {
                Text("Faz merge da branch \(source.branch) em \(trama.branch), nos repositórios que as duas têm. Se algum worktree daqui tiver mudanças não commitadas ou o merge previr conflito, nada é mesclado.")
            }
        }
        .confirmationDialog("Abrir PRs de “\(trama.title)”?", isPresented: $confirmingPRs) {
            Button("Abrir PRs") { Task { await model.openPullRequests(trama.slug, draft: false) } }
            Button("Abrir como rascunho") { Task { await model.openPullRequests(trama.slug, draft: true) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Envia a branch \(trama.branch) de cada repositório com commits novos para o remoto e abre um PR em cada um, com links cruzados.")
        }
        .alert("Arquivar “\(trama.title)”?", isPresented: $confirmingArchive) {
            Button("Arquivar", role: .destructive) { Task { await model.archive(trama.slug) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os worktrees são removidos; as branches \(trama.branch) continuam em cada repositório e a cápsula fica guardada. Se houver mudanças não commitadas, o arquivamento é recusado.")
        }
    }
}

enum CellType {
    case inside, outside, capsule
}

struct LoomView: View {
    @EnvironmentObject var model: AppModel
    let selected: LiveTrama

    var body: some View {
        let columns = model.visibleTramas
        VStack(spacing: 0) {
            LoomHeader(columns: columns, selected: selected)
            let hasContext = !(model.state?.context ?? "").isEmpty
            let count = model.repos.count
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.repos.enumerated()), id: \.element.id) { index, repo in
                        LoomRow(repo: repo, columns: columns, selected: selected, rank: count - 1 - index + (hasContext ? 1 : 0))
                    }
                    if let context = model.state?.context, !context.isEmpty {
                        ContextRow(context: context, columns: columns, selected: selected)
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
        .background(Theme.loom)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }
}

struct LoomHeader: View {
    @EnvironmentObject var model: AppModel
    let columns: [LiveTrama]
    let selected: LiveTrama

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
                        .frame(width: columnWidth, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
            SectionLabel(text: "Nesta trama")
                .padding(.leading, 4)
            Spacer()
        }
        .frame(height: 44)
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

    var inside: Bool { selected.repos.contains(repo.name) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(inside ? Theme.text : Theme.text3)
                    .lineLimit(1)
                Text(repo.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(width: nameWidth, alignment: .leading)
            ForEach(columns) { t in
                LoomCell(
                    type: t.repos.contains(repo.name) ? .inside : .outside,
                    selected: t.slug == selected.slug,
                    parked: t.isParked,
                    rank: rank,
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
    var agent: Agent?

    private var climb: Animation {
        selected
            ? .spring(response: 0.45, dampingFraction: 0.72).delay(Double(rank) * 0.1)
            : .easeOut(duration: 0.18)
    }

    var body: some View {
        ZStack {
            VerticalThread(selected: selected, parked: parked)
            node
            if type == .inside, let agent, agent.isWorking || agent.isWaiting {
                PulseRing(color: agent.isWaiting ? Theme.wait : Theme.iris, size: selected ? 14 : 10)
            }
        }
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity)
        .animation(climb, value: selected)
        .animation(climb, value: type)
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
                .frame(width: selected ? 18 : 7, height: selected ? 30 : 22)
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

struct VerticalThread: View {
    let selected: Bool
    let parked: Bool

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
            Rectangle()
                .fill(Theme.ember)
                .frame(width: 2)
                .shadow(color: Theme.ember.opacity(0.5), radius: 6)
                .scaleEffect(y: selected ? 1 : 0, anchor: .bottom)
                .opacity(selected ? 1 : 0)
        }
    }
}

struct RepoDetail: View {
    @EnvironmentObject var model: AppModel
    let repo: RepoConfig
    let trama: LiveTrama

    var body: some View {
        if trama.repos.contains(repo.name) {
            if let s = trama.status(for: repo.name) {
                InsideDetail(repo: repo, trama: trama, status: s)
            } else {
                Text("carregando…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fora desta trama")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text3)
                    Text("o fio passa por baixo, nada a mudar aqui")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if trama.isActive {
                    Button {
                        Task { await model.pull(trama.slug, repo.name) }
                    } label: {
                        Label("Puxar", systemImage: "plus")
                    }
                    .buttonStyle(GhostButton(compact: true))
                    .help("Cria a branch \(trama.branch) em \(repo.name) e inclui na trama")
                }
            }
        }
    }
}

struct InsideDetail: View {
    @EnvironmentObject var model: AppModel
    let repo: RepoConfig
    let trama: LiveTrama
    let status: RepoStatus

    var body: some View {
        let path = model.worktreePath(trama, repo.name)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SyncRow(status: status)
                AgentRow(status: status)
                PrepRow(repo: repo, trama: trama, status: status)
                ServicesRow(repo: repo, trama: trama, status: status)
                PullRequestRow(repo: repo, trama: trama)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let ag = status.primaryAgent, ag.isWaiting {
                    Button("Revisar") {
                        model.terminals.open(path: path, command: "claude", title: "\(repo.name) · claude")
                    }
                    .buttonStyle(ToneButton(color: Theme.wait, text: Theme.waitText))
                    .help("O agente está esperando sua aprovação")
                }
                Button {
                    model.terminals.open(path: path, command: nil, title: "\(repo.name) · \(trama.slug)")
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(IconButton())
                .help("Abrir o Terminal em \(repo.name)")
                .accessibilityLabel("Abrir o Terminal em \(repo.name)")
                Button {
                    model.terminals.open(path: path, command: "claude", title: "\(repo.name) · claude")
                } label: {
                    Image(systemName: "sparkle")
                }
                .buttonStyle(IconButton())
                .help("Abrir o Claude Code em \(repo.name)")
                .accessibilityLabel("Abrir o Claude Code em \(repo.name)")
                Menu {
                    Button("Mostrar no Finder") { Terminal.reveal(path) }
                    Button("Copiar caminho") { Terminal.copy(path) }
                    Divider()
                    Button("Soltar da trama") { Task { await model.drop(trama.slug, repo.name) } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .help("Mais ações")
            }
        }
    }
}

struct SyncRow: View {
    let status: RepoStatus

    var body: some View {
        HStack(spacing: 8) {
            if !status.exists {
                Text(status.error ?? "worktree não encontrado")
                    .foregroundStyle(Theme.waitText)
            } else {
                Text("↑\(status.ahead)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.text3)
                Text("↓\(status.behind)")
                    .font(Theme.mono(12))
                    .foregroundStyle(status.behind > 0 ? Theme.wait : Theme.text3)
                if status.conflict == "conflito" {
                    Text("⚠ conflito previsto")
                        .foregroundStyle(Theme.waitText)
                }
                Text(status.changed == 0 ? "limpo" : "\(status.changed) \(plural(status.changed, "alterado", "alterados"))")
                if let c = status.lastCommit {
                    Text("·")
                    Text("\(c.subject) · \(relativeTime(c.timestamp))")
                        .truncationMode(.tail)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.faded)
        .lineLimit(1)
    }
}

struct PrepRow: View {
    @EnvironmentObject var model: AppModel
    let repo: RepoConfig
    let trama: LiveTrama
    let status: RepoStatus

    var body: some View {
        if let prep = status.prep {
            HStack(spacing: 8) {
                switch prep {
                case PrepState.running:
                    ProgressView().controlSize(.mini)
                    Text("Preparando o ambiente…")
                        .foregroundStyle(Theme.irisText)
                case PrepState.failed:
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Theme.waitText)
                    Text("Preparo falhou")
                        .foregroundStyle(Theme.waitText)
                default:
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.okText)
                    Text("Ambiente pronto")
                        .foregroundStyle(Theme.okText)
                }
                if let log = status.prepLog {
                    Button("log") { Terminal.openFile(log) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.text3)
                }
                if prep == PrepState.failed, trama.isActive {
                    Button("tentar de novo") { Task { await model.prepare(trama.slug, repo.name) } }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.text3)
                }
            }
            .font(.system(size: 12.5))
            .lineLimit(1)
        }
    }
}

struct ServicesRow: View {
    @EnvironmentObject var model: AppModel
    let repo: RepoConfig
    let trama: LiveTrama
    let status: RepoStatus

    var body: some View {
        if !status.services.isEmpty {
            let anyRunning = status.services.contains { $0.running }
            HStack(spacing: 10) {
                ForEach(status.services) { s in
                    HStack(spacing: 6) {
                        Dot(color: s.running ? Theme.ok : Theme.faded, halo: s.running)
                        if s.running {
                            Button(s.name + " · :" + String(s.port)) {
                                if let url = URL(string: s.url) { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.okText)
                            .help("Abrir \(s.url)")
                            Button("log") { Terminal.openFile(s.log) }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.text3)
                        } else {
                            Text(s.name + " · :" + String(s.port))
                                .foregroundStyle(Theme.faded)
                        }
                    }
                }
                if trama.isActive {
                    Button(anyRunning ? "descer" : "subir") {
                        Task {
                            if anyRunning {
                                await model.stopServices(trama.slug, repo: repo.name)
                            } else {
                                await model.startServices(trama.slug, repo: repo.name)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.text3)
                    .help(anyRunning ? "Derruba os serviços de \(repo.name) nesta trama" : "Sobe os serviços de \(repo.name) nas portas desta trama")
                }
            }
            .font(.system(size: 12.5))
            .lineLimit(1)
        }
    }
}

struct PullRequestRow: View {
    @EnvironmentObject var model: AppModel
    let repo: RepoConfig
    let trama: LiveTrama

    var body: some View {
        if let url = trama.trama.prs[repo.name] {
            let info = model.pullRequests[trama.slug]?.first { $0.repo == repo.name }
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(stateColor(info))
                Button(label(info)) {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(stateColor(info))
                .help(url)
                if let info, info.state == "open" {
                    switch info.ci {
                    case CIState.success:
                        Label("CI ok", systemImage: "checkmark").foregroundStyle(Theme.okText)
                    case CIState.failure:
                        Label("CI falhou", systemImage: "xmark").foregroundStyle(Theme.waitText)
                    case CIState.pending:
                        Label("CI rodando", systemImage: "clock").foregroundStyle(Theme.irisText)
                    default:
                        EmptyView()
                    }
                }
            }
            .font(.system(size: 12.5))
            .lineLimit(1)
        }
    }

    func label(_ info: PullRequestInfo?) -> String {
        guard let info, info.number > 0 else { return "PR aberto" }
        let state: String
        switch info.state {
        case "merged": state = "mesclado"
        case "closed": state = "fechado"
        default: state = info.draft ? "rascunho" : "aberto"
        }
        return "PR #\(info.number) · \(state)"
    }

    func stateColor(_ info: PullRequestInfo?) -> Color {
        switch info?.state {
        case "merged": return Theme.irisText
        case "closed": return Theme.faded
        default: return Theme.text3
        }
    }
}

struct AgentRow: View {
    let status: RepoStatus

    var body: some View {
        HStack(spacing: 8) {
            if let ag = status.primaryAgent {
                if ag.isWaiting {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Theme.waitText)
                    Text("Aguardando você" + suffix(ag))
                        .foregroundStyle(Theme.waitText)
                } else if ag.isWorking {
                    Dot(color: Theme.iris, halo: true)
                    Text("Agente trabalhando" + suffix(ag))
                        .foregroundStyle(Theme.irisText)
                } else if ag.isDone {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.okText)
                    Text("Agente concluiu" + suffix(ag))
                        .foregroundStyle(Theme.okText)
                } else {
                    Dot(color: Theme.faded)
                    Text("Sessão do Claude aberta")
                        .foregroundStyle(Theme.text3)
                }
                if status.agents.count > 1 {
                    Text("+\(status.agents.count - 1)")
                        .foregroundStyle(Theme.faded)
                }
            } else {
                Text("sem agente aberto")
                    .foregroundStyle(Theme.faded)
            }
        }
        .font(.system(size: 12.5))
        .lineLimit(1)
    }

    func suffix(_ ag: Agent) -> String {
        guard let m = ag.message, !m.isEmpty else { return "" }
        return ": " + m
    }
}

struct ContextRow: View {
    @EnvironmentObject var model: AppModel
    let context: String
    let columns: [LiveTrama]
    let selected: LiveTrama

    var summary: String {
        guard let c = model.capsule, c.trama == selected.slug, c.exists else {
            return "a cápsula desta trama ainda não existe"
        }
        var parts = ["\(c.decisions.count) \(plural(c.decisions.count, "decisão", "decisões"))"]
        let open = c.openHandoffs.count
        if open > 0 { parts.append("\(open) \(plural(open, "handoff aberto", "handoffs abertos"))") }
        if let at = c.updatedAt { parts.append("atualizada \(relativeTime(at))") }
        return parts.joined(separator: " · ")
    }

    var file: String {
        let path = selected.capsule
        if path.hasPrefix(context + "/") {
            return String(path.dropFirst(context.count + 1))
        }
        return Paths.abbreviate(path)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: context).lastPathComponent)
                    .font(Theme.mono(12.5))
                    .lineLimit(1)
                Text("contexto compartilhado")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(width: nameWidth, alignment: .leading)
            ForEach(columns) { t in
                LoomCell(type: .capsule, selected: t.slug == selected.slug, parked: t.isParked)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(file)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    Terminal.openFile(selected.capsule)
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(IconButton())
                .help("Abrir a cápsula no editor")
                .accessibilityLabel("Abrir a cápsula")
            }
            .padding(.leading, 4)
            .padding(.trailing, 14)
        }
        .frame(height: rowHeight)
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

struct CapsuleComposer: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    @State private var text = ""
    @State private var kind = NoteType.decision

    enum NoteType: String, CaseIterable, Identifiable {
        case decision = "Decisão"
        case pending = "Pendência"
        case note = "Nota no diário"
        var id: String { rawValue }

        var noteKind: AppModel.NoteKind {
            switch self {
            case .decision: return .decision
            case .pending: return .pending
            case .note: return .note
            }
        }
    }

    var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .foregroundStyle(Theme.iris)
            Picker("Tipo", selection: $kind) {
                ForEach(NoteType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            TextField("Escreva na cápsula · os agentes leem ao começar", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.emberDark)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(empty ? Theme.ember.opacity(0.4) : Theme.ember))
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .accessibilityLabel("Registrar na cápsula")
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x262930), lineWidth: 1))
    }

    func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let noteKind = kind.noteKind
        let slug = trama.slug
        text = ""
        Task { await model.annotate(noteKind, t, trama: slug) }
    }
}
