import Foundation

struct AzureProvider: PullRequestProvider {
    let coordinates: AzureCoordinates

    var kind: ProviderKind { .azure }
    var tool: CLITool { .az }
    var bodyLimit: Int { 4000 }

    private var organization: [String] {
        ["--organization", coordinates.organizationURL, "--detect", "false", "--output", "json"]
    }

    private var repository: [String] {
        organization + ["--project", coordinates.project, "--repository", coordinates.repository]
    }

    static func pullRequestId(_ url: String) -> Int? {
        guard let range = url.range(of: "/pullrequest/") else { return nil }
        let digits = url[range.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }

    static func shortRef(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    static func state(_ status: String?) -> String {
        switch (status ?? "").lowercased() {
        case "completed": return "merged"
        case "abandoned": return "closed"
        default: return "open"
        }
    }

    func existing(_ dir: String, _ reference: String) -> ExistingPullRequest? {
        if reference.hasPrefix("http") {
            guard let id = Self.pullRequestId(reference) else { return nil }
            return show(dir, id)
        }
        guard let list = tool.json(dir, ["repos", "pr", "list", "--source-branch", reference, "--status", "all"] + repository, timeout: 45) as? [[String: Any]] else {
            return nil
        }
        let matching = list.filter { item in
            guard let source = item["sourceRefName"] as? String else { return true }
            return Self.shortRef(source) == reference
        }
        let parsed = matching.compactMap(parse)
        return parsed.first { $0.state == "open" } ?? parsed.max { $0.number < $1.number }
    }

    private func show(_ dir: String, _ id: Int) -> ExistingPullRequest? {
        guard let json = tool.json(dir, ["repos", "pr", "show", "--id", String(id)] + organization, timeout: 30) as? [String: Any] else { return nil }
        return parse(json)
    }

    private func parse(_ json: [String: Any]) -> ExistingPullRequest? {
        guard let id = json["pullRequestId"] as? Int else { return nil }
        let web = ((json["repository"] as? [String: Any])?["webUrl"] as? String) ?? coordinates.webURL
        return ExistingPullRequest(
            url: web + "/pullrequest/\(id)",
            number: id,
            state: Self.state(json["status"] as? String),
            base: (json["targetRefName"] as? String).map(Self.shortRef) ?? "",
            draft: json["isDraft"] as? Bool ?? false
        )
    }

    func create(_ dir: String, head: String, base: String, title: String, body: String, draft: Bool) throws -> String {
        var args = ["repos", "pr", "create", "--source-branch", head, "--target-branch", base, "--title", title, "--description=" + body]
        if draft { args += ["--draft", "true"] }
        let out = try tool.run(dir, args + repository)
        guard let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let created = parse(json) else {
            throw TramaError("o az não devolveu o PR criado")
        }
        return created.url
    }

    func retarget(_ dir: String, url: String, base: String) throws {
        guard let id = Self.pullRequestId(url) else { throw TramaError("não entendi o endereço do PR: \(url)") }
        let file = NSTemporaryDirectory() + "/trama-az-" + UUID().uuidString + ".json"
        let payload = try JSONSerialization.data(withJSONObject: ["targetRefName": "refs/heads/" + base], options: [.withoutEscapingSlashes])
        try payload.write(to: URL(fileURLWithPath: file))
        defer { try? FileManager.default.removeItem(atPath: file) }
        let args = ["devops", "invoke", "--area", "git", "--resource", "pullRequests",
                    "--route-parameters", "project=\(coordinates.project)", "repositoryId=\(coordinates.repository)", "pullRequestId=\(id)",
                    "--http-method", "PATCH", "--in-file", file, "--api-version", "7.1"] + organization
        do {
            try tool.run(dir, args)
        } catch {
            throw TramaError("o Azure DevOps não trocou o destino do PR #\(id) para \(base): \(errorMessage(error)) · troque pelo site do PR")
        }
    }

    func updateBody(_ dir: String, url: String, body: String) throws {
        guard let id = Self.pullRequestId(url) else { throw TramaError("não entendi o endereço do PR: \(url)") }
        try tool.run(dir, ["repos", "pr", "update", "--id", String(id), "--description=" + body] + organization)
    }

    func status(_ dir: String, url: String) -> PullRequestStatus? {
        guard let id = Self.pullRequestId(url), let current = show(dir, id) else { return nil }
        let policies = tool.json(dir, ["repos", "pr", "policy", "list", "--id", String(id)] + organization, timeout: 30) as? [[String: Any]] ?? []
        return PullRequestStatus(number: current.number, state: current.state, draft: current.draft, ci: Self.ciState(policies))
    }

    static func ciState(_ evaluations: [[String: Any]]) -> String {
        let checkTypes: Set<String> = ["0609b952-1397-4640-95ec-e00a01b2c241", "cbdc66da-9728-4af8-aada-9a5a32e4a226"]
        let checkNames: Set<String> = ["build", "status"]
        let checks = evaluations.filter { evaluation in
            let type = (evaluation["configuration"] as? [String: Any])?["type"] as? [String: Any]
            let id = (type?["id"] as? String ?? "").lowercased()
            let name = (type?["displayName"] as? String ?? "").lowercased()
            return checkTypes.contains(id) || checkNames.contains(name)
        }
        guard !checks.isEmpty else { return CIState.none }
        var pending = false
        for check in checks {
            switch (check["status"] as? String ?? "").lowercased() {
            case "rejected", "broken":
                return CIState.failure
            case "queued", "running":
                pending = true
            default:
                break
            }
        }
        return pending ? CIState.pending : CIState.success
    }
}
