import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ServiceConfig: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var command: String
    public var port: Int

    enum CodingKeys: String, CodingKey {
        case name = "nome", command = "comando", port = "porta"
    }

    public var id: String { name }
}

public struct ServiceStatus: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var port: Int
    public var url: String
    public var running: Bool
    public var log: String

    public var id: String { name }
}

extension Workspace {
    public static let portBase = 3000
    public static let portStep = 10

    var runDir: String { Paths.join(stateDir, "run") }

    public func portOffset(_ t: Trama) -> Int {
        (t.portIndex ?? 0) * Workspace.portStep
    }

    public func servicePort(_ t: Trama, _ s: ServiceConfig) -> Int {
        s.port + portOffset(t)
    }

    func assignMissingPortIndexes() {
        guard let ts = try? tramas(), ts.contains(where: { !$0.isArchived && $0.portIndex == nil }) else { return }
        try? withLock {
            var all = try tramas()
            for i in all.indices where !all[i].isArchived && all[i].portIndex == nil {
                all[i].portIndex = Workspace.nextPortIndex(all)
            }
            try saveTramas(all)
        }
    }

    static func nextPortIndex(_ ts: [Trama]) -> Int {
        let used = Set(ts.filter { !$0.isArchived }.compactMap(\.portIndex))
        var i = 0
        while used.contains(i) { i += 1 }
        return i
    }

    private func servicePidPath(_ slug: String, _ repo: String, _ service: String) -> String {
        Paths.join(runDir, "\(slug)-\(repo)-\(service).pid")
    }

    public func serviceLogPath(_ slug: String, _ repo: String, _ service: String) -> String {
        Paths.join(logsDir, "\(slug)-\(repo)-\(service).servico.log")
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        if waitpid(pid, nil, WNOHANG) == pid { return false }
        return kill(pid, 0) == 0
    }

    private func servicePid(_ slug: String, _ repo: String, _ service: String) -> pid_t? {
        let path = servicePidPath(slug, repo, service)
        guard let text = try? File.read(path), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if pid > 1, Workspace.isAlive(pid), getsid(pid) == pid { return pid }
        try? FileManager.default.removeItem(atPath: path)
        return nil
    }

    public func serviceStatuses(_ t: Trama, _ r: RepoConfig) -> [ServiceStatus] {
        r.services.map { s in
            let port = servicePort(t, s)
            return ServiceStatus(
                name: s.name,
                port: port,
                url: "http://localhost:\(port)",
                running: servicePid(t.slug, r.name, s.name) != nil,
                log: serviceLogPath(t.slug, r.name, s.name)
            )
        }
    }

    static func portInUse(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected == 0 { return true }
        let probe = socket(AF_INET, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        addr.sin_addr.s_addr = in_addr_t(0)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound != 0 && errno == EADDRINUSE
    }

    @discardableResult
    public func setServices(_ key: String, _ services: [ServiceConfig]) throws -> RepoConfig {
        var r = try repo(key)
        var seen = Set<String>()
        var cleaned: [ServiceConfig] = []
        for s in services {
            let name = s.name.trimmingCharacters(in: .whitespaces)
            let command = s.command.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains("/"), !name.contains(" ") else { throw TramaError("o nome do serviço “\(s.name)” é inválido") }
            guard !command.isEmpty else { throw TramaError("o serviço “\(name)” precisa de um comando") }
            guard (1...(65535 - 1000)).contains(s.port) else { throw TramaError("a porta de “\(name)” precisa estar entre 1 e 64535") }
            guard seen.insert(name).inserted else { throw TramaError("já existe um serviço “\(name)” em \(r.name)") }
            cleaned.append(ServiceConfig(name: name, command: command, port: s.port))
        }
        r.services = cleaned
        try replaceRepo(r)
        return r
    }

    @discardableResult
    public func startServices(_ slug: String, repo key: String? = nil, service only: String? = nil) throws -> [ServiceStatus] {
        assignMissingPortIndexes()
        let t = try trama(slug)
        guard t.isActive else { throw TramaError("a trama “\(t.slug)” não está ativa · retome antes de subir os serviços") }
        let repos = try key.map { [try repo($0)] } ?? t.repos.compactMap { try? repo($0) }
        var started: [ServiceStatus] = []
        var matched = false
        for r in repos where t.repos.contains(r.name) {
            let wt = worktreePath(t.slug, r.name)
            for s in r.services where only == nil || only == s.name {
                matched = true
                if servicePid(t.slug, r.name, s.name) != nil { continue }
                guard Paths.isDirectory(wt) else { throw TramaError("worktree de \(r.name) não encontrado") }
                let port = servicePort(t, s)
                if Workspace.portInUse(port) {
                    throw TramaError("\(r.name)/\(s.name): a porta \(port) já está em uso · pare o que está nela ou mude a porta do serviço")
                }
                try spawnService(t, r, s, port: port)
                started.append(ServiceStatus(name: s.name, port: port, url: "http://localhost:\(port)", running: true, log: serviceLogPath(t.slug, r.name, s.name)))
            }
        }
        guard matched else { throw TramaError("nenhum serviço configurado · veja `trama repo servico`") }
        return started
    }

    private func spawnService(_ t: Trama, _ r: RepoConfig, _ s: ServiceConfig, port: Int) throws {
        #if canImport(Darwin)
        try FileManager.default.createDirectory(atPath: runDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(port)
        env["TRAMA_PORTA_BASE"] = String(Workspace.portBase + portOffset(t))
        env["TRAMA_WT"] = worktreePath(t.slug, r.name)
        env["TRAMA_CMD"] = s.command
        let script = "cd \"$TRAMA_WT\" && exec /bin/zsh -ilc \"$TRAMA_CMD\""
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, serviceLogPath(t.slug, r.name, s.name), O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        let argStrings = ["/bin/sh", "-c", script]
        let argv: [UnsafeMutablePointer<CChar>?] = argStrings.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/sh", &actions, &attr, argv, envp)
        guard rc == 0 else { throw TramaError("não consegui subir \(r.name)/\(s.name): \(String(cString: strerror(rc)))") }
        try File.write("\(pid)\n", to: servicePidPath(t.slug, r.name, s.name))
        #else
        throw TramaError("subir serviços só funciona no macOS")
        #endif
    }

    @discardableResult
    public func stopServices(_ slug: String, repo key: String? = nil, service only: String? = nil) -> Int {
        guard let t = try? trama(slug) else { return 0 }
        var stopped = 0
        var targets: [pid_t] = []
        for name in t.repos where key == nil || key == name {
            guard let r = try? repo(name) else { continue }
            for s in r.services where only == nil || only == s.name {
                guard let pid = servicePid(t.slug, r.name, s.name) else { continue }
                kill(-pid, SIGTERM)
                targets.append(pid)
                stopped += 1
            }
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, targets.contains(where: { Workspace.isAlive($0) || kill(-$0, 0) == 0 }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        for pid in targets where Workspace.isAlive(pid) || kill(-pid, 0) == 0 {
            kill(-pid, SIGKILL)
        }
        for name in t.repos {
            guard let r = try? repo(name) else { continue }
            for s in r.services where servicePid(t.slug, r.name, s.name) == nil {
                try? FileManager.default.removeItem(atPath: servicePidPath(t.slug, r.name, s.name))
            }
        }
        return stopped
    }

    func clearServiceLogs(_ slug: String, _ repos: [String]) {
        for name in repos {
            guard let r = try? repo(name) else { continue }
            for s in r.services {
                try? FileManager.default.removeItem(atPath: serviceLogPath(slug, name, s.name))
            }
        }
    }
}
