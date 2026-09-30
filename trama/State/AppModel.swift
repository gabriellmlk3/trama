import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Hashable {
        case trama(String)
        case findings
    }

    enum NoteKind {
        case decision, pending, note, goal
    }

    @Published var state: OverallState?
    @Published var screen: Screen?
    @Published var capsule: TramaCapsule?
    @Published var findings: [Finding] = []
    @Published var findingsAt: Date?
    @Published var error: String?
    @Published var notice: String?
    @Published var needsSetup = false
    @Published var busy = false
    @Published var showingNewTrama = false
    @Published var resuming: LiveTrama?

    let terminals = TerminalStore()

    private var loop: Task<Void, Never>?
    private var refreshing = false

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            DispatchQueue.global(qos: .utility).async { Integration.sync() }
            await self?.refresh()
            await self?.fetchRemotes()
            await self?.refreshFindings()
            var cycle = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                cycle += 1
                await self.refresh()
                if cycle % 120 == 0 { await self.fetchRemotes() }
                if cycle % 12 == 0 { await self.refreshFindings() }
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let new = try await Core.run { try $0.fullState() }
            state = new
            needsSetup = false
            if screen == nil, let first = new.tramas.first(where: { $0.isActive }) ?? new.tramas.first {
                screen = .trama(first.slug)
            }
            if let t = selectedTrama {
                await loadCapsule(t.slug)
            }
        } catch let e as TramaError where e == .notInitialized {
            needsSetup = true
        } catch {
            showError(errorMessage(error))
        }
    }

    func refreshFindings() async {
        guard !needsSetup else { return }
        do {
            findings = try await Core.run { try $0.findings() }
            findingsAt = Date()
        } catch {
            showError(errorMessage(error))
        }
    }

    func fetchRemotes() async {
        guard !needsSetup else { return }
        _ = try? await Core.run { $0.fetchAll() }
        await refresh()
    }

    func loadCapsule(_ slug: String) async {
        if let c = try? await Core.run({ try $0.readCapsule(slug) }) {
            capsule = c
        }
    }

    func showError(_ text: String) {
        if error != text { error = text }
    }

    func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if notice == text { notice = nil }
        }
    }

    var visibleTramas: [LiveTrama] { state?.tramas.filter { !$0.isArchived } ?? [] }
    var active: [LiveTrama] { visibleTramas.filter { $0.isActive } }
    var parked: [LiveTrama] { visibleTramas.filter { $0.isParked } }
    var repos: [RepoConfig] { state?.repos ?? [] }
    var activeAgents: [Agent] { state?.agents ?? [] }

    var selectedTrama: LiveTrama? {
        guard case .trama(let slug)? = screen else { return nil }
        return state?.tramas.first(where: { $0.slug == slug })
    }

    var focusedTrama: LiveTrama? {
        if let t = selectedTrama, t.isActive { return t }
        return active.first
    }

    func agents(for slug: String) -> [Agent] {
        activeAgents.filter { $0.trama == slug }
    }

    func repo(_ name: String) -> RepoConfig? {
        repos.first(where: { $0.name == name })
    }

    func aliases(_ names: [String]) -> [String] {
        names.map { repo($0)?.alias ?? $0 }
    }

    func worktreePath(_ t: LiveTrama, _ repo: String) -> String {
        t.status(for: repo)?.path ?? (t.path + "/" + repo)
    }

    func select(_ slug: String) {
        screen = .trama(slug)
        if capsule?.trama != slug { capsule = nil }
        Task { await loadCapsule(slug) }
    }

    @discardableResult
    func perform(success: String? = nil, _ work: @escaping @Sendable (Workspace) throws -> Void) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            try await Core.run(work)
            if let success { showNotice(success) }
            await refresh()
            return true
        } catch {
            showError(errorMessage(error))
            return false
        }
    }

    func newTrama(_ options: NewTramaOptions, openAgents: Bool) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let result = try await Core.run { try $0.newTrama(options) }
            await refresh()
            select(result.trama.slug)
            showNotice("Trama “\(result.trama.title)” tecida")
            if !result.warnings.isEmpty {
                let lines = result.warnings.map { warning -> String in
                    guard let r = warning.repo else { return warning.message }
                    return "\(r): \(warning.message)"
                }
                showError(lines.joined(separator: "\n"))
            }
            if openAgents, let live = selectedTrama {
                openClaudeInAll(live)
            }
            return true
        } catch {
            showError(errorMessage(error))
            return false
        }
    }

    func park(_ slug: String) async {
        await perform(success: "Trama estacionada · os worktrees ficaram intactos") { _ = try $0.park(slug) }
    }

    func resume(_ slug: String, rebase: Bool) async -> [ResumeResult]? {
        busy = true
        defer { busy = false }
        do {
            let result = try await Core.run { try $0.resume(slug, rebase: rebase) }
            await refresh()
            select(slug)
            return result.results
        } catch {
            showError(errorMessage(error))
            return nil
        }
    }

    func pull(_ slug: String, _ repo: String) async {
        await perform(success: "\(repo) entrou na trama") { _ = try $0.pullRepos(slug, [repo]) }
    }

    func drop(_ slug: String, _ repo: String) async {
        await perform(success: "\(repo) saiu da trama (a branch continua)") { _ = try $0.dropRepo(slug, repo) }
    }

    func archive(_ slug: String) async {
        if await perform(success: "Trama arquivada", { _ = try $0.archive(slug) }) {
            screen = active.first.map { Screen.trama($0.slug) }
        }
    }

    func annotate(_ kind: NoteKind, _ text: String, trama slug: String) async {
        await perform { w in
            switch kind {
            case .decision: try w.addDecision(slug, author: "você", text)
            case .pending: try w.addPending(slug, text)
            case .note: try w.addJournal(slug, text)
            case .goal: try w.setGoal(slug, text)
            }
        }
        await loadCapsule(slug)
    }

    func completePending(_ n: Int, trama slug: String) async {
        await perform { try $0.completePending(slug, n) }
        await loadCapsule(slug)
    }

    func confirmHandoff(_ n: Int, trama slug: String) async {
        await perform { _ = try $0.confirmHandoffs(slug, to: nil, number: n) }
        await loadCapsule(slug)
    }

    func sync(_ slug: String) async {
        await perform(success: "Cápsula commitada no repositório de contexto") { _ = try $0.syncCapsule(slug) }
    }

    func resolve(_ finding: Finding) async {
        let ok: Bool
        switch finding.type {
        case FindingType.editOnBase, FindingType.forgottenChange:
            guard let repo = finding.repo, let slug = finding.suggestedTrama else { return }
            ok = await perform(success: "Mudanças levadas para a trama") { try $0.adoptChanges(repo, into: slug) }
        case FindingType.merged:
            guard let repo = finding.repo else { return }
            ok = await perform(success: "Branches integradas apagadas") { _ = try $0.cleanMerged(repo) }
        default:
            return
        }
        if ok { await refreshFindings() }
    }

    func openClaudeInAll(_ t: LiveTrama) {
        for r in t.repos {
            let path = worktreePath(t, r)
            terminals.open(path: path, command: "claude", title: "\(r) · claude")
        }
    }

    func setup(context: String?, repos: [String], hooks: Bool, command: Bool) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            try await Core.inBackground {
                let w = try Workspace.configure(context: context)
                var failures: [String] = []
                for p in repos {
                    do {
                        try w.addRepo(p)
                    } catch {
                        failures.append(errorMessage(error))
                    }
                }
                if command { try Integration.installCommand() }
                if hooks { try Integration.installHooks() }
                if !failures.isEmpty { throw TramaError(failures.joined(separator: "\n")) }
            }
            await refresh()
            await refreshFindings()
            return true
        } catch {
            showError(errorMessage(error))
            await refresh()
            return false
        }
    }

    func setContext(_ path: String) async {
        busy = true
        defer { busy = false }
        do {
            try await Core.inBackground { _ = try Workspace.configure(context: path) }
            showNotice("Repositório de contexto atualizado")
            await refresh()
        } catch {
            showError(errorMessage(error))
        }
    }

    func setDefaultBranch(_ branch: String) async {
        await perform(success: "Branch padrão atualizada") { w in try w.setDefaultBranch(branch) }
    }

    func addRepos(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        await perform(success: "Repositórios cadastrados") { w in
            var failures: [String] = []
            for p in paths {
                do {
                    try w.addRepo(p)
                } catch {
                    failures.append(errorMessage(error))
                }
            }
            if failures.count == paths.count { throw TramaError(failures.joined(separator: "\n")) }
        }
    }

    func removeRepo(_ name: String) async {
        await perform(success: "\(name) saiu do cadastro") { _ = try $0.removeRepo(name) }
    }
}
