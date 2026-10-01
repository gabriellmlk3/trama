import Foundation
import SwiftUI

enum GitTab: Hashable {
    case changes, commits, baseMoved
}

struct GitCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.loom))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }
}

struct GitRepoDetail: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let repo: RepoConfig
    let status: RepoStatus
    let overview: GitOverview?
    let error: String?
    @Binding var tab: GitTab
    @Binding var selectedFile: String?
    let diff: [DiffLine]
    @Namespace private var tabPill

    var path: String { model.worktreePath(trama, repo.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chips
            ConflictsPanel(repo: repo.name, worktree: path)
            if let o = overview {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        BranchThread(overview: o, status: status)
                        WorktreesCard(overview: o, repo: repo, trama: trama)
                            .frame(width: 300)
                    }
                    VStack(spacing: 14) {
                        BranchThread(overview: o, status: status)
                        WorktreesCard(overview: o, repo: repo, trama: trama)
                    }
                }
                tabs(o)
                tabContent(o)
                    .id(tab)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            } else if let error {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.waitText)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("lendo o Git…").font(.system(size: 12.5)).foregroundStyle(Theme.faded)
                }
                .padding(.top, 20)
            }
        }
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(repo.name)
                        .font(Theme.mono(21, weight: .medium))
                    if let label = repo.label, !label.isEmpty {
                        Chip(text: label)
                    }
                }
                HStack(spacing: 7) {
                    Image(systemName: "folder").font(.system(size: 11))
                    Text(Paths.abbreviate(path))
                        .font(Theme.mono(12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .foregroundStyle(Theme.faded)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button {
                    model.openClaude(path: path, repo: repo.name)
                } label: {
                    Label("Agente", systemImage: "sparkles")
                }
                .buttonStyle(GhostButton(compact: true))
                .help("Abre o Claude neste worktree (conforme Ajustes)")
                Button {
                    model.terminals.open(path: path, command: nil, title: "\(repo.name) · \(trama.slug)")
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .buttonStyle(GhostButton(compact: true))
                Button {
                    Task { await model.openInEditor(trama.slug, repos: [repo.name]) }
                } label: {
                    Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(GhostButton(compact: true))
                .help("Abre este worktree no editor do repositório")
                Button {
                    Terminal.reveal(path)
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(GhostButton(compact: true))
                Button {
                    Terminal.copy(path)
                    model.showNotice("Caminho copiado")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Copiar caminho")
                .accessibilityLabel("Copiar caminho")
            }
        }
    }

    var chips: some View {
        HStack(spacing: 8) {
            if status.branch.isEmpty {
                ToneChip(icon: "exclamationmark.circle", text: "HEAD solto · \(status.lastCommit?.hash ?? "")", tone: .wait)
            } else {
                ToneChip(icon: "arrow.triangle.branch", text: status.branch, tone: .ember)
                if status.branch == trama.branch {
                    ToneChip(icon: "checkmark", text: "é a branch da trama", tone: .ok)
                } else {
                    ToneChip(icon: "exclamationmark.circle", text: "não é a branch da trama", tone: .wait)
                }
                if let o = overview {
                    if !o.hasOrigin {
                        ToneChip(icon: nil, text: "sem origin", tone: .plain)
                    } else if o.pushed {
                        ToneChip(icon: nil, text: "enviada à origin", tone: .plain)
                    } else {
                        ToneChip(icon: nil, text: "só local · não enviada à origin", tone: .plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.2), value: overview?.loadedAt)
    }

    func tabs(_ o: GitOverview) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                tabButton("Mudanças", count: o.changes.count, value: .changes)
                tabButton("Commits", count: o.aheadCount, value: .commits)
                tabButton("Base andou", count: o.behindCount, value: .baseMoved)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2, lineWidth: 1))
            Spacer(minLength: 8)
            syncChip
        }
    }

    @ViewBuilder var syncChip: some View {
        if status.behind == 0 {
            ToneChip(icon: "checkmark", text: "em dia com \(status.base)", tone: .ok)
        } else if status.conflict == "conflito" {
            ToneChip(icon: "exclamationmark.triangle", text: "rebase em origin/\(status.base): conflito", tone: .wait)
        } else {
            ToneChip(icon: "checkmark", text: "rebase em origin/\(status.base): limpo", tone: .ok)
        }
    }

    func tabButton(_ title: String, count: Int, value: GitTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { tab = value }
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: tab == value ? .medium : .regular))
                Text("\(count)")
                    .font(Theme.mono(10.5))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(Capsule().fill(tab == value ? Theme.ember.opacity(0.22) : Theme.surface2))
                    .foregroundStyle(tab == value ? Theme.emberText : Theme.faded)
            }
            .foregroundStyle(tab == value ? Theme.text : Theme.faded)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                if tab == value {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.surface2)
                        .matchedGeometryEffect(id: "tab", in: tabPill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder func tabContent(_ o: GitOverview) -> some View {
        switch tab {
        case .changes:
            ChangesPane(trama: trama, repo: repo.name, merging: o.merging, changes: o.changes, selectedFile: $selectedFile, diff: diff, path: path, status: status)
        case .commits:
            CommitsPane(commits: o.ahead, total: o.aheadCount, tint: Theme.emberLight,
                        empty: "Nenhum commit à frente de \(o.base) ainda.")
        case .baseMoved:
            CommitsPane(commits: o.behind, total: o.behindCount, tint: Theme.wait,
                        empty: "A base não andou desde que esta branch saiu.")
        }
    }
}

struct ToneChip: View {
    enum Tone { case ember, ok, wait, plain }
    let icon: String?
    let text: String
    let tone: Tone

    var color: Color {
        switch tone {
        case .ember: return Theme.emberLight
        case .ok: return Theme.okText
        case .wait: return Theme.waitText
        case .plain: return Theme.text3
        }
    }

    var tint: Color {
        switch tone {
        case .ember: return Theme.ember
        case .ok: return Theme.ok
        case .wait: return Theme.wait
        case .plain: return Theme.faded
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(text).lineLimit(1).truncationMode(.middle)
        }
        .font(tone == .plain ? .system(size: 11.5) : Theme.mono(11.5))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(tone == .plain ? 0.06 : 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(tone == .plain ? 0.3 : 0.4), lineWidth: 1))
    }
}

struct WorktreesCard: View {
    @EnvironmentObject var model: AppModel
    let overview: GitOverview
    let repo: RepoConfig
    let trama: LiveTrama
    @State private var pending: (from: WorktreeSummary, into: WorktreeSummary)?
    @State private var resolvingIn: WorktreeSummary?

    func title(_ w: WorktreeSummary) -> String {
        if w.isPrimary { return "Cópia principal" }
        if Paths.real(w.path) == Paths.real(model.worktreePath(trama, repo.name)) { return "Esta trama" }
        if let t = model.state?.tramas.first(where: { w.path.hasPrefix($0.path + "/") }) { return t.title }
        return URL(fileURLWithPath: w.path).lastPathComponent
    }

    func current(_ w: WorktreeSummary) -> Bool {
        Paths.real(w.path) == Paths.real(model.worktreePath(trama, repo.name))
    }

    func trailing(_ w: WorktreeSummary) -> String {
        if w.changed > 0 { return "\(w.changed) \(plural(w.changed, "alterado", "alterados"))" }
        if w.ahead > 0 { return "↑\(w.ahead)" }
        return w.isPrimary ? "intacta" : "limpo"
    }

    var body: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Worktrees de \(repo.name)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(overview.worktrees.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                }
                VStack(spacing: 4) {
                    ForEach(Array(overview.worktrees.enumerated()), id: \.element.id) { i, w in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(w))
                                    .font(.system(size: 12.5, weight: current(w) ? .medium : .regular))
                                    .foregroundStyle(current(w) ? Theme.text : Theme.text2)
                                    .lineLimit(1)
                                Text(w.branch.isEmpty ? "HEAD solto" : w.branch)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.faded)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 6)
                            if w.conflicts > 0 {
                                Button {
                                    resolvingIn = w
                                } label: {
                                    Label("\(w.conflicts) em conflito", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.waitText)
                                }
                                .buttonStyle(.plain)
                                .help("Resolver os conflitos deste worktree")
                            } else {
                                Text(trailing(w))
                                    .font(.system(size: 12))
                                    .foregroundStyle(w.changed > 0 ? Theme.text3 : Theme.faded)
                            }
                            if !current(w), !w.branch.isEmpty, let mine = overview.worktrees.first(where: current), !mine.branch.isEmpty {
                                Menu {
                                    Button("Mesclar \(mine.branch) em \(w.branch)") { pending = (mine, w) }
                                    Button("Trazer \(w.branch) para \(mine.branch)") { pending = (w, mine) }
                                } label: {
                                    Image(systemName: "arrow.triangle.merge")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.text2)
                                        .frame(width: 26, height: 26)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
                                        .contentShape(Rectangle())
                                }
                                .menuStyle(.button)
                                .buttonStyle(.plain)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .help("Fazer merge entre este worktree e \(title(w))")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(current(w) ? Theme.surface2 : Color.clear))
                        .overlay(alignment: .leading) {
                            if current(w) {
                                Capsule().fill(Theme.ember).frame(width: 2.5, height: 24)
                                    .shadow(color: Theme.ember.opacity(0.5), radius: 4)
                            }
                        }
                        .transition(.opacity.combined(with: .offset(x: 8)))
                        .animation(.easeOut(duration: 0.28).delay(Double(i) * 0.05), value: overview.worktrees.count)
                    }
                }
            }
            .padding(14)
        }
        .sheet(item: $resolvingIn) { w in
            ConflictsSheet(repo: repo.name, worktree: w.path, title: title(w))
        }
        .alert("Fazer merge?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Fazer merge") {
                if let p = pending {
                    Task { await model.mergeWorktree(repo.name, from: p.from.path, into: p.into.path, label: title(p.into)) }
                }
                pending = nil
            }
            Button("Mesclar e resolver conflitos") {
                if let p = pending {
                    Task { await model.mergeWorktree(repo.name, from: p.from.path, into: p.into.path, label: title(p.into), allowConflicts: true) }
                }
                pending = nil
            }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: {
            if let p = pending {
                Text("Mescla \(p.from.branch) em \(p.into.branch) (\(title(p.into))). Se o merge previr conflito, “Fazer merge” não mescla nada; “Mesclar e resolver conflitos” deixa o merge em andamento para você resolver aqui." + (p.into.changed > 0 ? " Esse worktree tem \(p.into.changed) \(plural(p.into.changed, "alteração", "alterações")) não commitada(s): o Git só recusa se elas tocarem os mesmos arquivos." : ""))
            }
        }
    }
}

struct ConflictsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repo: String
    let worktree: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Conflitos em \(title)")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Fechar") { dismiss() }
                    .buttonStyle(GhostButton(compact: true))
                    .keyboardShortcut(.cancelAction)
            }
            ConflictsPanel(repo: repo, worktree: worktree)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 280)
        .background(Theme.background)
    }
}
