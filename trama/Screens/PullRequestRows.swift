import Foundation
import SwiftUI

struct SummaryStat: View {
    let value: Int
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(Theme.mono(12.5))
                .foregroundStyle(color)
            Text(text)
        }
    }
}

struct TargetButton: View {
    let name: String
    var warning = false
    var open = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faded)
                Text(name)
                    .font(Theme.mono(12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faded)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(open ? Theme.ember.opacity(0.08) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    var border: Color {
        if warning { return Theme.wait.opacity(0.55) }
        if open { return Theme.ember.opacity(0.6) }
        return Theme.line2
    }
}

struct TonePill: View {
    let text: String
    var icon: String?
    var color: Color = Theme.text3
    var fill: Color = Theme.surface
    var stroke: Color = Theme.line2

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11.5))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(stroke, lineWidth: 1))
    }
}

struct PullRequestRowView: View {
    @EnvironmentObject var model: AppModel
    let row: PullRequestPlanRow
    @ObservedObject var planner: PullRequestPlanner
    @State private var picking = false

    var included: Bool { planner.isIncluded(row) }
    var blocked: Bool { planner.mode == .merge ? !planner.canMerge(row) : row.action == .blocked }
    var canPick: Bool { row.blocker != .noWorktree && row.blocker != .noRemote }

    var missingTarget: String? {
        if let wanted = planner.missing[row.repo] { return wanted }
        return row.blocker == .missingTarget ? row.target : nil
    }

    var body: some View {
        HStack(spacing: Column.gap) {
            checkbox
            VStack(alignment: .leading, spacing: 3) {
                Text(row.repo)
                    .font(Theme.mono(13))
                    .lineLimit(1)
                Text(included ? "\(row.order)º a mesclar" : "fora desta rodada")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
                Text(row.provider.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            .frame(width: Column.repo, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                TargetButton(name: row.target, warning: missingTarget != nil, open: picking, disabled: !canPick) { picking.toggle() }
                    .popover(isPresented: $picking, arrowEdge: .bottom) {
                        BranchPicker(
                            options: planner.branches(for: row.repo),
                            selected: row.target,
                            totalRepos: planner.repoCount,
                            scopedRepo: row.repo,
                            defaultNames: planner.defaultNames,
                            planner: planner
                        ) { name in
                            planner.choose(name, for: row.repo)
                            picking = false
                        }
                    }
                if let wanted = missingTarget {
                    Text("\(wanted) não existe neste repo")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.waitText)
                    Button {
                        Task { await planner.createMissing(wanted, repos: [row.repo]) }
                    } label: {
                        HStack(spacing: 6) {
                            if planner.creatingBranches.contains(row.repo) {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                            }
                            Text("Criar neste repo")
                        }
                    }
                    .buttonStyle(GhostButton(compact: true))
                    .disabled(planner.creatingBranches.contains(row.repo))
                }
            }
            .frame(width: Column.target, alignment: .leading)
            commits
                .frame(width: Column.commits, alignment: .leading)
            conflict
                .frame(width: Column.conflict, alignment: .leading)
            status
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 72)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
        .opacity(included ? 1 : 0.55)
    }

    var checkbox: some View {
        Button {
            planner.toggle(row.repo)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(included ? Theme.ember : Color.clear)
                RoundedRectangle(cornerRadius: 6).stroke(included ? Theme.ember : Theme.thread, lineWidth: 1)
                if included {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.emberDark)
                }
            }
            .frame(width: Column.check, height: Column.check)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .accessibilityLabel("Incluir \(row.repo)")
    }

    var commits: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("↑\(row.ahead)")
                .font(Theme.mono(13))
                .foregroundStyle(row.ahead > 0 ? Theme.text : Theme.faded)
            Text(plural(row.ahead, "commit", "commits"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
        }
    }

    @ViewBuilder
    var conflict: some View {
        if let files = row.conflictFiles {
            if files.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label("nenhum", systemImage: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.okText)
                    Text("contra o destino")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label("\(files.count) \(plural(files.count, "arquivo", "arquivos"))", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.waitText)
                    Text(files.count == 1 ? Paths.name(files[0]) : files.prefix(2).map { Paths.name($0) }.joined(separator: ", ") + "…")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(files.joined(separator: "\n"))
                }
            }
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
        }
    }

    @ViewBuilder
    var status: some View {
        let number = row.existing?.number ?? 0
        VStack(alignment: .leading, spacing: 5) {
            if planner.mode == .merge {
                if planner.canMerge(row) {
                    TonePill(text: "mesclar direto", icon: "arrow.triangle.merge", color: Theme.emberLight, fill: Theme.ember.opacity(0.10), stroke: Theme.ember.opacity(0.32))
                    note("push em \(row.target)", mono: true)
                } else if row.hasConflict {
                    TonePill(text: "conflito previsto", icon: "exclamationmark.circle", color: Theme.waitText)
                    note("resolva antes de mesclar")
                } else {
                    TonePill(text: row.ahead == 0 && row.blocker == nil ? "nada a mesclar" : blockedTitle)
                    note(row.ahead == 0 && row.blocker == nil ? "0 commits novos" : blockedNote)
                }
            } else {
            switch row.action {
            case .create:
                TonePill(text: "novo PR", icon: "plus", color: Theme.emberLight, fill: Theme.ember.opacity(0.10), stroke: Theme.ember.opacity(0.32))
                note("ainda sem PR")
            case .retarget:
                TonePill(text: "redirecionar PR #\(number)", icon: "arrow.right", color: Theme.irisText, fill: Theme.iris.opacity(0.10), stroke: Theme.iris.opacity(0.34))
                note("\(row.existing?.base ?? "") → \(row.target)", mono: true)
            case .update:
                TonePill(text: "atualizar PR #\(number)", icon: "arrow.clockwise", color: Theme.okText, fill: Theme.ok.opacity(0.10), stroke: Theme.ok.opacity(0.30))
                note("já aponta para \(row.target)")
            case .manual:
                TonePill(text: "abrir no navegador", icon: "arrow.up.right.square", color: Theme.text2)
                note(row.missingTool.map { "sem o \($0) instalado" } ?? "este provedor abre pelo link")
            case .blocked:
                TonePill(text: blockedTitle)
                if row.blocker == .merged || row.blocker == .closed {
                    Button("Descartar") {
                        planner.discard(row.repo)
                        Task { await model.forgetPullRequests(planner.slug, repos: [row.repo]) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.emberLight)
                    .help("Esquece o PR #\(number) desta trama, para um novo poder ser aberto")
                } else {
                    note(blockedNote)
                }
            }
            }
        }
    }

    func note(_ text: String, mono: Bool = false) -> some View {
        Text(text)
            .font(mono ? Theme.mono(11) : .system(size: 11.5))
            .foregroundStyle(Theme.faded)
            .lineLimit(1)
    }

    var blockedTitle: String {
        let number = row.existing?.number ?? 0
        switch row.blocker {
        case .nothingAhead: return "nada a subir"
        case .merged: return "PR #\(number) mesclado"
        case .closed: return "PR #\(number) fechado"
        case .noWorktree: return "sem worktree"
        case .noRemote: return "sem remoto"
        case .missingTarget: return "destino ausente"
        case nil: return ""
        }
    }

    var blockedNote: String {
        switch row.blocker {
        case .nothingAhead: return "0 commits novos"
        case .merged, .closed: return "não mexo nele"
        case .noWorktree: return "worktree não encontrado"
        case .noRemote: return "não tem origin"
        case .missingTarget: return "escolha outra branch"
        case nil: return ""
        }
    }
}

struct BranchPicker: View {
    let options: [RemoteBranchOption]
    let selected: String?
    let totalRepos: Int
    let scopedRepo: String?
    let defaultNames: Set<String>
    @ObservedObject var planner: PullRequestPlanner
    let onPick: (String) -> Void
    @State private var query = ""
    @State private var mode = Mode.list
    @State private var text = ""
    @State private var source = ""
    @State private var working = false
    @State private var problem: String?

    enum Mode: Equatable {
        case list
        case create
        case rename(String)
        case delete(String)
    }

    var visible: [RemoteBranchOption] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var branches: [RemoteBranchOption] {
        let plain = visible.filter { !$0.isTrama }
        return plain.filter { defaultNames.contains($0.name) } + plain.filter { !defaultNames.contains($0.name) }
    }

    var stacks: [RemoteBranchOption] { visible.filter { $0.isTrama } }

    var body: some View {
        Group {
            switch mode {
            case .list: listBody
            case .create: form(title: "Nova branch", field: "Nome da branch", action: "Criar", sourcePicker: true)
            case .rename(let name): form(title: "Renomear \(name)", field: "Novo nome", action: "Renomear", sourcePicker: false)
            case .delete(let name): confirmation(name)
            }
        }
        .padding(8)
        .frame(width: 372)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }

    var listBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                TextField("Filtrar branches", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !branches.isEmpty {
                        SectionLabel(text: "Branches remotas")
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(branches) { option in
                            item(option)
                        }
                    }
                    if !stacks.isEmpty {
                        SectionLabel(text: "Outras tramas · empilhar")
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        ForEach(stacks) { option in
                            item(option)
                        }
                    }
                    if branches.isEmpty && stacks.isEmpty {
                        Text("Nenhuma branch encontrada")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faded)
                            .padding(10)
                    }
                }
            }
            .frame(maxHeight: 300)
            if scopedRepo == nil {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.waitText)
                    Text("Repositórios que não têm a branch escolhida ficam com o destino próprio.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
            Button {
                text = query.trimmingCharacters(in: .whitespaces)
                source = selected ?? options.first?.name ?? ""
                problem = nil
                mode = .create
            } label: {
                Label("Nova branch…", systemImage: "plus")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.emberLight)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    func form(title: String, field: String, action: String, sourcePicker: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            TextField(field, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.mono(12.5))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                .onSubmit(submitForm)
            if sourcePicker {
                HStack(spacing: 8) {
                    Text("a partir de")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                    AppPicker(selection: $source, options: options.map { (label: $0.name, value: $0.name) }, width: 240, mono: true)
                }
            }
            scopeNote
            if let problem {
                Text(problem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.waitText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Voltar") { mode = .list }
                    .buttonStyle(GhostButton())
                    .disabled(working)
                Button(action: submitForm) {
                    HStack(spacing: 8) {
                        if working { ProgressView().controlSize(.small) }
                        Text(action)
                    }
                }
                .buttonStyle(EmberButton())
                .disabled(working || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
    }

    func confirmation(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Excluir \(name)?")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("A branch é removida do remoto. PRs abertos que apontam para ela serão fechados pelo provedor.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
                .fixedSize(horizontal: false, vertical: true)
            scopeNote
            if let problem {
                Text(problem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.waitText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Voltar") { mode = .list }
                    .buttonStyle(GhostButton())
                    .disabled(working)
                Button(action: submitForm) {
                    HStack(spacing: 8) {
                        if working { ProgressView().controlSize(.small) }
                        Text("Excluir")
                    }
                }
                .buttonStyle(EmberButton())
                .disabled(working)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    var scopeNote: some View {
        if let scopedRepo {
            Text("Só em \(scopedRepo).")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
        } else {
            Text("Em todos os repositórios que têm a branch de origem.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
        }
    }

    func submitForm() {
        guard !working else { return }
        let value = text.trimmingCharacters(in: .whitespaces)
        let current = mode
        let scope = scopedRepo
        let from = source
        working = true
        problem = nil
        Task {
            let failure: String?
            switch current {
            case .list: failure = nil
            case .create: failure = await planner.createBranch(value, from: from, scope: scope)
            case .rename(let old): failure = await planner.renameBranch(old, to: value, scope: scope)
            case .delete(let name): failure = await planner.deleteBranch(name, scope: scope)
            }
            working = false
            problem = failure
            guard failure == nil else { return }
            if current == .create {
                onPick(value)
            } else {
                mode = .list
            }
        }
    }

    func item(_ option: RemoteBranchOption) -> some View {
        HStack(spacing: 2) {
            pickButton(option)
            if !defaultNames.contains(option.name) {
                AppMenu(width: 180) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                } content: {
                    MenuAction("Renomear…") {
                        text = option.name
                        problem = nil
                        mode = .rename(option.name)
                    }
                    MenuAction("Excluir…", destructive: true) {
                        problem = nil
                        mode = .delete(option.name)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
    }

    func pickButton(_ option: RemoteBranchOption) -> some View {
        let isSelected = option.name == selected
        return Button {
            onPick(option.name)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 14)
                Image(systemName: option.isTrama ? "square.stack.3d.up" : "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faded)
                Text(option.name)
                    .font(Theme.mono(12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if defaultNames.contains(option.name) {
                    Chip(text: "padrão")
                }
                Spacer(minLength: 8)
                if scopedRepo == nil {
                    Text("\(option.repos.count) de \(totalRepos) \(plural(totalRepos, "repo", "repos"))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Theme.surface2 : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
