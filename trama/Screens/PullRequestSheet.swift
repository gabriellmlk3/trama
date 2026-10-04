import Foundation
import SwiftUI

private enum Column {
    static let gap: CGFloat = 14
    static let check: CGFloat = 20
    static let repo: CGFloat = 150
    static let target: CGFloat = 228
    static let commits: CGFloat = 64
    static let conflict: CGFloat = 132
}

private struct PlannerSeed: Sendable {
    var saved: [String: String]
    var defaults: [String: String]
    var options: [RemoteBranchOption]
}

@MainActor
final class PullRequestPlanner: ObservableObject {
    private(set) var slug = ""
    private(set) var repoCount = 0

    @Published private(set) var rows: [PullRequestPlanRow] = []
    @Published private(set) var options: [RemoteBranchOption] = []
    @Published private(set) var targets: [String: String] = [:]
    @Published private(set) var defaults: [String: String] = [:]
    @Published private(set) var missing: [String: String] = [:]
    @Published private(set) var excluded: Set<String> = []
    @Published private(set) var chosenForAll: String?
    @Published private(set) var loaded = false
    @Published private(set) var existingLoaded = false
    @Published private(set) var refreshing = false
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var refreshFailures: [String] = []
    @Published private(set) var failure: String?
    @Published private(set) var creatingBranches: Set<String> = []
    @Published private(set) var creationFailure: String?
    @Published var draft = false
    @Published var mode = Mode.pullRequest

    enum Mode: Hashable, Identifiable {
        case pullRequest, merge
        var id: Self { self }
    }

    private var existing: [String: ExistingPullRequest] = [:]
    private var generation = 0
    private var started = false

    func start(slug: String, repoCount: Int) async {
        guard !started else { return }
        started = true
        self.slug = slug
        self.repoCount = repoCount
        do {
            let seed = try await Core.run { w -> PlannerSeed in
                let t = try w.pullRequestTargets(slug)
                let catalog = try w.remoteBranchCatalog(slug)
                return PlannerSeed(saved: t.saved, defaults: t.defaults, options: catalog.options)
            }
            targets = seed.saved
            defaults = seed.defaults
            options = seed.options
        } catch {
            failure = errorMessage(error)
            return
        }
        await plan()
        loaded = true
        let known = try? await Core.run { try $0.existingPullRequests(slug) }
        existing = known ?? [:]
        existingLoaded = true
        await plan()
        await refresh()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let slug = self.slug
        do {
            let fresh = try await Core.run { w -> (catalog: RemoteBranchCatalog, existing: [String: ExistingPullRequest]) in
                let catalog = try w.remoteBranchCatalog(slug, fetch: true)
                return (catalog, try w.existingPullRequests(slug))
            }
            options = fresh.catalog.options
            existing = fresh.existing
            existingLoaded = true
            refreshFailures = fresh.catalog.warnings.map { w in w.repo.map { "\($0): \(w.message)" } ?? w.message }
            refreshedAt = Date()
        } catch {
            refreshFailures = [errorMessage(error)]
        }
        await plan()
    }

    private func plan() async {
        generation += 1
        let mine = generation
        let slug = self.slug
        let snapshot = targets
        let known = existing
        guard let result = try? await Core.run({ try $0.pullRequestPlan(slug, targets: snapshot, existing: known) }) else { return }
        if mine == generation { rows = result }
    }

    private func replan() {
        Task { await plan() }
    }

    func choose(_ branch: String, for repo: String) {
        targets[repo] = branch
        missing[repo] = nil
        replan()
    }

    func chooseForAll(_ branch: String) {
        let covered = Set(options.first(where: { $0.name == branch })?.repos ?? [])
        chosenForAll = branch
        for name in targets.keys {
            if covered.contains(name) {
                targets[name] = branch
                missing[name] = nil
            } else {
                missing[name] = branch
            }
        }
        replan()
    }

    private func reposFor(_ branch: String, scope: String?) -> [String] {
        scope.map { [$0] } ?? options.first(where: { $0.name == branch })?.repos ?? []
    }

    func createBranch(_ name: String, from source: String, scope: String?) async -> String? {
        let slug = self.slug
        let taken = Set(options.first(where: { $0.name == name })?.repos ?? [])
        let repos = reposFor(source, scope: scope).filter { !taken.contains($0) }
        do {
            try await Core.run { try $0.createRemoteBranch(slug, name: name, from: source, repos: repos) }
        } catch {
            return errorMessage(error)
        }
        await refresh()
        if let scope { choose(name, for: scope) } else { chooseForAll(name) }
        return nil
    }

    var missingByBranch: [String: [String]] {
        var out: [String: [String]] = [:]
        for row in rows {
            if let wanted = missing[row.repo] ?? (row.blocker == .missingTarget ? row.target : nil) {
                out[wanted, default: []].append(row.repo)
            }
        }
        return out
    }

    var missingCount: Int { missingByBranch.values.reduce(0) { $0 + $1.count } }

    func createMissing(_ name: String, repos: [String]) async {
        guard !repos.isEmpty, creatingBranches.isDisjoint(with: repos) else { return }
        creatingBranches.formUnion(repos)
        creationFailure = nil
        defer { creatingBranches.subtract(repos) }
        let slug = self.slug
        let fallback = originLabel
        let groups = Dictionary(grouping: repos, by: { defaults[$0] ?? fallback })
        do {
            for (source, group) in groups {
                try await Core.run { try $0.createRemoteBranch(slug, name: name, from: source, repos: group) }
            }
        } catch {
            creationFailure = errorMessage(error)
        }
        await refresh()
        let covered = Set(options.first(where: { $0.name == name })?.repos ?? [])
        for repo in repos where covered.contains(repo) {
            targets[repo] = name
            missing[repo] = nil
        }
        replan()
    }

    func renameBranch(_ old: String, to new: String, scope: String?) async -> String? {
        let slug = self.slug
        let repos = reposFor(old, scope: scope)
        do {
            try await Core.run { try $0.renameRemoteBranch(slug, from: old, to: new, repos: repos) }
        } catch {
            return errorMessage(error)
        }
        for name in repos where targets[name] == old { targets[name] = new }
        if chosenForAll == old { chosenForAll = new }
        await refresh()
        return nil
    }

    func deleteBranch(_ branch: String, scope: String?) async -> String? {
        let slug = self.slug
        let repos = reposFor(branch, scope: scope)
        do {
            try await Core.run { try $0.deleteRemoteBranch(slug, name: branch, repos: repos) }
        } catch {
            return errorMessage(error)
        }
        for name in repos where targets[name] == branch { targets[name] = defaults[name] }
        if chosenForAll == branch { chosenForAll = nil }
        await refresh()
        return nil
    }

    func discard(_ repo: String) {
        existing[repo] = nil
        excluded.remove(repo)
        replan()
    }

    func toggle(_ repo: String) {
        if excluded.contains(repo) {
            excluded.remove(repo)
        } else {
            excluded.insert(repo)
        }
    }

    func branches(for repo: String) -> [RemoteBranchOption] {
        options.filter { $0.repos.contains(repo) }
    }

    var defaultNames: Set<String> { Set(defaults.values) }

    var commonTarget: String? {
        let counts = Dictionary(grouping: targets.values, by: { $0 }).mapValues { $0.count }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
    }

    var shownForAll: String? { chosenForAll ?? commonTarget }

    var originLabel: String { commonDefault ?? "main" }

    private var commonDefault: String? {
        let counts = Dictionary(grouping: defaults.values, by: { $0 }).mapValues { $0.count }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
    }

    func coverage(of branch: String) -> Int {
        options.first(where: { $0.name == branch })?.repos.count ?? 0
    }

    func canMerge(_ row: PullRequestPlanRow) -> Bool {
        switch row.blocker {
        case nil, .merged, .closed: return row.ahead > 0 && !row.hasConflict
        default: return false
        }
    }

    func isIncluded(_ row: PullRequestPlanRow) -> Bool {
        let usable = mode == .merge ? canMerge(row) : row.action != .blocked
        return usable && !excluded.contains(row.repo)
    }

    var selection: [PullRequestPlanRow] { rows.filter { isIncluded($0) } }
    var creating: Int { selection.filter { $0.action == .create }.count }
    var retargeting: Int { selection.filter { $0.action == .retarget }.count }
    var updating: Int { selection.filter { $0.action == .update }.count }
    var manual: Int { selection.filter { $0.action == .manual }.count }
    var canSubmit: Bool { loaded && existingLoaded && !selection.isEmpty }
    var runOnly: Set<String> { Set(selection.map { $0.repo }) }

    var runTargets: [String: String] {
        Dictionary(uniqueKeysWithValues: selection.map { ($0.repo, $0.target) })
    }

    var buttonTitle: String {
        if mode == .merge {
            let n = selection.count
            return n == 0 ? "Nada a mesclar" : "Mesclar \(n) \(plural(n, "repositório", "repositórios")) direto"
        }
        var parts: [String] = []
        if creating > 0 { parts.append("abrir \(creating) \(plural(creating, "PR", "PRs"))") }
        if retargeting > 0 { parts.append("redirecionar \(retargeting)") }
        if updating > 0 { parts.append("atualizar \(updating)") }
        if manual > 0 { parts.append(parts.isEmpty ? "abrir \(manual) \(plural(manual, "PR", "PRs")) no navegador" : "\(manual) no navegador") }
        guard let last = parts.last else { return "Nada a enviar" }
        let head = parts.dropLast().joined(separator: ", ")
        let text = head.isEmpty ? last : head + " e " + last
        return text.prefix(1).uppercased() + String(text.dropFirst())
    }
}

struct PullRequestSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planner = PullRequestPlanner()
    @State private var pickingForAll = false
    @State private var sending = false
    @State private var confirmingMerge = false
    let trama: LiveTrama

    init(trama: LiveTrama, mode: PullRequestPlanner.Mode) {
        self.trama = trama
        let planner = PullRequestPlanner()
        planner.mode = mode
        _planner = StateObject(wrappedValue: planner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            content
            footer
        }
        .frame(width: 980)
        .background(Theme.field)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .task { await planner.start(slug: trama.slug, repoCount: trama.trama.repos.count) }
    }

    var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.pull")
                    Text(trama.branch).foregroundStyle(Theme.emberLight)
                    Text("·")
                    Text(trama.title)
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.faded)
                Text(planner.mode == .merge ? "Mesclar direto" : "Abrir PRs")
                    .font(Theme.serif(32))
            }
            Spacer()
            if planner.mode == .pullRequest {
            HStack(spacing: 10) {
                Text("Abrir como rascunho")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                Toggle("Abrir como rascunho", isOn: $planner.draft)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar
            if let failure = planner.failure {
                Text(failure)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.waitText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if planner.loaded {
                table
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            footnote
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    var toolbar: some View {
        HStack(spacing: 14) {
            Text("Todos para")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text3)
            TargetButton(name: planner.shownForAll ?? "…", open: pickingForAll) { pickingForAll.toggle() }
                .frame(width: 188)
                .popover(isPresented: $pickingForAll, arrowEdge: .bottom) {
                    BranchPicker(
                        options: planner.options,
                        selected: planner.shownForAll,
                        totalRepos: planner.repoCount,
                        scopedRepo: nil,
                        defaultNames: planner.defaultNames,
                        planner: planner
                    ) { name in
                        planner.chooseForAll(name)
                        pickingForAll = false
                    }
                }
            if let all = planner.shownForAll {
                Chip(text: "existe em \(planner.coverage(of: all)) de \(planner.repoCount) \(plural(planner.repoCount, "repo", "repos"))")
            }
            if planner.missingCount > 0 {
                Button {
                    Task {
                        for (name, repos) in planner.missingByBranch {
                            await planner.createMissing(name, repos: repos)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if !planner.creatingBranches.isEmpty {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        }
                        Text("Criar nos \(planner.missingCount) \(plural(planner.missingCount, "repo", "repos")) sem a branch")
                    }
                }
                .buttonStyle(GhostButton(compact: true))
                .disabled(!planner.creatingBranches.isEmpty)
            }
            if let failure = planner.creationFailure {
                Text(failure)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.waitText)
                    .lineLimit(1)
                    .help(failure)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("branch de origem")
                Text(trama.base ?? planner.originLabel)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.text3)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.faded)
            Rectangle().fill(Theme.line2).frame(width: 1, height: 18)
            Text(refreshText)
                .font(.system(size: 12))
                .foregroundStyle(planner.refreshFailures.isEmpty ? Theme.faded : Theme.waitText)
                .help(planner.refreshFailures.joined(separator: "\n"))
            Button {
                Task { await planner.refresh() }
            } label: {
                if planner.refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(IconButton(size: 30))
            .disabled(planner.refreshing)
            .help("Atualizar as branches do remoto")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }

    var refreshText: String {
        if planner.refreshing { return "atualizando o remoto…" }
        if !planner.refreshFailures.isEmpty { return "remoto não atualizado" }
        guard let at = planner.refreshedAt else { return "" }
        let ago = relativeTime(Int64(at.timeIntervalSince1970))
        return ago == "agora" ? "remoto atualizado agora" : "remoto atualizado \(ago)"
    }

    var table: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Column.gap) {
                Color.clear.frame(width: Column.check, height: 1)
                SectionLabel(text: "Repositório").frame(width: Column.repo, alignment: .leading)
                SectionLabel(text: planner.mode == .merge ? "Mesclar em" : "Destino do PR").frame(width: Column.target, alignment: .leading)
                SectionLabel(text: "Commits").frame(width: Column.commits, alignment: .leading)
                SectionLabel(text: "Conflito previsto").frame(width: Column.conflict, alignment: .leading)
                SectionLabel(text: "Situação").frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(planner.rows) { row in
                        PullRequestRowView(row: row, planner: planner)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }

    var footnote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 13))
                .foregroundStyle(Theme.iris)
                .padding(.top, 1)
            Text(planner.mode == .merge
                ? "A branch da trama é mesclada direto no destino e enviada ao remoto" + orderText + ", sem PR e sem revisão. Repositórios com conflito previsto ficam de fora: traga o destino para a trama e resolva antes."
                : "Os PRs recebem links cruzados na ordem de merge" + orderText + ". Commits e conflitos são calculados contra o destino de cada linha." + manualText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    var manualText: String {
        planner.manual > 0 ? " Onde o provedor não tem automação (ou falta o gh, az ou glab), a branch sobe e o PR abre pelo link, no navegador." : ""
    }

    var orderText: String {
        let names = planner.selection.map { $0.repo }
        return names.count > 1 ? ": " + names.joined(separator: " → ") : ""
    }

    var footer: some View {
        HStack(spacing: 18) {
            summary
            Spacer()
            Button("Cancelar") { dismiss() }
                .buttonStyle(GhostButton())
                .keyboardShortcut(.cancelAction)
            Button(action: { planner.mode == .merge ? (confirmingMerge = true) : submit() }) {
                HStack(spacing: 10) {
                    if sending {
                        ProgressView().controlSize(.small)
                    }
                    Text(planner.buttonTitle)
                    KeyCap(text: "⌘↵", dark: true)
                }
            }
            .buttonStyle(EmberButton())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!planner.canSubmit || sending)
            .opacity(planner.canSubmit && !sending ? 1 : 0.5)
        }
        .appDialog(
            "Mesclar direto, sem PR?",
            isPresented: $confirmingMerge,
            message: planner.selection.map { "\($0.repo) → \($0.target)" }.joined(separator: "\n"),
            actions: [DialogAction("Mesclar e enviar ao remoto", role: .destructive, handler: submit)]
        )
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Theme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    var summary: some View {
        HStack(spacing: 18) {
            let pushes = planner.selection.count
            if pushes == 0 {
                Text("Nada para enviar")
            } else if planner.mode == .merge {
                SummaryStat(value: pushes, text: pushes == 1 ? "branch recebe a mescla" : "branches recebem a mescla", color: Theme.emberLight)
            } else {
                SummaryStat(value: pushes, text: pushes == 1 ? "branch vai para o remoto" : "branches vão para o remoto", color: Theme.text)
                if planner.creating > 0 {
                    SummaryStat(value: planner.creating, text: plural(planner.creating, "PR novo", "PRs novos"), color: Theme.emberLight)
                }
                if planner.retargeting > 0 {
                    SummaryStat(value: planner.retargeting, text: plural(planner.retargeting, "redirecionado", "redirecionados"), color: Theme.irisText)
                }
                if planner.updating > 0 {
                    SummaryStat(value: planner.updating, text: plural(planner.updating, "atualizado", "atualizados"), color: Theme.okText)
                }
                if planner.manual > 0 {
                    SummaryStat(value: planner.manual, text: plural(planner.manual, "abre no navegador", "abrem no navegador"), color: Theme.text2)
                }
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.faded)
    }

    func submit() {
        guard planner.canSubmit, !sending else { return }
        sending = true
        let targets = planner.runTargets
        let only = planner.runOnly
        let draft = planner.draft
        let merging = planner.mode == .merge
        Task {
            if merging {
                let ok = await model.mergeIntoBranches(trama.slug, targets: targets, only: only)
                sending = false
                if ok { dismiss() }
                return
            }
            let ok = await model.openPullRequests(trama.slug, draft: draft, targets: targets, only: only)
            sending = false
            if ok { dismiss() }
        }
    }
}

private struct SummaryStat: View {
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

private struct TargetButton: View {
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

private struct TonePill: View {
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

private struct PullRequestRowView: View {
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

private struct BranchPicker: View {
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
