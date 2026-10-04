import AppKit
import Foundation

@MainActor
final class RateLimitStore: ObservableObject {
    static let shared = RateLimitStore()
    private static let key = "claudeRateLimits"
    private static let maxAge: TimeInterval = 15 * 60

    @Published private(set) var limits: RateLimits?
    @Published private(set) var refreshing = false
    private var polling: Task<Void, Never>?

    private init() {
        limits = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(RateLimits.self, from: $0) }
    }

    func update(_ new: RateLimits) {
        guard !new.windows.isEmpty || limits == nil else { return }
        limits = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                if let self, NSApp.isActive, self.isStale { await self.refresh() }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private var isStale: Bool {
        guard let limits else { return true }
        return Date().timeIntervalSince(limits.updatedAt) > Self.maxAge
    }

    func refresh() async {
        guard !refreshing, let executable = CLITool.claude.executable else { return }
        refreshing = true
        defer { refreshing = false }
        let found = await Task.detached(priority: .utility) { Self.probe(executable) }.value
        if let found { update(found) }
    }

    nonisolated private static func probe(_ executable: String) -> RateLimits? {
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        let result = ProcessRunner.run(
            executable,
            ["-p", "ok", "--model", "claude-haiku-4-5-20251001", "--output-format", "stream-json", "--verbose"],
            directory: NSTemporaryDirectory(),
            environment: environment,
            timeout: 60
        )
        var parser = AgentStreamParser()
        for line in result.output.split(separator: "\n") where line.contains("rate_limit_event") {
            for case .rateLimits(let limits) in parser.parse(String(line)) { return limits }
        }
        return nil
    }
}
