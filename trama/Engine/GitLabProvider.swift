import Foundation

struct GitLabProvider: PullRequestProvider {
    var kind: ProviderKind { .gitlab }
    var tool: CLITool { .glab }
    var bodyLimit: Int { 100000 }

    static func mergeRequestId(_ url: String) -> Int? {
        guard let range = url.range(of: "/merge_requests/") else { return nil }
        return Int(url[range.upperBound...].prefix(while: { $0.isNumber }))
    }

    static func state(_ value: String?) -> String {
        switch (value ?? "").lowercased() {
        case "merged": return "merged"
        case "closed", "locked": return "closed"
        default: return "open"
        }
    }

    static func ci(_ json: [String: Any]) -> String {
        let pipeline = (json["head_pipeline"] as? [String: Any]) ?? (json["pipeline"] as? [String: Any])
        switch (pipeline?["status"] as? String ?? "").lowercased() {
        case "success": return CIState.success
        case "failed", "canceled", "cancelled": return CIState.failure
        case "running", "pending", "created", "preparing", "waiting_for_resource", "scheduled": return CIState.pending
        default: return CIState.none
        }
    }

    private func argument(_ reference: String) -> String {
        reference.hasPrefix("http") ? Self.mergeRequestId(reference).map(String.init) ?? reference : reference
    }

    private func view(_ dir: String, _ reference: String) -> [String: Any]? {
        tool.json(dir, ["mr", "view", argument(reference), "--output", "json"], timeout: 30) as? [String: Any]
    }

    private func parse(_ json: [String: Any]) -> ExistingPullRequest? {
        guard let url = json["web_url"] as? String, !url.isEmpty else { return nil }
        return ExistingPullRequest(
            url: url,
            number: json["iid"] as? Int ?? 0,
            state: Self.state(json["state"] as? String),
            base: json["target_branch"] as? String ?? "",
            draft: (json["draft"] as? Bool) ?? (json["work_in_progress"] as? Bool) ?? false
        )
    }

    func existing(_ dir: String, _ reference: String) -> ExistingPullRequest? {
        view(dir, reference).flatMap(parse)
    }

    func create(_ dir: String, head: String, base: String, title: String, body: String, draft: Bool) throws -> String {
        var args = ["mr", "create", "--source-branch", head, "--target-branch", base, "--title", title, "--description=" + body, "--yes", "--no-editor"]
        if draft { args.append("--draft") }
        let r = tool.execute(dir, args, timeout: 90)
        guard r.code == 0 else {
            let message = r.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TramaError("glab mr create: \(message.isEmpty ? "código \(r.code)" : message)")
        }
        let text = r.output + "\n" + r.error
        if let range = text.range(of: #"https?://[^\s)]+/merge_requests/\d+"#, options: .regularExpression) {
            return String(text[range])
        }
        if let found = existing(dir, head) { return found.url }
        throw TramaError("o glab não devolveu o endereço do MR")
    }

    func retarget(_ dir: String, url: String, base: String) throws {
        try tool.run(dir, ["mr", "update", argument(url), "--target-branch", base])
    }

    func updateBody(_ dir: String, url: String, body: String) throws {
        try tool.run(dir, ["mr", "update", argument(url), "--description=" + body])
    }

    func status(_ dir: String, url: String) -> PullRequestStatus? {
        guard let json = view(dir, url), let current = parse(json) else { return nil }
        return PullRequestStatus(number: current.number, state: current.state, draft: current.draft, ci: Self.ci(json))
    }
}
