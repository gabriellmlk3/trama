import Foundation

public enum AutomationEvent: String, Codable, CaseIterable, Sendable {
    case focus = "focar"
    case unfocus = "desfocar"
    case create = "criar"
    case pull = "incluir"
    case park = "estacionar"
    case resume = "retomar"

    public var label: String {
        switch self {
        case .focus: return "ao focar"
        case .unfocus: return "ao sair do foco"
        case .create: return "ao criar"
        case .pull: return "ao incluir repositório"
        case .park: return "ao estacionar"
        case .resume: return "ao retomar"
        }
    }

    static func parse(_ text: String) throws -> [AutomationEvent] {
        let values = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        return try values.map { value in
            guard let event = AutomationEvent(rawValue: value) else {
                throw TramaError("evento desconhecido: \(value) (use \(AutomationEvent.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            return event
        }
    }
}

public enum AutomationScope: String, Codable, CaseIterable, Sendable {
    case worktrees
    case trama
    case primaries = "principais"

    public var label: String {
        switch self {
        case .worktrees: return "em cada worktree"
        case .trama: return "na pasta da trama"
        case .primaries: return "na cópia principal"
        }
    }

    static func parse(_ text: String) throws -> AutomationScope {
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "worktrees", "worktree": return .worktrees
        case "trama": return .trama
        case "principais", "principal": return .primaries
        default: throw TramaError("onde rodar: worktrees, trama ou principal")
        }
    }
}

public enum AutomationKind: String, Codable, CaseIterable, Sendable {
    case command = "comando"
    case paths = "caminhos"
}

public enum AutomationRunState {
    public static let running = "rodando"
    public static let done = "pronto"
    public static let failed = "falhou"
}

public struct Automation: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: AutomationKind
    public var events: [AutomationEvent]
    public var scope: AutomationScope
    public var repos: [String]
    public var command: String
    public var files: [String]
    public var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name = "nome", kind = "tipo", events = "quando", scope = "onde", repos, command = "comando", files = "arquivos"
        case enabled = "ativa"
    }

    public init(id: String = Automation.newID(), name: String, kind: AutomationKind = .command, events: [AutomationEvent] = [],
                scope: AutomationScope, repos: [String] = [], command: String = "", files: [String] = [], enabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.events = events
        self.scope = scope
        self.repos = repos
        self.command = command
        self.files = files
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Automation.newID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        let rawKind = try c.decodeIfPresent(String.self, forKey: .kind) ?? AutomationKind.command.rawValue
        kind = AutomationKind(rawValue: rawKind) ?? .command
        events = (try c.decodeIfPresent([String].self, forKey: .events) ?? []).compactMap(AutomationEvent.init(rawValue:))
        let rawScope = try c.decodeIfPresent(String.self, forKey: .scope) ?? AutomationScope.worktrees.rawValue
        scope = AutomationScope(rawValue: rawScope) ?? .worktrees
        repos = try c.decodeIfPresent([String].self, forKey: .repos) ?? []
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        let understood = AutomationScope(rawValue: rawScope) != nil && AutomationKind(rawValue: rawKind) != nil
        enabled = (try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true) && understood
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    public var followsFocus: Bool { kind == .paths && scope == .primaries }

    public var when: String {
        switch kind {
        case .command: return events.map(\.label).joined(separator: ", ")
        case .paths: return scope == .primaries ? "enquanto uma trama estiver em foco" : "em todas as tramas"
        }
    }

    public var action: String {
        switch kind {
        case .command: return command.replacingOccurrences(of: "\n", with: " ⏎ ")
        case .paths: return "apontar caminhos em " + files.joined(separator: ", ")
        }
    }

    public var summary: String {
        let target = repos.isEmpty ? "" : (scope == .primaries ? " de " : " · só ") + repos.joined(separator: ", ")
        return "\(when) · \(scope.label)\(target)"
    }
}

struct AutomationBatch {
    var trama: Trama
    var event: AutomationEvent
    var added: [String] = []
}

extension Workspace {
    public func automationLogPath(_ slug: String) -> String {
        Paths.join(logsDir, "\(slug)-automacoes.log")
    }

    private func automationStatePath(_ slug: String) -> String {
        Paths.join(logsDir, "\(slug)-automacoes.estado")
    }

    public func automationState(_ slug: String) -> String? {
        guard let text = try? File.read(automationStatePath(slug)) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func automation(_ key: String) throws -> Automation {
        let list = config.automations
        let k = key.trimmingCharacters(in: .whitespaces)
        if let n = Int(k), n >= 1, n <= list.count { return list[n - 1] }
        if let a = list.first(where: { $0.id == k }) { return a }
        let matches = list.filter { $0.name.lowercased() == k.lowercased() }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 { throw TramaError("há mais de uma automação chamada “\(k)” · use o número (veja `trama automacao`)") }
        throw TramaError("automação “\(k)” não encontrada (veja `trama automacao`)")
    }

    private func validated(_ input: Automation) throws -> Automation {
        var a = input
        a.name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
        a.command = a.command.trimmingCharacters(in: .whitespacesAndNewlines)
        a.files = a.files.flatMap { $0.split(whereSeparator: { $0 == "," || $0 == "\n" }) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch a.kind {
        case .command:
            guard !a.command.isEmpty else { throw TramaError("informe o comando da automação") }
            guard !a.events.isEmpty else { throw TramaError("escolha quando a automação roda") }
            a.files = []
            if a.name.isEmpty { a.name = String(a.command.split(separator: "\n").first ?? "").prefix(40).description }
        case .paths:
            guard !a.files.isEmpty else { throw TramaError("informe em quais arquivos apontar os caminhos") }
            for f in a.files where f.hasPrefix("/") || f.hasPrefix("~") || f.split(separator: "/").contains("..") {
                throw TramaError("o arquivo “\(f)” precisa ser relativo à pasta do repositório")
            }
            guard a.scope != .trama else { throw TramaError("caminhos são ajustados nos worktrees ou na cópia principal") }
            a.events = []
            a.command = ""
            if a.name.isEmpty { a.name = "Caminhos em " + a.files.joined(separator: ", ") }
        }
        a.events = AutomationEvent.allCases.filter { a.events.contains($0) }
        var names: [String] = []
        for key in a.repos.flatMap({ $0.split(separator: ",") }).map({ $0.trimmingCharacters(in: .whitespaces) }) where !key.isEmpty {
            let n = try repo(key).name
            if !names.contains(n) { names.append(n) }
        }
        a.repos = a.scope == .trama ? [] : names
        if a.scope == .primaries && a.repos.isEmpty {
            throw TramaError("na cópia principal, escolha em quais repositórios a automação age")
        }
        return a
    }

    @discardableResult
    public func saveAutomation(_ input: Automation) throws -> (automation: Automation, warnings: [Warning]) {
        let saved = try validated(input)
        let previous = config.automations.first { $0.id == saved.id }
        try updateConfig { config in
            if let i = config.automations.firstIndex(where: { $0.id == saved.id }) {
                config.automations[i] = saved
            } else {
                config.automations.append(saved)
            }
        }
        var warnings: [Warning] = []
        if let previous, previous.followsFocus, previous.enabled {
            warnings += applyFocusPathRules(nil, rules: [previous])
        }
        warnings += applyAllPathRules()
        return (saved, warnings)
    }

    @discardableResult
    public func removeAutomation(_ key: String) throws -> (automation: Automation, warnings: [Warning]) {
        let a = try automation(key)
        try updateConfig { $0.automations.removeAll { $0.id == a.id } }
        var warnings: [Warning] = []
        if a.followsFocus && a.enabled {
            warnings += applyFocusPathRules(nil, rules: [a])
            warnings += applyAllPathRules()
        }
        return (a, warnings)
    }

    @discardableResult
    public func setAutomationEnabled(_ key: String, _ enabled: Bool) throws -> (automation: Automation, warnings: [Warning]) {
        var a = try automation(key)
        a.enabled = enabled
        return try saveAutomation(a)
    }

    private static func environmentName(_ repo: String) -> String {
        "TRAMA_CAMINHO_" + String(repo.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func automationEnvironment(_ b: AutomationBatch) -> [(String, String)] {
        var env: [(String, String)] = [
            ("TRAMA_RAIZ", root),
            ("TRAMA_SLUG", b.trama.slug),
            ("TRAMA_TITULO", b.trama.title),
            ("TRAMA_BRANCH", b.trama.branch),
            ("TRAMA_DIR", tramaPath(b.trama.slug)),
            ("TRAMA_EVENTO", b.event.rawValue),
            ("TRAMA_REPOS", b.trama.repos.joined(separator: " ")),
            ("TRAMA_NOVOS", b.added.joined(separator: " ")),
        ]
        for r in config.repos {
            let path = b.trama.repos.contains(r.name) ? worktreePath(b.trama.slug, r.name) : r.path
            env.append((Workspace.environmentName(r.name), path))
        }
        return env
    }

    func automationSteps(_ b: AutomationBatch, from list: [Automation]) -> [(automation: Automation, dir: String, repo: String)] {
        let primariesAllowed = b.event == .focus || b.event == .unfocus || focusedSlug() == b.trama.slug
        var steps: [(Automation, String, String)] = []
        for a in list where a.enabled && a.kind == .command && a.events.contains(b.event) {
            switch a.scope {
            case .trama:
                steps.append((a, tramaPath(b.trama.slug), ""))
            case .worktrees:
                for name in b.trama.repos where a.repos.isEmpty || a.repos.contains(name) {
                    let wt = worktreePath(b.trama.slug, name)
                    if Paths.isDirectory(wt) { steps.append((a, wt, name)) }
                }
            case .primaries:
                guard primariesAllowed else { continue }
                for name in a.repos {
                    guard let r = try? repo(name) else { continue }
                    steps.append((a, r.path, r.name))
                }
            }
        }
        return steps
    }

    @discardableResult
    func runAutomations(_ batches: [AutomationBatch], logOwner slug: String, using list: [Automation]? = nil) -> [Warning] {
        let automations = list ?? config.automations
        let planned = batches.map { ($0, automationSteps($0, from: automations)) }.filter { !$0.1.isEmpty }
        guard !planned.isEmpty else { return [] }
        let log = automationLogPath(slug)
        let statePath = automationStatePath(slug)
        var header = "# automações · \(Timestamp.string())\n"
        var script = """
        status=0
        passo() {
          printf '\\n▸ %s\\n  %s\\n' "$1" "$2" >> "$TRAMA_LOG"
          if (cd "$2" && TRAMA_REPO="$3" exec /bin/zsh -ilc "$4") >> "$TRAMA_LOG" 2>&1; then
            printf '✓ ok\\n' >> "$TRAMA_LOG"
          else
            printf '✗ falhou (código %s)\\n' "$?" >> "$TRAMA_LOG"
            status=1
          fi
        }

        """
        for (batch, steps) in planned {
            header += "\(batch.event.label): \(batch.trama.title) (\(batch.trama.slug))\n"
            let exports = automationEnvironment(batch).map { "\($0.0)=\(Workspace.quoted($0.1))" }
            script += "export " + exports.joined(separator: " ") + "\n"
            for (a, dir, repo) in steps {
                let title = "\(a.name) · \(batch.event.label)" + (repo.isEmpty ? "" : " · \(repo)")
                script += "passo \(Workspace.quoted(title)) \(Workspace.quoted(dir)) \(Workspace.quoted(repo)) \(Workspace.quoted(a.command))\n"
            }
        }
        script += """
        if [ "$status" -eq 0 ]; then echo \(AutomationRunState.done) > "$TRAMA_STATE"; else echo \(AutomationRunState.failed) > "$TRAMA_STATE"; fi

        """
        do {
            try File.write(header, to: log)
            try File.write(AutomationRunState.running + "\n", to: statePath)
            var env = ProcessInfo.processInfo.environment
            env["TRAMA_LOG"] = log
            env["TRAMA_STATE"] = statePath
            try ProcessRunner.spawnDetached("/bin/sh", ["-c", script], environment: env)
            return []
        } catch {
            try? File.write(AutomationRunState.failed + "\n", to: statePath)
            return [Warning(message: "não consegui rodar as automações: \(errorMessage(error))")]
        }
    }

    @discardableResult
    func fire(_ event: AutomationEvent, _ t: Trama, added: [String] = []) -> [Warning] {
        runAutomations([AutomationBatch(trama: t, event: event, added: added)], logOwner: t.slug)
    }

    @discardableResult
    public func runAutomation(_ key: String, trama slug: String, event: AutomationEvent? = nil) throws -> [Warning] {
        let a = try automation(key)
        let t = try trama(slug)
        guard !t.isArchived else { throw TramaError("essa trama está arquivada") }
        var only = a
        only.enabled = true
        if a.kind == .paths {
            if a.scope == .primaries {
                guard focusedSlug() == t.slug else {
                    throw TramaError("“\(a.name)” segue a trama em foco · foque \(t.slug) com `trama focar \(t.slug)`")
                }
                return applyFocusPathRules(t, rules: [only])
            }
            return applyWorktreePathRules(t, rules: [only])
        }
        guard let e = event ?? a.events.first else { throw TramaError("a automação não tem evento") }
        only.events = [e]
        let batch = AutomationBatch(trama: t, event: e)
        guard !automationSteps(batch, from: [only]).isEmpty else {
            let hint = a.scope == .primaries && e != .focus && e != .unfocus ? " (na cópia principal, só a trama em foco dispara)" : ""
            throw TramaError("nada para rodar: “\(a.name)” não tem onde rodar em \(t.slug)\(hint)")
        }
        return runAutomations([batch], logOwner: t.slug, using: [only])
    }
}
