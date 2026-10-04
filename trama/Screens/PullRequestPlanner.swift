import Foundation
import SwiftUI

enum Column {
    static let gap: CGFloat = 14
    static let check: CGFloat = 20
    static let repo: CGFloat = 150
    static let target: CGFloat = 228
    static let commits: CGFloat = 64
    static let conflict: CGFloat = 132
}

struct PlannerSeed: Sendable {
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
