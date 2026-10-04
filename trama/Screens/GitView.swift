import Foundation
import SwiftUI

enum DetailMode: String, CaseIterable, Identifiable {
    case loom = "Tear"
    case git = "Git"
    case agent = "Agent"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .loom: return "repositórios × tramas · cada ponto é um worktree vivo"
        case .git: return "onde cada worktree está, em qual branch e o que mudou"
        case .agent: return "conversa com o agent geral da trama · visual nativo"
        }
    }
}

struct DetailBar: View {
    @Binding var mode: DetailMode
    let refreshing: Bool
    let onRefresh: () -> Void
    @Namespace private var pill

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(mode.rawValue)
                .font(.system(size: 13, weight: .semibold))
            Text(mode.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
                .id(mode)
                .transition(.opacity)
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if mode == .git {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(IconButton(size: 32))
                    .help("Reler o Git agora")
                    .accessibilityLabel("Reler o Git")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                HStack(spacing: 2) {
                    ForEach(DetailMode.allCases) { m in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { mode = m }
                        } label: {
                            Text(m.rawValue)
                                .font(.system(size: 12, weight: mode == m ? .medium : .regular))
                                .foregroundStyle(mode == m ? Theme.text : Theme.faded)
                                .padding(.horizontal, 11)
                                .frame(height: 26)
                                .background {
                                    if mode == m {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Theme.surface2)
                                            .matchedGeometryEffect(id: "pill", in: pill)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line2, lineWidth: 1))
            }
        }
    }
}

private struct LoadKey: Equatable {
    var slug: String
    var repo: String
    var stamp: Int64
    var token: Int
    var compare: String?
}

private struct DiffKey: Equatable {
    var file: String?
    var loadedAt: Int64
    var signature: String
}

struct GitView: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let refreshToken: Int
    @Binding var refreshing: Bool

    @AppStorage("repoListVisible") private var repoListVisible = true
    @State private var selectedRepo: String?
    @State private var compares: [String: String] = [:]
    @State private var overview: GitOverview?
    @State private var overviewRepo: String?
    @State private var loadError: String?
    @State private var tab = GitTab.changes
    @State private var selectedFile: String?
    @State private var diff: [DiffLine] = []
    @State private var diffFile: String?
    @State private var committingAll = false

    var currentRepo: String? {
        if let s = selectedRepo, trama.repos.contains(s) { return s }
        return trama.status.first(where: { $0.primaryAgent?.isWaiting == true })?.repo
            ?? trama.status.first(where: { $0.changed > 0 })?.repo
            ?? trama.status.first?.repo
    }

    var outside: [RepoConfig] {
        model.repos.filter { !trama.repos.contains($0.name) }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 760
            Group {
                if wide {
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Color.clear.frame(width: 28, height: 28)
                                    Spacer(minLength: 0)
                                    commitAllButton
                                }
                                RepoList(trama: trama, outside: outside, selected: currentRepo, horizontal: false) { select($0) }
                            }
                            .frame(width: 272, alignment: .topLeading)
                            .frame(width: repoListVisible ? 272 : 0, alignment: .topLeading)
                            .opacity(repoListVisible ? 1 : 0)
                            .allowsHitTesting(repoListVisible)
                            .clipped()
                            .padding(.trailing, repoListVisible ? 26 : 0)
                            detail
                        }
                        Button {
                            repoListVisible.toggle()
                        } label: {
                            Image(systemName: "sidebar.left")
                                .foregroundStyle(repoListVisible ? Theme.text2 : Theme.emberText)
                        }
                        .buttonStyle(IconButton(size: 28))
                        .help(repoListVisible ? "Recolher a lista de repositórios" : "Mostrar a lista de repositórios")
                        .accessibilityLabel(repoListVisible ? "Recolher a lista de repositórios" : "Mostrar a lista de repositórios")
                    }
                    .animation(.spring(response: 0.36, dampingFraction: 0.86), value: repoListVisible)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        RepoList(trama: trama, outside: outside, selected: currentRepo, horizontal: true) { select($0) }
                        detail
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task(id: LoadKey(slug: trama.slug, repo: currentRepo ?? "", stamp: model.state?.generatedAt ?? 0, token: refreshToken, compare: currentRepo.flatMap { compares[$0] })) {
            await load()
        }
        .task(id: DiffKey(file: selectedFile, loadedAt: overview?.loadedAt ?? 0, signature: changeSignature)) {
            await loadDiff()
        }
        .sheet(isPresented: $committingAll) { CommitAllSheet(trama: trama) }
        .onChange(of: trama.slug) { _, _ in
            selectedRepo = nil
            overview = nil
            selectedFile = nil
            diff = []
        }
    }

    var commitAllButton: some View {
        Button {
            committingAll = true
        } label: {
            Label("Commitar todos", systemImage: "checkmark.circle")
        }
        .buttonStyle(GhostButton(compact: true))
        .disabled(!trama.status.contains(where: { $0.changed > 0 }))
        .help("Commita as mudanças de todos os repositórios de uma vez, com uma mensagem para cada um")
    }

    var changeSignature: String {
        overview?.changes.map { "\($0.path):\($0.added):\($0.removed)" }.joined(separator: "|") ?? ""
    }

    @ViewBuilder var detail: some View {
        if let name = currentRepo, let status = trama.status(for: name), let repo = model.repo(name) {
            BlurScrollView {
                GitRepoDetail(
                    trama: trama,
                    repo: repo,
                    status: status,
                    overview: overviewRepo == name ? overview : nil,
                    compare: compares[name],
                    onCompare: { compares[name] = $0 },
                    error: loadError,
                    tab: $tab,
                    selectedFile: $selectedFile,
                    diff: diffFile == selectedFile ? diff : []
                )
                .padding(.bottom, 28)
                .id(name)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            Text("Esta trama ainda não tem repositórios.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func select(_ name: String) {
        guard name != currentRepo else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            selectedRepo = name
            selectedFile = nil
            diff = []
            tab = .changes
        }
    }

    func load() async {
        guard let name = currentRepo else { return }
        let slug = trama.slug
        let compare = compares[name]
        refreshing = true
        defer { refreshing = false }
        do {
            let fresh = try await Core.run { try $0.gitOverview(slug, repo: name, compare: compare) }
            guard name == currentRepo else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                overview = fresh
                overviewRepo = name
                loadError = nil
                if selectedFile == nil || !fresh.changes.contains(where: { $0.path == selectedFile }) {
                    selectedFile = fresh.changes.first?.path
                }
            }
        } catch {
            loadError = errorMessage(error)
        }
    }

    func loadDiff() async {
        guard let name = currentRepo, let file = selectedFile,
              let change = overview?.changes.first(where: { $0.path == file }) else {
            diff = []
            diffFile = nil
            return
        }
        let slug = trama.slug
        if let lines = try? await Core.run({ try $0.fileDiff(slug, repo: name, change: change) }), file == selectedFile {
            withAnimation(.easeOut(duration: 0.2)) {
                diff = lines
                diffFile = file
            }
        }
    }
}

struct RepoList: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let outside: [RepoConfig]
    let selected: String?
    let horizontal: Bool
    let onSelect: (String) -> Void

    var body: some View {
        if horizontal {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(trama.status) { s in
                        RepoCard(trama: trama, status: s, selected: s.repo == selected) { onSelect(s.repo) }
                            .frame(width: 260)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                BlurScrollView(height: 4) {
                    VStack(alignment: .leading, spacing: 10) {
                        CollapsibleSection(
                            title: "Nesta trama · \(trama.status.count)",
                            collapseLabel: "repositórios desta trama",
                            storageKey: "insideExpanded",
                            trailing: {
                                Text("base \(trama.base ?? trama.status.first?.base ?? "main")")
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.faded)
                            }
                        ) {
                            ForEach(trama.status) { s in
                                RepoCard(trama: trama, status: s, selected: s.repo == selected) { onSelect(s.repo) }
                            }
                        }
                        if !outside.isEmpty {
                            CollapsibleSection(
                                title: "Fora desta trama · \(outside.count)",
                                collapseLabel: "repositórios fora desta trama",
                                storageKey: "outsideExpanded"
                            ) {
                                ForEach(outside) { r in
                                    OutsideRow(trama: trama, repo: r)
                                }
                            }
                            .padding(.top, 14)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(Theme.iris)
                        .padding(.top, 1)
                    Text("Cada repositório mantém a cópia principal na base, intacta. A trama só mexe nos worktrees acima.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }
}

struct AgentBadge: View {
    let agent: Agent?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        if let ag = agent {
            HStack(spacing: 6) {
                if ag.isWorking {
                    Circle().fill(Theme.iris).frame(width: 7, height: 7)
                        .background(
                            Circle().fill(Theme.iris.opacity(pulse ? 0 : 0.35))
                                .frame(width: 7, height: 7)
                                .scaleEffect(pulse ? 2.4 : 1)
                        )
                    Text("escrevendo").foregroundStyle(Theme.irisText)
                } else if ag.isWaiting {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.waitText)
                    Text("aguardando você").foregroundStyle(Theme.waitText)
                } else if ag.isDone {
                    Image(systemName: "checkmark").foregroundStyle(Theme.okText)
                    Text("concluiu").foregroundStyle(Theme.okText)
                } else {
                    Circle().fill(Theme.faded).frame(width: 6, height: 6)
                    Text("aberto").foregroundStyle(Theme.text3)
                }
            }
            .font(.system(size: 11.5))
            .lineLimit(1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
        }
    }
}

struct RepoCard: View {
    let trama: LiveTrama
    let status: RepoStatus
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var detached: Bool { status.exists && status.branch.isEmpty }

    var syncText: String {
        if status.behind == 0 { return "nada a atualizar" }
        if status.conflict == "conflito" { return "conflito previsto" }
        if status.conflict == "limpo" { return "rebase limpo" }
        return "base andou"
    }

    var syncColor: Color {
        if status.behind == 0 { return Theme.faded }
        return status.conflict == "conflito" ? Theme.waitText : Theme.okText
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(status.repo)
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    AgentBadge(agent: status.primaryAgent)
                }
                if detached {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 10.5))
                        Text("HEAD solto · \(status.lastCommit?.hash ?? "")")
                    }
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.waitText)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.wait.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.wait.opacity(0.45), lineWidth: 1))
                } else if status.exists {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                        Text(status.branch).lineLimit(1).truncationMode(.middle)
                    }
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.emberLight)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.ember.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.ember.opacity(0.35), lineWidth: 1))
                }
                if status.exists {
                    HStack(spacing: 8) {
                        Text("↑\(status.ahead)").foregroundStyle(Theme.text3)
                        Text("↓\(status.behind)").foregroundStyle(status.behind > 0 ? Theme.wait : Theme.text3)
                        Text(status.changed == 0 ? "limpo" : "\(status.changed) \(plural(status.changed, "alterado", "alterados"))")
                        Text("·")
                        Text(syncText).foregroundStyle(syncColor)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
                } else {
                    Text(status.error ?? "worktree não encontrado")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.waitText)
                }
                if detached {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 11)).padding(.top, 1)
                        Text("Fora da branch da trama. Commits feitos aqui podem se perder.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.waitText)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Theme.surface2 : (hovering ? Theme.surface : Theme.loom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Theme.ember.opacity(0.55) : Theme.line, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Theme.ember).frame(width: 3, height: 34)
                        .shadow(color: Theme.ember.opacity(0.5), radius: 5)
                        .offset(x: -1)
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selected)
    }
}

struct OutsideRow: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let repo: RepoConfig

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repo.name)
                    .font(Theme.mono(12.5))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                Text("o fio passa por baixo")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
            }
            Spacer(minLength: 6)
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
        .padding(.leading, 13)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.thread).frame(width: 1)
        }
    }
}
