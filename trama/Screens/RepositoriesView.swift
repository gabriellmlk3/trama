import Foundation
import SwiftUI

enum WorkbenchTab: Hashable {
    case history, changes, branches, stash
}

struct NewBranchRequest: Identifiable {
    var start: String?
    var startLabel: String

    var id: String { start ?? "HEAD" }
}

typealias GitWork = @Sendable (Workspace) throws -> String

struct GitRunner {
    let perform: (@escaping GitWork, @escaping (Bool) -> Void) -> Void

    func callAsFunction(_ work: @escaping GitWork, then done: @escaping (Bool) -> Void = { _ in }) {
        perform(work, done)
    }
}

struct RepositoriesView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("repositoriesSelection") private var selection = ""
    @State private var snapshots: [RepoSnapshot] = []
    @State private var loaded = false

    var current: RepoSnapshot? {
        snapshots.first { $0.name == selection } ?? snapshots.first
    }

    var headline: String {
        let dirty = snapshots.filter { $0.status.changed > 0 }.count
        let ahead = snapshots.filter { $0.status.ahead > 0 }.count
        return "\(snapshots.count) \(plural(snapshots.count, "repositório", "repositórios")) · \(dirty) com mudanças · \(ahead) com commits para enviar"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if loaded && snapshots.isEmpty {
                empty
            } else {
                if let current {
                    RepoWorkbench(snapshot: current, snapshots: snapshots, onSelect: { selection = $0 }) { await loadSnapshots() }
                        .id(current.name)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await loadSnapshots() }
        .onRefresh(model.clock, every: 6) { await loadSnapshots() }
    }

    var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(loaded ? headline : "lendo os repositórios…")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.faded)
                Text("Repositórios")
                    .font(Theme.serif(42))
                Text("Histórico, branches, stash e commits de cada repositório cadastrado, dentro ou fora das tramas.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
            Button {
                let names = snapshots.map(\.name)
                Task {
                    await model.fetchAllRepos(names)
                    await loadSnapshots()
                }
            } label: {
                Label("Buscar em todos", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(GhostButton())
            .disabled(model.busy || snapshots.isEmpty)
            .help("git fetch --all --prune em cada repositório cadastrado")
        }
    }

    var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 26))
                .foregroundStyle(Theme.thread)
            Text("Nenhum repositório cadastrado ainda.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
            Button("Cadastrar repositórios…") {
                let folders = Terminal.choosePaths(multiple: true, title: "Escolha os repositórios que podem entrar em tramas")
                Task { await model.addRepos(folders) }
            }
            .buttonStyle(GhostButton())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func loadSnapshots() async {
        guard let list = try? await Core.run({ $0.repoSnapshots() }) else { return }
        if list != snapshots { snapshots = list }
        loaded = true
    }
}

struct SyncCounts: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 6) {
            if ahead > 0 {
                Text("↑\(ahead)").foregroundStyle(Theme.emberLight)
            }
            if behind > 0 {
                Text("↓\(behind)").foregroundStyle(Theme.irisText)
            }
        }
        .font(Theme.mono(11))
    }
}

struct RepoSwitcher: View {
    let snapshots: [RepoSnapshot]
    let current: RepoSnapshot
    let onSelect: (String) -> Void
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(current.name)
                    .font(Theme.mono(21, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faded)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering || open ? Theme.surface : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -8)
        .onHover { hovering = $0 }
        .help("Trocar de repositório")
        .accessibilityLabel("Repositório \(current.name). Trocar de repositório")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            RepoSwitcherList(snapshots: snapshots, selected: current.name) {
                open = false
                onSelect($0)
            }
        }
    }
}

private struct RepoSwitcherList: View {
    let snapshots: [RepoSnapshot]
    let selected: String
    let onSelect: (String) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var filtered: [RepoSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return snapshots }
        return snapshots.filter {
            $0.name.lowercased().contains(needle) || $0.alias.lowercased().contains(needle) || $0.status.branch.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                TextField("Buscar repositório ou branch", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit { if let first = filtered.first { onSelect(first.name) } }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faded)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(searchFocused ? Theme.ember.opacity(0.6) : Theme.line2, lineWidth: 1))
            if filtered.isEmpty {
                Text("Nenhum repositório encontrado.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { s in
                            RepoSwitcherRow(snapshot: s, selected: s.name == selected) { onSelect(s.name) }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(filtered.count) * 56 + 4, 380))
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(Theme.background)
        .task { searchFocused = true }
    }
}

private struct RepoSwitcherRow: View {
    let snapshot: RepoSnapshot
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var branchLabel: String {
        snapshot.status.detached ? "HEAD solto · \(snapshot.status.head)" : snapshot.status.branch
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(snapshot.alias)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.text2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    SyncCounts(ahead: snapshot.status.ahead, behind: snapshot.status.behind)
                }
                HStack(spacing: 6) {
                    Image(systemName: snapshot.status.detached ? "exclamationmark.circle" : "arrow.triangle.branch")
                        .font(.system(size: 9.5))
                    Text(branchLabel)
                        .font(Theme.mono(11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if snapshot.error != nil {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.waitText)
                            .help(snapshot.error ?? "")
                    }
                    if snapshot.status.conflicts > 0 {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.waitText)
                            .help("\(snapshot.status.conflicts) \(plural(snapshot.status.conflicts, "arquivo em conflito", "arquivos em conflito"))")
                    } else if snapshot.status.changed > 0 {
                        Dot(color: Theme.wait, size: 6)
                        Text("\(snapshot.status.changed)")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.waitText)
                    }
                }
                .foregroundStyle(Theme.faded)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : (hovering ? Theme.surface : Color.clear)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Theme.line2 : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Mostrar no Finder") { Terminal.reveal(snapshot.path) }
            Button("Copiar caminho") { Terminal.copy(snapshot.path) }
        }
    }
}

private struct WorkbenchKey: Equatable {
    var checkout: String?
    var limit: Int
    var token: Int
}

struct RepoWorkbench: View {
    @EnvironmentObject var model: AppModel
    let snapshot: RepoSnapshot
    let snapshots: [RepoSnapshot]
    let onSelect: (String) -> Void
    let onChanged: () async -> Void

    @State private var checkout: String?
    @State private var state: RepoBrowserState?
    @State private var loadError: String?
    @State private var tab = WorkbenchTab.history
    @State private var limit = 400
    @State private var token = 0
    @State private var selectedCommit: String?
    @State private var branchRequest: NewBranchRequest?
    @State private var showingConflicts = false
    @State private var labeledActions = true
    @Namespace private var tabPill

    var path: String { state?.checkout ?? checkout ?? snapshot.path }

    var repoConfig: RepoConfig? { model.repo(snapshot.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let state {
                if state.merging || state.status.conflicts > 0 {
                    conflictBanner(state)
                }
                tabs(state)
                content(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if let loadError {
                Text(loadError)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.waitText)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("lendo o Git…").font(.system(size: 12.5)).foregroundStyle(Theme.faded)
                }
                .padding(.top, 20)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: WorkbenchKey(checkout: checkout, limit: limit, token: token)) {
            await load()
        }
        .onRefresh(model.clock) { await load() }
        .sheet(item: $branchRequest) { request in
            NewBranchSheet(request: request) { name, switchTo in
                let repo = snapshot.name
                let checkout = path
                let start = request.start
                run { try $0.createBranch(repo, checkout: checkout, name: name, from: start, switchTo: switchTo) }
            }
        }
        .sheet(isPresented: $showingConflicts) {
            ConflictsSheet(repo: snapshot.name, worktree: path, title: snapshot.alias)
        }
    }

    func load() async {
        let name = snapshot.name
        let checkout = checkout
        let limit = limit
        do {
            let fresh = try await Core.run { try $0.repoBrowser(name, checkout: checkout, limit: limit) }
            if !fresh.sameContent(as: state) { state = fresh }
            loadError = nil
        } catch {
            if checkout != nil {
                self.checkout = nil
            } else {
                loadError = errorMessage(error)
            }
        }
    }

    func run(_ work: @escaping GitWork, then done: @escaping (Bool) -> Void = { _ in }) {
        let repo = snapshot.name
        Task {
            let ok = await model.performGit(repo, work)
            done(ok)
            token += 1
            await onChanged()
        }
    }

    var runner: GitRunner {
        GitRunner { work, done in run(work, then: done) }
    }

    func label(for checkout: CheckoutInfo) -> String {
        let branch = checkout.branch.isEmpty ? "HEAD solto" : checkout.branch
        if checkout.isPrimary { return "cópia principal · \(branch)" }
        let owner = model.checkoutLabel(checkout.path, repo: snapshot.name) ?? Paths.name(checkout.path)
        return "\(owner) · \(branch)"
    }

    var labeledActionsWidth: CGFloat {
        let name = CGFloat(snapshot.name.count) * 12.6
        let label = repoConfig?.label.map { $0.isEmpty ? 0 : CGFloat($0.count) * 7 + 38 } ?? 0
        return name + label + 44 + 440
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    RepoSwitcher(snapshots: snapshots, current: snapshot, onSelect: onSelect)
                    if let label = repoConfig?.label, !label.isEmpty {
                        Chip(text: label)
                    }
                }
                Spacer(minLength: 8)
                if let state {
                    actions(state, labeled: labeledActions)
                }
            }
            if let state {
                HStack(spacing: 8) {
                    if state.checkouts.count > 1 {
                        checkoutMenu(state)
                    }
                    branchMenu(state)
                    upstreamChip(state)
                    Spacer(minLength: 0)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= labeledActionsWidth } action: { labeledActions = $0 }
    }

    func checkoutMenu(_ state: RepoBrowserState) -> some View {
        let current = state.checkouts.first { $0.path == state.checkout }
        return AppMenu(width: 380) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faded)
                Text(current.map { label(for: $0) } ?? Paths.abbreviate(state.checkout))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.faded)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
            .contentShape(Rectangle())
        } content: {
            MenuSection("Checkout")
            state.checkouts.map { c in
                MenuAction(label(for: c), checked: c.path == state.checkout) {
                    checkout = c.isPrimary ? nil : c.path
                    selectedCommit = nil
                }
            }
        }
        .buttonStyle(.plain)
        .help("Checkout em que os comandos rodam: a cópia principal ou o worktree de uma trama")
    }

    func branchMenu(_ state: RepoBrowserState) -> some View {
        AppMenu(width: 300) {
            HStack(spacing: 6) {
                Image(systemName: state.status.detached ? "exclamationmark.circle" : "arrow.triangle.branch")
                    .font(.system(size: 10))
                Text(state.status.detached ? "HEAD solto · \(state.status.head)" : state.status.branch)
                    .font(Theme.mono(11.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(state.status.detached ? Theme.waitText : Theme.emberLight)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill((state.status.detached ? Theme.wait : Theme.ember).opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke((state.status.detached ? Theme.wait : Theme.ember).opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle())
        } content: {
            MenuSection("Trocar para")
            state.localBranches.prefix(14).map { b in
                MenuAction(b.name, checked: b.current, disabled: b.current || b.openAt != nil || model.busy) {
                    let repo = snapshot.name
                    let checkout = path
                    run { try $0.switchBranch(repo, checkout: checkout, branch: b.name, remote: false) }
                }
            }
            MenuDivider()
            MenuAction("Nova branch…", systemImage: "plus") {
                branchRequest = NewBranchRequest(start: nil, startLabel: state.status.detached ? state.status.head : state.status.branch)
            }
            MenuAction("Todas as branches", systemImage: "list.bullet") { tab = .branches }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func upstreamChip(_ state: RepoBrowserState) -> some View {
        if state.status.detached {
            EmptyView()
        } else if let upstream = state.status.upstream {
            if state.status.ahead == 0 && state.status.behind == 0 {
                StatusNote(icon: "checkmark.circle.fill", tone: .ok, text: "em dia com \(upstream)")
            } else {
                StatusNote(icon: "arrow.up.arrow.down.circle.fill", tone: .wait) {
                    SyncCounts(ahead: state.status.ahead, behind: state.status.behind)
                    Text(upstream).truncationMode(.middle)
                }
            }
        } else {
            StatusNote(icon: "icloud.slash", text: "só local · sem branch remota")
        }
    }

    func actions(_ state: RepoBrowserState, labeled: Bool) -> some View {
        let status = state.status
        let repo = snapshot.name
        let checkout = path
        return HStack(spacing: 8) {
            Button {
                run { try $0.fetchRepo(repo) }
            } label: {
                countLabel("Buscar", icon: "arrow.triangle.2.circlepath", count: 0, labeled: labeled)
            }
            .buttonStyle(GhostButton(compact: true))
            .disabled(model.busy || !state.hasRemote)
            .help("git fetch --all --prune")
            Button {
                run { try $0.pullCheckout(repo, checkout: checkout) }
            } label: {
                countLabel("Puxar", icon: "arrow.down", count: status.behind, labeled: labeled)
            }
            .buttonStyle(GhostButton(compact: true))
            .disabled(model.busy || status.detached || status.upstream == nil)
            .help("Traz os commits novos de \(status.upstream ?? "origin") sem criar merge")
            Button {
                run { try $0.pushCheckout(repo, checkout: checkout) }
            } label: {
                countLabel(status.upstream == nil ? "Publicar" : "Enviar", icon: "arrow.up", count: status.ahead, labeled: labeled)
            }
            .buttonStyle(GhostButton(compact: true))
            .disabled(model.busy || status.detached || !state.hasRemote || (status.upstream != nil && status.ahead == 0))
            .help(status.upstream == nil ? "Envia a branch para origin e passa a acompanhá-la" : "git push")
            Button {
                tab = .stash
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .buttonStyle(IconButton(size: 28))
            .help("Stash")
            .accessibilityLabel("Stash")
            Button {
                _ = model.terminals.open(path: checkout, command: nil, title: "\(snapshot.alias) · git")
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(IconButton(size: 28))
            .help("Abrir um terminal neste checkout")
            .accessibilityLabel("Terminal")
            Button {
                Terminal.reveal(checkout)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(IconButton(size: 28))
            .help("Mostrar no Finder")
            .accessibilityLabel("Mostrar no Finder")
        }
    }

    func countLabel(_ title: String, icon: String, count: Int, labeled: Bool) -> some View {
        HStack(spacing: 6) {
            if labeled {
                Label(title, systemImage: icon)
            } else {
                Image(systemName: icon)
                    .accessibilityLabel(title)
            }
            if count > 0 {
                Text("\(count)")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.emberText)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(Capsule().fill(Theme.ember.opacity(0.22)))
            }
        }
        .fixedSize()
    }

    func conflictBanner(_ state: RepoBrowserState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.waitText)
            Text(state.merging ? "Merge em andamento · \(state.status.conflicts) \(plural(state.status.conflicts, "arquivo em conflito", "arquivos em conflito"))" : "\(state.status.conflicts) \(plural(state.status.conflicts, "arquivo em conflito", "arquivos em conflito"))")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
            Spacer()
            Button("Resolver conflitos…") { showingConflicts = true }
                .buttonStyle(ToneButton(color: Theme.wait, text: Theme.waitText))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.wait.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.wait.opacity(0.4), lineWidth: 1))
    }

    func tabs(_ state: RepoBrowserState) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                tabButton("Histórico", count: nil, value: .history)
                tabButton("Mudanças", count: state.changes.count, value: .changes)
                tabButton("Branches", count: state.localBranches.count, value: .branches)
                tabButton("Stash", count: state.stashes.count, value: .stash)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: tab)
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2, lineWidth: 1))
            .fixedSize()
            Spacer(minLength: 8)
            Text(Paths.abbreviate(state.checkout))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.faded)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    func tabButton(_ title: String, count: Int?, value: WorkbenchTab) -> some View {
        Button {
            tab = value
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: tab == value ? .medium : .regular))
                if let count {
                    Text("\(count)")
                        .font(Theme.mono(10.5))
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 16)
                        .background(Capsule().fill(tab == value ? Theme.ember.opacity(0.22) : Theme.surface2))
                        .foregroundStyle(tab == value ? Theme.emberText : Theme.faded)
                }
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

    @ViewBuilder
    func content(_ state: RepoBrowserState) -> some View {
        let repo = snapshot.name
        switch tab {
        case .history:
            CommitHistoryPane(
                repo: repo,
                state: state,
                selected: $selectedCommit,
                onBranch: { hash in branchRequest = NewBranchRequest(start: hash, startLabel: String(hash.prefix(7))) },
                onShowChanges: { tab = .changes },
                onLoadMore: { limit += 400 }
            )
        case .changes:
            BlurScrollView {
                CheckoutChangesPane(repo: repo, state: state, draftScope: model.tramaSlug(forCheckout: state.checkout, repo: repo) ?? state.checkout, run: runner)
            }
        case .branches:
            BlurScrollView {
                BranchesPane(
                    repo: repo,
                    state: state,
                    openLabel: { model.checkoutLabel($0, repo: repo) ?? Paths.abbreviate($0) },
                    run: runner,
                    onNewBranch: { start in branchRequest = NewBranchRequest(start: start, startLabel: start ?? state.status.branch) }
                )
            }
        case .stash:
            BlurScrollView {
                StashPane(repo: repo, state: state, run: runner)
            }
        }
    }
}

private struct DiffKey: Equatable {
    var changes: [FileChange]
    var selectedFile: String?
}

struct CheckoutChangesPane: View {
    @EnvironmentObject var model: AppModel
    let repo: String
    let state: RepoBrowserState
    let draftScope: String
    let run: GitRunner

    @State private var selectedFile: String?
    @State private var diff: [DiffLine] = []
    @State private var unchecked: Set<String> = []
    @State private var discarding: DiscardRequest?
    @State private var generating = false

    var changes: [FileChange] { state.changes }
    var selected: FileChange? { changes.first { $0.id == selectedFile } }
    var chosen: [String] { changes.map(\.id).filter { !unchecked.contains($0) } }
    var draft: Binding<String> { model.commitDraft(draftScope, repo) }

    var canCommit: Bool {
        !model.busy && !chosen.isEmpty && !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!state.merging || chosen.count == changes.count)
    }

    var body: some View {
        Group {
            if changes.isEmpty {
                GitCard {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.okText)
                        Text("Checkout limpo · nada para commitar.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.text3)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WidthSwitch {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            fileList
                            commitBox
                        }
                        .frame(width: 300)
                        diffPane
                    }
                } narrow: {
                    VStack(spacing: 14) {
                        fileList
                        commitBox
                        diffPane
                    }
                }
            }
        }
        .task(id: DiffKey(changes: changes, selectedFile: selectedFile)) { await loadDiff() }
        .onChange(of: changes.map(\.id)) { _, ids in
            unchecked.formIntersection(ids)
            if let s = selectedFile, !ids.contains(s) { selectedFile = ids.first }
        }
        .onAppear { if selectedFile == nil { selectedFile = changes.first?.id } }
        .appDialog(
            { $0.title },
            item: $discarding,
            message: { $0.message },
            actions: { request in [DialogAction("Descartar", role: .destructive) { confirm(request) }] }
        )
    }

    var fileList: some View {
        FileList(
            changes: changes,
            selectedFile: $selectedFile,
            unchecked: $unchecked,
            onDiscard: state.merging ? nil : { discarding = .files([$0]) },
            onDiscardAll: state.merging ? nil : { discarding = .files(changes) }
        )
    }

    var diffPane: some View {
        DiffPane(
            change: selected,
            lines: diff,
            path: state.checkout,
            onDiscardFile: state.merging ? nil : { discarding = .files([$0]) },
            onDiscardLines: state.merging ? nil : { c, ids in discarding = .lines(c, ids) }
        )
    }

    var commitBox: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Mensagem do commit", text: draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(1...5)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                if state.merging && chosen.count != changes.count {
                    Text("Merge em andamento: o commit precisa incluir todos os arquivos.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.waitText)
                }
                HStack {
                    Button {
                        generate()
                    } label: {
                        if generating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("Gerar", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(GhostButton(compact: true))
                    .disabled(generating || chosen.isEmpty)
                    .help("Gerar a mensagem com o Claude a partir dos arquivos marcados")
                    Spacer()
                    Button {
                        commit()
                    } label: {
                        Text("Commitar \(chosen.count) \(plural(chosen.count, "arquivo", "arquivos"))")
                    }
                    .buttonStyle(EmberButton(compact: true))
                    .disabled(!canCommit)
                    .opacity(canCommit ? 1 : 0.45)
                }
            }
            .padding(12)
        }
    }

    func loadDiff() async {
        guard let change = selected else {
            diff = []
            return
        }
        let repo = repo
        let checkout = state.checkout
        let lines = (try? await Core.run { try $0.checkoutFileDiff(repo, checkout: checkout, change: change) }) ?? []
        if lines != diff { diff = lines }
    }

    func commit() {
        let repo = repo
        let checkout = state.checkout
        let paths = chosen
        let message = draft.wrappedValue
        let binding = draft
        run({ w in
            let made = try w.commitCheckout(repo, checkout: checkout, paths: paths, message: message)
            return "commit \(made.hash) feito"
        }) { ok in
            guard ok else { return }
            binding.wrappedValue = ""
            unchecked = []
        }
    }

    func generate() {
        let repo = repo
        let checkout = state.checkout
        let paths = chosen
        let binding = draft
        generating = true
        Task {
            defer { generating = false }
            do {
                binding.wrappedValue = try await Core.run { try $0.suggestCheckoutCommitMessage(repo, checkout: checkout, paths: paths) }
            } catch {
                model.showError("\(repo): \(errorMessage(error))")
            }
        }
    }

    func confirm(_ request: DiscardRequest) {
        let repo = repo
        let checkout = state.checkout
        switch request {
        case .files(let list):
            let paths = list.map(\.path)
            unchecked.subtract(paths)
            run { w in
                try w.discardInCheckout(repo, checkout: checkout, paths: paths)
                return "\(paths.count) \(plural(paths.count, "arquivo descartado", "arquivos descartados"))"
            }
        case .lines(let change, let ids):
            run { w in
                try w.discardLinesInCheckout(repo, checkout: checkout, change: change, lines: ids)
                return "\(ids.count) \(plural(ids.count, "linha descartada", "linhas descartadas")) em \(change.name)"
            }
        }
    }
}
