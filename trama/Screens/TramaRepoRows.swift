import Foundation
import SwiftUI

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
                        .foregroundStyle(Theme.faded)
                    Text("o fio passa por baixo, nada a mudar aqui")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
                .opacity(0.55)
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
                HandoffRow(repo: repo, trama: trama)
                PrepRow(repo: repo, trama: trama, status: status)
                ServicesRow(repo: repo, trama: trama, status: status)
                PullRequestRow(repo: repo, trama: trama)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let ag = status.primaryAgent, ag.isWaiting {
                    Button("Revisar") {
                        let known = ClaudeSessions.conversations(at: path).contains { $0.id == ag.session }
                        model.openClaude(path: path, title: "\(repo.name) · claude", resume: known ? .conversation(ag.session) : .latest)
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
                    Task { await model.openInEditor(trama.slug, repos: [repo.name]) }
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(IconButton())
                .help("Abrir o worktree de \(repo.name) no editor")
                .accessibilityLabel("Abrir \(repo.name) no editor")
                if trama.isActive {
                    Button {
                        model.openAgent(trama, repo: repo.name)
                    } label: {
                        Image(systemName: model.isAgentBusy(trama.slug, repo: repo.name) ? "ellipsis.bubble" : "bubble.left.and.text.bubble.right")
                    }
                    .buttonStyle(IconButton())
                    .help("Agent embutido de \(repo.name) · só este worktree")
                    .accessibilityLabel("Abrir o agent embutido de \(repo.name)")
                }
                ClaudeMenu(path: path, repo: repo.name)
                AppMenu {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                } content: {
                    MenuAction("Mostrar no Finder") { Terminal.reveal(path) }
                    MenuAction("Copiar caminho") { Terminal.copy(path) }
                    MenuDivider()
                    MenuAction("Soltar da trama") { Task { await model.drop(trama.slug, repo.name) } }
                }
                .buttonStyle(.plain)
                .help("Mais ações")
            }
        }
    }
}

struct HandoffRow: View {
    @EnvironmentObject var model: AppModel
    let repo: RepoConfig
    let trama: LiveTrama

    var body: some View {
        if let capsule = model.capsule, capsule.trama == trama.slug {
            let open = capsule.openHandoffs.filter { $0.to == repo.name }
            if let first = open.first {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right.circle")
                        .foregroundStyle(Theme.emberLight)
                    Text(open.count == 1 ? "Handoff pendente" : "\(open.count) handoffs pendentes")
                        .foregroundStyle(Theme.emberLight)
                    if trama.isActive {
                        Button("abrir agent") { model.openAgent(trama, repo: repo.name, handoff: first) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.text3)
                            .help("Abre o agent de \(repo.name) já com o handoff: \(first.text)")
                    }
                }
                .font(.system(size: 12.5))
                .lineLimit(1)
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

struct TramaAgentBadge: View {
    let agent: Agent?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var tone: (fg: Color, bg: Color) {
        guard let ag = agent else { return (Theme.faded, Theme.line) }
        if ag.isWaiting { return (Theme.waitText, Theme.wait.opacity(0.14)) }
        if ag.isWorking { return (Theme.irisText, Theme.iris.opacity(0.14)) }
        if ag.isDone { return (Theme.okText, Theme.okText.opacity(0.12)) }
        return (Theme.text3, Theme.line)
    }

    var icon: String {
        guard let ag = agent else { return "point.3.connected.trianglepath.dotted" }
        if ag.isWaiting { return "exclamationmark.circle" }
        if ag.isDone { return "checkmark.circle" }
        return "point.3.connected.trianglepath.dotted"
    }

    var body: some View {
        if let ag = agent {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .opacity(ag.isWorking && pulse ? 0.45 : 1)
                Text("Agente · \(ag.rootStateLabel)")
                    .font(.system(size: 11))
            }
            .foregroundStyle(tone.fg)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(tone.bg))
            .overlay(Capsule().stroke(tone.fg.opacity(ag.isWorking && pulse ? 0.75 : 0.35), lineWidth: 1))
            .scaleEffect(ag.isWorking && pulse ? 1.03 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: ag.rootStateLabel)
            .help(ag.message ?? "Agent da raiz da trama, que coordena todos os repositórios")
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
            }
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
    var rank = 0
    var total = 1
    var sweep = 1.0

    var summary: String {
        guard let c = model.capsule, c.trama == selected.slug, c.exists else {
            return "a cápsula desta trama ainda não existe"
        }
        var parts = ["\(c.decisions.count) \(plural(c.decisions.count, "decisão", "decisões"))"]
        let open = c.openHandoffs.count
        if open > 0 { parts.append("\(open) \(plural(open, "handoff aberto", "handoffs abertos"))") }
        let suggested = c.openSuggestions.count
        if suggested > 0 { parts.append("\(suggested) \(plural(suggested, "repositório sugerido", "repositórios sugeridos"))") }
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
                LoomCell(type: .capsule, selected: t.slug == selected.slug, parked: t.isParked, rank: rank, total: total, sweep: sweep)
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
