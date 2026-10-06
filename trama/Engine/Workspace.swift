import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct RepoConfig: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var alias: String
    public var path: String
    public var label: String?
    public var base: String?
    public var copy: [String] = []
    public var run: [String] = []
    public var services: [ServiceConfig] = []
    public var mergeRank = 0
    public var editor: String?
    public var provider: ProviderKind?

    enum CodingKeys: String, CodingKey {
        case name = "nome", alias = "apelido", path = "caminho", label = "rotulo", base, copy = "copiar", run = "rodar"
        case services = "servicos", mergeRank = "ordemMerge", editor, provider = "provedor"
    }

    public var id: String { name }

    public var summary: String {
        if let r = label, !r.isEmpty { return r }
        return alias
    }
}

extension RepoConfig {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        alias = try c.decode(String.self, forKey: .alias)
        path = try c.decode(String.self, forKey: .path)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        base = try c.decodeIfPresent(String.self, forKey: .base)
        copy = try c.decodeIfPresent([String].self, forKey: .copy) ?? []
        run = try c.decodeIfPresent([String].self, forKey: .run) ?? []
        services = try c.decodeIfPresent([ServiceConfig].self, forKey: .services) ?? []
        mergeRank = try c.decodeIfPresent(Int.self, forKey: .mergeRank) ?? 0
        editor = try c.decodeIfPresent(String.self, forKey: .editor)
        provider = try? c.decode(ProviderKind.self, forKey: .provider)
    }
}

public enum AgentPullPolicy: String, Codable, Sendable {
    case free = "livre"
    case approval = "aprovacao"
}

public struct Config: Codable, Sendable {
    public static let currentVersion = 1

    public var version = Config.currentVersion
    public var branchPrefix = "trama/"
    public var defaultBranch = "main"
    public var context: String?
    public var capsuleFolder = "tramas"
    public var agentPullPolicy = AgentPullPolicy.free
    public var agentGrants: [String: AgentGrants] = [:]
    public var repos: [RepoConfig] = []
    public var automations: [Automation] = []

    enum CodingKeys: String, CodingKey {
        case version = "versao", branchPrefix = "prefixoBranch", defaultBranch = "basePadrao"
        case context = "contexto", capsuleFolder = "pastaCapsulas", agentPullPolicy = "puxadaDeAgentes", repos
        case agentGrants = "permissoesDeAgentes", automations = "automacoes"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Config.currentVersion
        branchPrefix = try c.decodeIfPresent(String.self, forKey: .branchPrefix) ?? ""
        defaultBranch = try c.decodeIfPresent(String.self, forKey: .defaultBranch) ?? ""
        context = try c.decodeIfPresent(String.self, forKey: .context)
        capsuleFolder = try c.decodeIfPresent(String.self, forKey: .capsuleFolder) ?? ""
        agentPullPolicy = (try? c.decodeIfPresent(AgentPullPolicy.self, forKey: .agentPullPolicy)) ?? .free
        agentGrants = (try? c.decodeIfPresent([String: AgentGrants].self, forKey: .agentGrants)) ?? [:]
        repos = try c.decodeIfPresent([RepoConfig].self, forKey: .repos) ?? []
        automations = (try? c.decodeIfPresent([Automation].self, forKey: .automations)) ?? []
        if branchPrefix.isEmpty { branchPrefix = "trama/" }
        if defaultBranch.isEmpty { defaultBranch = "main" }
        if capsuleFolder.isEmpty { capsuleFolder = "tramas" }
        if context?.isEmpty == true { context = nil }
    }
}

public enum TramaState {
    public static let active = "ativa"
    public static let parked = "estacionada"
    public static let archived = "arquivada"
}

public struct Trama: Codable, Hashable, Identifiable, Sendable {
    public var slug: String
    public var title: String
    public var branch: String
    public var base: String?
    public var repos: [String]
    public var state: String
    public var task: String?
    public var context: String?
    public var portIndex: Int?
    public var prs: [String: String] = [:]
    public var prBases: [String: String] = [:]
    public var createdAt: Int64
    public var parkedAt: Int64?
    public var updatedAt: Int64
    public var pinned = false
    public var order: Int?

    public var id: String { slug }
    public var isActive: Bool { state == TramaState.active }
    public var isParked: Bool { state == TramaState.parked }
    public var isArchived: Bool { state == TramaState.archived }

    enum CodingKeys: String, CodingKey {
        case slug, title = "titulo", branch, base, repos, state = "estado", task = "tarefa", context = "contexto"
        case portIndex = "indicePorta", prs, prBases = "destinosPR", createdAt = "criadaEm", parkedAt = "estacionadaEm", updatedAt = "atualizadaEm"
        case pinned = "fixada", order = "ordem"
    }

    init(slug: String, title: String, branch: String, base: String?, repos: [String], state: String, task: String?, createdAt: Int64) {
        self.slug = slug
        self.title = title
        self.branch = branch
        self.base = base
        self.repos = repos
        self.state = state
        self.task = task
        self.createdAt = createdAt
        self.parkedAt = nil
        self.updatedAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? slug
        branch = try c.decode(String.self, forKey: .branch)
        base = try c.decodeIfPresent(String.self, forKey: .base)
        repos = try c.decodeIfPresent([String].self, forKey: .repos) ?? []
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? TramaState.active
        task = try c.decodeIfPresent(String.self, forKey: .task)
        context = try c.decodeIfPresent(String.self, forKey: .context)
        portIndex = try c.decodeIfPresent(Int.self, forKey: .portIndex)
        prs = try c.decodeIfPresent([String: String].self, forKey: .prs) ?? [:]
        prBases = try c.decodeIfPresent([String: String].self, forKey: .prBases) ?? [:]
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        parkedAt = try c.decodeIfPresent(Int64.self, forKey: .parkedAt)
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? createdAt
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        order = try c.decodeIfPresent(Int.self, forKey: .order)
        if base?.isEmpty == true { base = nil }
        if task?.isEmpty == true { task = nil }
        if context?.isEmpty == true { context = nil }
        if parkedAt == 0 { parkedAt = nil }
    }
}

private struct TramasFile: Codable {
    static let currentVersion = 1

    var version = TramasFile.currentVersion
    var tramas: [Trama]

    enum CodingKeys: String, CodingKey {
        case version = "versao", tramas
    }

    init(tramas: [Trama]) {
        self.tramas = tramas
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? TramasFile.currentVersion
        tramas = try c.decode([Trama].self, forKey: .tramas)
    }
}

public final class Workspace {
    public let root: String
    public private(set) var config: Config

    public var executable: String

    init(root: String, config: Config) {
        self.root = root
        self.config = config
        self.executable = Workspace.currentExecutable()
    }

    public static func defaultRoot() -> String {
        if let v = ProcessInfo.processInfo.environment["TRAMA_HOME"], !v.isEmpty {
            return Paths.absolute(v)
        }
        return Paths.join(Paths.home, "Tramas")
    }

    public static func currentExecutable() -> String {
        #if os(Linux)
        if let p = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") {
            return p
        }
        #endif
        if let p = Bundle.main.executablePath {
            return Paths.real(p)
        }
        return Paths.real(Paths.absolute(CommandLine.arguments.first ?? "trama"))
    }

    var stateDir: String { Paths.join(root, ".trama") }
    var configPath: String { Paths.join(stateDir, "config.json") }
    var tramasPath: String { Paths.join(stateDir, "tramas.json") }
    var lockPath: String { Paths.join(stateDir, "lock") }
    public var agentsDir: String { Paths.join(stateDir, "agentes") }

    public func tramaPath(_ slug: String) -> String {
        Paths.join(root, slug)
    }

    public func worktreePath(_ slug: String, _ repo: String) -> String {
        Paths.join(root, slug, repo)
    }

    public static func open(root: String? = nil) throws -> Workspace {
        let r = Paths.absolute(root ?? defaultRoot())
        let path = Paths.join(r, ".trama", "config.json")
        guard let text = try File.read(path) else {
            throw TramaError.notInitialized
        }
        return Workspace(root: r, config: try decodeConfig(text, path: path))
    }

    @discardableResult
    public static func configure(root: String? = nil, context: String? = nil) throws -> Workspace {
        let r = Paths.absolute(root ?? defaultRoot())
        let w: Workspace
        do {
            w = try open(root: r)
        } catch let e as TramaError where e == .notInitialized {
            w = Workspace(root: r, config: Config())
        }
        try FileManager.default.createDirectory(atPath: w.agentsDir, withIntermediateDirectories: true)
        if let context, !context.trimmingCharacters(in: .whitespaces).isEmpty {
            let c = Paths.absolute(context)
            guard Paths.isDirectory(c) else {
                throw TramaError("pasta de contexto não encontrada: \(c)")
            }
            try w.updateConfig { $0.context = c }
        } else {
            try w.saveConfig()
        }
        return w
    }

    public func saveConfig() throws {
        try withLock { try writeConfig() }
    }

    private func writeConfig() throws {
        let data = try JSON.encoder().encode(config)
        try File.write(data + Data("\n".utf8), to: configPath)
    }

    private func reloadConfig() throws {
        guard let text = try File.read(configPath) else { return }
        config = try Workspace.decodeConfig(text, path: configPath)
    }

    @discardableResult
    func updateConfig<T>(_ change: (inout Config) throws -> T) throws -> T {
        try withLock {
            try reloadConfig()
            var updated = config
            let result = try change(&updated)
            config = updated
            try writeConfig()
            return result
        }
    }

    static func decodeConfig(_ text: String, path: String) throws -> Config {
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: Data(text.utf8))
        } catch {
            throw TramaError("config.json inválido (\(path)): \(error.localizedDescription)")
        }
        guard config.version <= Config.currentVersion else {
            throw TramaError("config.json é da versão \(config.version), mais nova que a \(Config.currentVersion) que este Trama entende · atualize o Trama")
        }
        return config
    }

    func replaceRepo(_ r: RepoConfig) throws {
        try updateConfig { config in
            guard let i = config.repos.firstIndex(where: { $0.name == r.name }) else { return }
            config.repos[i] = r
        }
    }

    public func setDefaultBranch(_ branch: String) throws {
        let b = branch.trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty else { throw TramaError("informe o nome da branch") }
        try updateConfig { $0.defaultBranch = b }
    }

    public func setAgentPullPolicy(_ policy: AgentPullPolicy) throws {
        try updateConfig { $0.agentPullPolicy = policy }
    }

    public func repo(_ key: String) throws -> RepoConfig {
        let key = key.trimmingCharacters(in: .whitespaces)
        if let r = config.repos.first(where: { $0.name == key }) { return r }
        if let r = config.repos.first(where: { $0.alias == key }) { return r }
        let lower = key.lowercased()
        let found = config.repos.filter { r in
            let n = r.name.lowercased()
            return n == lower || r.alias.lowercased() == lower || n.hasSuffix("-" + lower) || n.hasSuffix("_" + lower)
        }
        if found.count == 1 { return found[0] }
        if found.count > 1 {
            throw TramaError("“\(key)” é ambíguo · use o nome completo do repositório")
        }
        throw TramaError("o repositório “\(key)” não está cadastrado (veja `trama repo ls`)")
    }

    public func base(for trama: Trama?, _ r: RepoConfig) -> String {
        if let b = trama?.base, !b.isEmpty { return b }
        if let b = r.base, !b.isEmpty { return b }
        return config.defaultBranch
    }

    static func deriveAlias(_ name: String) -> String {
        if let i = name.lastIndex(where: { $0 == "-" || $0 == "_" }), name.index(after: i) < name.endIndex {
            return String(name[name.index(after: i)...])
        }
        return name
    }

    @discardableResult
    public func addRepo(_ path: String, alias: String? = nil, label: String? = nil, base: String? = nil) throws -> RepoConfig {
        let a = Paths.absolute(path)
        guard let top = try? Git.toplevel(a), !top.isEmpty else {
            throw TramaError("\(Paths.abbreviate(a)) não é um repositório git")
        }
        let topPath = Paths.clean(top)
        let name = Paths.name(topPath)
        let suggestion = RecipeSuggestion.forRepo(topPath)
        let finalBase = (base?.isEmpty == false ? base! : Git.probableBase(topPath))
        return try updateConfig { config in
            if let r = config.repos.first(where: { Paths.real($0.path) == Paths.real(topPath) }) {
                throw TramaError("\(Paths.abbreviate(topPath)) já está cadastrado como “\(r.name)”")
            }
            if config.repos.contains(where: { $0.name == name }) {
                throw TramaError("já existe um repositório chamado “\(name)”")
            }
            var finalAlias = (alias?.isEmpty == false ? alias! : Workspace.deriveAlias(name))
            if config.repos.contains(where: { $0.alias == finalAlias }) {
                finalAlias = name
            }
            let r = RepoConfig(
                name: name,
                alias: finalAlias,
                path: topPath,
                label: label?.isEmpty == false ? label : nil,
                base: finalBase,
                copy: suggestion.copy,
                run: suggestion.run
            )
            config.repos.append(r)
            config.repos.sort { $0.name < $1.name }
            return r
        }
    }

    @discardableResult
    public func removeRepo(_ key: String) throws -> RepoConfig {
        let r = try repo(key)
        if let t = try tramas().first(where: { !$0.isArchived && $0.repos.contains(r.name) }) {
            throw TramaError("\(r.name) ainda faz parte da trama “\(t.slug)”")
        }
        try updateConfig { $0.repos.removeAll { $0.name == r.name } }
        return r
    }

    public func tramas() throws -> [Trama] {
        guard let text = try File.read(tramasPath) else { return [] }
        let file: TramasFile
        do {
            file = try JSONDecoder().decode(TramasFile.self, from: Data(text.utf8))
        } catch {
            throw TramaError("tramas.json inválido: \(error.localizedDescription)")
        }
        guard file.version <= TramasFile.currentVersion else {
            throw TramaError("tramas.json é da versão \(file.version), mais nova que a \(TramasFile.currentVersion) que este Trama entende · atualize o Trama")
        }
        return file.tramas
    }

    public func trama(_ slug: String) throws -> Trama {
        let ts = try tramas()
        if let t = ts.first(where: { $0.slug == slug }) { return t }
        let candidates = ts.filter { !$0.isArchived && $0.slug.hasPrefix(slug) }
        if candidates.count == 1 { return candidates[0] }
        if candidates.count > 1 {
            throw TramaError("“\(slug)” combina com mais de uma trama")
        }
        throw TramaError("trama “\(slug)” não encontrada")
    }

    func saveTramas(_ ts: [Trama]) throws {
        let sorted = ts.sorted { $0.createdAt < $1.createdAt }
        let data = try JSON.encoder().encode(TramasFile(tramas: sorted))
        try File.write(data + Data("\n".utf8), to: tramasPath)
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        #if canImport(Darwin)
        let fd = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o644)
        #else
        let fd = Glibc.open(lockPath, O_CREAT | O_RDWR, 0o644)
        #endif
        guard fd >= 0 else {
            throw TramaError("não consegui abrir \(lockPath)")
        }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    @discardableResult
    func updateTrama(_ slug: String, _ change: (inout Trama) throws -> Void) throws -> Trama {
        try withLock {
            var ts = try tramas()
            guard let i = ts.firstIndex(where: { $0.slug == slug }) else {
                throw TramaError("trama “\(slug)” não encontrada")
            }
            try change(&ts[i])
            ts[i].updatedAt = nowUnix()
            try saveTramas(ts)
            return ts[i]
        }
    }
}
