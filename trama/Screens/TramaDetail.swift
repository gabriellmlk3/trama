import Foundation
import SwiftUI

let nameWidth: CGFloat = 168
let columnWidth: CGFloat = 52
let rowHeight: CGFloat = 84

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
            ZStack(alignment: .trailing) {
                VStack(alignment: .leading, spacing: 14) {
                    DetailBar(mode: mode, refreshing: refreshing) { refreshToken += 1 }
                        .padding(.trailing, 44)
                    TipCard(tips: [.capsule, .agents])
                    switch mode.wrappedValue {
                    case .loom:
                        LoomView(selected: trama)
                        LoomLegend(trama: trama)
                        CapsuleComposer(trama: trama)
                    case .git:
                        GitView(trama: trama, refreshToken: refreshToken, refreshing: $refreshing)
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 28)
                .padding(.top, 20)
                .padding(.bottom, mode.wrappedValue == .git ? 0 : 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.trailing, capsuleVisible ? 373 : 0)
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.line).frame(width: 1)
                    CapsulePanel(trama: trama)
                        .frame(width: 372)
                }
                .frame(width: 373)
                .offset(x: capsuleVisible ? 0 : 373)
                .allowsHitTesting(capsuleVisible)
                Button {
                    capsuleVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(capsuleVisible ? Theme.emberText : Theme.text2)
                }
                .buttonStyle(IconButton(size: 32))
                .help(capsuleVisible ? "Ocultar a cápsula" : "Mostrar a cápsula")
                .accessibilityLabel(capsuleVisible ? "Ocultar a cápsula" : "Mostrar a cápsula")
                .padding(.top, 20)
                .padding(.trailing, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .animation(.easeOut(duration: 0.22), value: capsuleVisible)
            .clipped()
        }
    }
}

struct TramaHeader: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    @State private var confirmingArchive = false
    @State private var confirmingRemoval = false
    @State private var pullRequestMode: PullRequestPlanner.Mode?
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
                    if model.isFocused(trama.slug) {
                        Chip(text: "em foco", color: Theme.emberText)
                            .help("As automações de caminhos apontam as cópias principais para esta trama (tela Automações)")
                    }
                    AutomationRunChip(trama: trama)
                    TramaAgentBadge(agent: model.agents(for: trama.slug).first(where: { $0.isRoot }))
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                AppMenu(width: 300) {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 32)
                        .contentShape(Rectangle())
                } content: {
                    MenuAction("Mostrar pasta no Finder") { Terminal.reveal(trama.path) }
                    MenuAction("Copiar nome da branch") { Terminal.copy(trama.branch) }
                    MenuAction("Abrir a trama no VS Code") { Task { await model.openInCode(trama.slug) } }
                    MenuAction("Abrir todos no editor") { Task { await model.openInEditor(trama.slug, repos: trama.repos) } }
                    if model.isFocused(trama.slug) {
                        MenuAction("Reaplicar o foco") { Task { await model.focus(trama.slug) } }
                        MenuAction("Tirar o foco") { Task { await model.clearFocus() } }
                    }
                    if let log = trama.automationLog {
                        MenuAction("Ver log das automações") { Terminal.openFile(log) }
                    }
                    MenuAction("Automações…") { model.screen = .automations }
                    if trama.context != nil || model.state?.context != nil {
                        MenuAction("Commitar cápsula no contexto") { Task { await model.sync(trama.slug) } }
                    }
                    MenuAction("Repositório de contexto desta trama…") {
                        if let folder = Terminal.choosePaths(multiple: false, title: "Repositório de contexto de \(trama.title)").first {
                            Task { await model.setTramaContext(trama.slug, folder) }
                        }
                    }
                    if trama.context != nil {
                        MenuAction("Usar o contexto padrão") { Task { await model.setTramaContext(trama.slug, nil) } }
                    }
                    MenuDivider()
                    if trama.isActive {
                        SubMenu("Trazer commits de outra trama", disabled: model.visibleTramas.count < 2) {
                            model.visibleTramas.filter { $0.slug != trama.slug }.map { other in
                                let shared = trama.repos.filter { other.repos.contains($0) }
                                return MenuAction(
                                    "\(other.title) · \(shared.isEmpty ? "sem repositório em comum" : model.aliases(shared).joined(separator: ", "))",
                                    disabled: shared.isEmpty
                                ) { mergeSource = other }
                            }
                        }
                    }
                    MenuAction("Arquivar trama…") { confirmingArchive = true }
                    MenuAction("Remover trama…", destructive: true) { confirmingRemoval = true }
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
                .help("Mais ações")

                if !model.isFocused(trama.slug) {
                    Button {
                        Task { await model.focus(trama.slug) }
                    } label: {
                        Label("Focar", systemImage: "scope")
                    }
                    .buttonStyle(GhostButton())
                    .help("Troca de trama: as automações “ao focar” rodam e os caminhos das cópias principais passam a apontar para esta trama (tela Automações)")
                }

                if trama.isParked {
                    Button {
                        model.resuming = trama
                    } label: {
                        Label("Retomar trama", systemImage: "play.fill")
                    }
                    .buttonStyle(EmberButton())
                } else {
                    Button {
                        pullRequestMode = .pullRequest
                    } label: {
                        Label(model.hasLivePullRequests(trama) ? "Atualizar PRs" : "Abrir PRs", systemImage: "arrow.up.right.circle")
                    }
                    .buttonStyle(GhostButton())
                    .help("Escolhe a branch de destino de cada repositório, envia as branches e abre (ou atualiza) os PRs, ligados entre si")
                    Button {
                        pullRequestMode = .merge
                    } label: {
                        Label("Mesclar direto", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(GhostButton())
                    .help("Mescla a branch da trama direto na branch de destino de cada repositório, sem abrir PR")
                    Button {
                        model.openClaudeInAll(trama)
                    } label: {
                        Label("Abrir agent", systemImage: "sparkle")
                    }
                    .buttonStyle(EmberButton())
                    .overlay(alignment: .topTrailing) {
                        if model.permissionCount(in: trama.slug) > 0 {
                            Dot(color: Theme.wait, halo: true)
                                .offset(x: 4, y: -4)
                        }
                    }
                    .help("Abre o Claude Code na trama: um agent com todos os repositórios, ou um por repositório (Ajustes)")
                }
            }
        }
        .padding(.horizontal, 28) 
        .padding(.top, 26)
        .padding(.bottom, 18)
        .appDialog(
            "Trazer “\(mergeSource?.title ?? "")” para cá?",
            isPresented: Binding(get: { mergeSource != nil }, set: { if !$0 { mergeSource = nil } }),
            message: mergeSource.map { "Faz merge da branch \($0.branch) em \(trama.branch), nos repositórios que as duas têm. Se algum worktree daqui tiver mudanças não commitadas ou o merge previr conflito, “Fazer merge” não mescla nada; “Mesclar e resolver conflitos” deixa o merge em andamento na aba Git." },
            actions: [
                DialogAction("Fazer merge") {
                    if let source = mergeSource { Task { await model.merge(source, into: trama) } }
                },
                DialogAction("Mesclar e resolver conflitos") {
                    if let source = mergeSource { Task { await model.merge(source, into: trama, allowConflicts: true) } }
                },
            ]
        )
        .sheet(item: $pullRequestMode) { mode in
            PullRequestSheet(trama: trama, mode: mode)
        }
        .appDialog(
            "Remover “\(trama.title)”?",
            isPresented: $confirmingRemoval,
            message: "A trama some do Trama e os worktrees são removidos. A cápsula continua no repositório de contexto. Se houver mudanças não commitadas, a remoção é recusada. Apagar as branches \(trama.branch) descarta commits que não estejam em outra branch.",
            actions: [
                DialogAction("Remover e manter as branches", role: .destructive) { Task { await model.remove(trama.slug, deleteBranches: false) } },
                DialogAction("Remover e apagar as branches locais", role: .destructive) { Task { await model.remove(trama.slug, deleteBranches: true) } },
            ]
        )
        .appDialog(
            "Arquivar “\(trama.title)”?",
            isPresented: $confirmingArchive,
            message: "Os worktrees são removidos; as branches \(trama.branch) continuam em cada repositório e a cápsula fica guardada. Se houver mudanças não commitadas, o arquivamento é recusado.",
            actions: [
                DialogAction("Arquivar", role: .destructive) { Task { await model.archive(trama.slug) } },
            ]
        )
    }
}

struct AutomationRunChip: View {
    let trama: LiveTrama

    var body: some View {
        if let state = trama.automation, state != AutomationRunState.done, let log = trama.automationLog {
            let running = state == AutomationRunState.running
            Button {
                Terminal.openFile(log)
            } label: {
                Chip(text: running ? "automações rodando…" : "automação falhou", color: running ? Theme.irisText : Theme.dangerText)
            }
            .buttonStyle(.plain)
            .help("Abrir o log das automações")
        }
    }
}
