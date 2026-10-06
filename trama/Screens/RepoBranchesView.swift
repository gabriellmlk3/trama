import Foundation
import SwiftUI

struct BranchesPane: View {
    @EnvironmentObject var model: AppModel
    let repo: String
    let state: RepoBrowserState
    let openLabel: (String) -> String
    let run: GitRunner
    let onNewBranch: (String?) -> Void

    @State private var query = ""
    @State private var deleting: BranchInfo?
    @FocusState private var searchFocused: Bool

    func matching(_ list: [BranchInfo]) -> [BranchInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let locals = matching(state.localBranches)
        let remotes = matching(state.remoteBranches)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                searchField
                Button {
                    onNewBranch(nil)
                } label: {
                    Label("Nova branch", systemImage: "plus")
                }
                .buttonStyle(GhostButton(compact: true))
            }
            GitCard {
                LazyVStack(alignment: .leading, spacing: 0) {
                    group("Locais", locals)
                    group("Remotas", remotes)
                    if locals.isEmpty && remotes.isEmpty {
                        Text(query.isEmpty ? "Nenhuma branch." : "Nenhuma branch com “\(query)”.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.faded)
                            .padding(18)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .appDialog(
            { "Apagar a branch \($0.name)?" },
            item: $deleting,
            message: { _ in "Só apaga se os commits dela já estiverem em outra branch. A branch no remoto não é tocada." },
            actions: { branch in
                [DialogAction("Apagar", role: .destructive) {
                    let repo = repo
                    let name = branch.name
                    run { try $0.deleteBranch(repo, name: name) }
                }]
            }
        )
    }

    var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
            TextField("Buscar branch", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(searchFocused ? Theme.ember.opacity(0.6) : Theme.line2, lineWidth: 1))
    }

    @ViewBuilder
    func group(_ title: String, _ list: [BranchInfo]) -> some View {
        if !list.isEmpty {
            HStack(spacing: 6) {
                SectionLabel(text: title)
                Text("\(list.count)")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.thread)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            ForEach(list) { branch in
                RepoBranchRow(
                    branch: branch,
                    openLabel: branch.openAt.map(openLabel),
                    busy: model.busy,
                    onSwitch: { switchTo(branch) },
                    onNewBranch: { onNewBranch(branch.name) },
                    onDelete: branch.remote || branch.current || branch.openAt != nil ? nil : { deleting = branch }
                )
            }
        }
    }

    func switchTo(_ branch: BranchInfo) {
        let repo = repo
        let checkout = state.checkout
        let name = branch.name
        let remote = branch.remote
        run { try $0.switchBranch(repo, checkout: checkout, branch: name, remote: remote) }
    }
}

private struct RepoBranchRow: View {
    let branch: BranchInfo
    let openLabel: String?
    let busy: Bool
    let onSwitch: () -> Void
    let onNewBranch: () -> Void
    let onDelete: (() -> Void)?
    @State private var hovering = false

    var canSwitch: Bool { !branch.current && branch.openAt == nil && !busy }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: branch.remote ? "cloud" : "laptopcomputer")
                .font(.system(size: 11))
                .foregroundStyle(branch.current ? Theme.ember : Theme.faded)
                .frame(width: 16)
            Text(branch.name)
                .font(Theme.mono(12.5, weight: branch.current ? .semibold : .regular))
                .foregroundStyle(branch.current ? Theme.text : Theme.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if branch.current {
                ToneChip(icon: "checkmark", text: "atual", tone: .ember)
            }
            if let openLabel {
                ToneChip(icon: "square.stack.3d.up", text: "aberta em \(openLabel)", tone: .plain)
                    .help("Esta branch está aberta em outro checkout; o git não deixa a mesma branch em dois lugares")
            }
            if branch.upstreamGone {
                ToneChip(icon: "cloud.slash", text: "remota apagada", tone: .wait)
            } else if branch.ahead > 0 || branch.behind > 0 {
                SyncCounts(ahead: branch.ahead, behind: branch.behind)
                    .help("Em relação a \(branch.upstream ?? "")")
            }
            Text(branch.subject)
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(relativeTime(branch.timestamp))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
                .lineLimit(1)
                .fixedSize()
            Button("Trocar", action: onSwitch)
                .buttonStyle(GhostButton(compact: true))
                .disabled(!canSwitch)
                .opacity(hovering && canSwitch ? 1 : 0)
                .help(branch.remote ? "Cria a branch local acompanhando \(branch.name) e troca para ela" : "Troca este checkout para \(branch.name)")
            AppMenu(width: 240) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            } content: {
                MenuAction(branch.remote ? "Trocar (cria a local)" : "Trocar para esta branch", systemImage: "arrow.right.circle", disabled: !canSwitch, handler: onSwitch)
                MenuAction("Nova branch a partir daqui…", systemImage: "plus", handler: onNewBranch)
                MenuAction("Copiar nome", systemImage: "doc.on.doc") { Terminal.copy(branch.remote ? branch.localName : branch.name) }
                if let onDelete {
                    MenuDivider()
                    MenuAction("Apagar…", systemImage: "trash", destructive: true, handler: onDelete)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mais ações da branch")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(hovering ? Theme.surface : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if canSwitch { onSwitch() } }
    }
}

struct StashPane: View {
    @EnvironmentObject var model: AppModel
    let repo: String
    let state: RepoBrowserState
    let run: GitRunner

    @State private var message = ""
    @State private var dropping: StashEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GitCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        TextField("Descrição do stash (opcional)", text: $message)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                            .onSubmit(save)
                        Button(action: save) {
                            Label("Guardar \(state.changes.count) \(plural(state.changes.count, "mudança", "mudanças"))", systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(EmberButton(compact: true))
                        .disabled(state.changes.isEmpty || model.busy || state.merging)
                        .opacity(state.changes.isEmpty ? 0.45 : 1)
                    }
                    Text("Guarda tudo o que mudou, inclusive arquivos novos, e deixa o checkout limpo. Os stashes valem para todos os checkouts deste repositório.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                }
                .padding(12)
            }
            GitCard {
                if state.stashes.isEmpty {
                    Text("Nenhum stash guardado.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.faded)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(state.stashes.enumerated()), id: \.element.id) { index, entry in
                            row(entry)
                                .overlay(alignment: .bottom) {
                                    if index < state.stashes.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                                }
                        }
                    }
                }
            }
        }
        .appDialog(
            { "Apagar \($0.ref)?" },
            item: $dropping,
            message: { "“\($0.message)” some da lista e as mudanças guardadas nele se perdem." },
            actions: { entry in
                [DialogAction("Apagar", role: .destructive) {
                    let repo = repo
                    let hash = entry.hash
                    run { try $0.dropStash(repo, hash: hash) }
                }]
            }
        )
    }

    func row(_ entry: StashEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.ref)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.faded)
            Text(entry.message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(relativeTime(entry.timestamp))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.faded)
                .fixedSize()
            Button("Aplicar") { apply(entry, drop: false) }
                .buttonStyle(GhostButton(compact: true))
                .disabled(model.busy)
                .help("Aplica as mudanças e mantém o stash na lista")
            Button("Aplicar e remover") { apply(entry, drop: true) }
                .buttonStyle(GhostButton(compact: true))
                .disabled(model.busy)
                .help("git stash pop")
            Button {
                dropping = entry
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.dangerText)
            }
            .buttonStyle(IconButton(size: 28))
            .disabled(model.busy)
            .help("Apagar este stash")
            .accessibilityLabel("Apagar stash")
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    func save() {
        guard !state.changes.isEmpty, !model.busy else { return }
        let repo = repo
        let checkout = state.checkout
        let text = message
        run({ try $0.saveStash(repo, checkout: checkout, message: text) }) { ok in
            if ok { message = "" }
        }
    }

    func apply(_ entry: StashEntry, drop: Bool) {
        let repo = repo
        let checkout = state.checkout
        let hash = entry.hash
        run { try $0.applyStash(repo, checkout: checkout, hash: hash, drop: drop) }
    }
}

struct NewBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: NewBranchRequest
    let onCreate: (String, Bool) -> Void

    @State private var name = ""
    @State private var switchTo = true
    @FocusState private var focused: Bool

    var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nova branch")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Text("a partir de")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                    Chip(text: request.startLabel, color: Theme.emberText, background: Theme.emberDark)
                }
            }
            TextField("nome-da-branch", text: $name)
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(focused ? Theme.ember.opacity(0.6) : Theme.line2, lineWidth: 1))
                .onSubmit(create)
            Toggle("Trocar para ela agora", isOn: $switchTo)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(GhostButton())
                    .keyboardShortcut(.cancelAction)
                Button("Criar branch", action: create)
                    .buttonStyle(EmberButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.45 : 1)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    func create() {
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, switchTo)
        dismiss()
    }
}
