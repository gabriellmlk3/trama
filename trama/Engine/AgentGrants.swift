import Foundation

public struct AgentGrants: Codable, Hashable, Sendable {
    public var rules: [String] = []
    public var directories: [String] = []

    enum CodingKeys: String, CodingKey {
        case rules = "regras", directories = "pastas"
    }

    public init(rules: [String] = [], directories: [String] = []) {
        self.rules = rules
        self.directories = directories
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([String].self, forKey: .rules) ?? []
        directories = try c.decodeIfPresent([String].self, forKey: .directories) ?? []
    }

    public var isEmpty: Bool { rules.isEmpty && directories.isEmpty }

    public mutating func add(rule: String?, directory: String?) {
        if let rule, !rules.contains(rule) { rules.append(rule) }
        if let directory, !directories.contains(directory) { directories.append(directory) }
    }

    public mutating func remove(rule: String?, directory: String?) {
        if let rule { rules.removeAll { $0 == rule } }
        if let directory { directories.removeAll { $0 == directory } }
    }
}

extension Workspace {
    public func agentGrants(_ slug: String) -> AgentGrants {
        config.agentGrants[slug] ?? AgentGrants()
    }

    public func grantAgent(_ slug: String, rule: String?, directory: String?) throws {
        guard rule != nil || directory != nil else { return }
        try updateConfig { config in
            var grants = config.agentGrants[slug] ?? AgentGrants()
            grants.add(rule: rule, directory: directory)
            config.agentGrants[slug] = grants
        }
    }

    public func revokeAgent(_ slug: String, rule: String?, directory: String?) throws {
        try updateConfig { config in
            guard var grants = config.agentGrants[slug] else { return }
            grants.remove(rule: rule, directory: directory)
            config.agentGrants[slug] = grants.isEmpty ? nil : grants
        }
    }
}
