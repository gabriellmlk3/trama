import Foundation

extension AppModel {
    @discardableResult
    func performGit(_ repo: String, _ work: @escaping @Sendable (Workspace) throws -> String) async -> Bool {
        busy = true
        defer { busy = false }
        let name = self.repo(repo)?.alias ?? repo
        do {
            let message = try await Core.run(work)
            showNotice("\(name): \(message)")
            await refresh()
            return true
        } catch {
            await refresh()
            showError("\(name): \(errorMessage(error))")
            return false
        }
    }

    func fetchAllRepos(_ names: [String]) async {
        busy = true
        defer { busy = false }
        let width = 4
        var outcomes = [String?](repeating: nil, count: names.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            func launch() {
                guard next < names.count else { return }
                let index = next
                let name = names[index]
                next += 1
                group.addTask {
                    do {
                        _ = try await Core.run { try $0.fetchRepo(name) }
                        return (index, nil)
                    } catch {
                        return (index, errorMessage(error))
                    }
                }
            }
            for _ in 0..<min(width, names.count) { launch() }
            for await (index, failure) in group {
                outcomes[index] = failure
                launch()
            }
        }
        let failures = names.enumerated().compactMap { index, name in
            outcomes[index].map { "\(repo(name)?.alias ?? name): \($0)" }
        }
        await refresh()
        let done = names.count - failures.count
        if failures.isEmpty {
            showNotice("Remotos atualizados em \(done) \(plural(done, "repositório", "repositórios"))")
        } else {
            showError(failures.joined(separator: "\n"))
        }
    }

    func checkoutLabel(_ path: String, repo: String) -> String? {
        for t in state?.tramas ?? [] {
            if let s = t.status(for: repo), Paths.real(s.path) == Paths.real(path) { return t.title }
        }
        return nil
    }

    func tramaSlug(forCheckout path: String, repo: String) -> String? {
        for t in state?.tramas ?? [] {
            if let s = t.status(for: repo), Paths.real(s.path) == Paths.real(path) { return t.slug }
        }
        return nil
    }
}
