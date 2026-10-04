import Foundation

struct GitHubProvider: PullRequestProvider {
    var kind: ProviderKind { .github }
    var tool: CLITool { .gh }
    var bodyLimit: Int { 60000 }

    func existing(_ dir: String, _ reference: String) -> ExistingPullRequest? {
        let r = tool.execute(dir, ["pr", "view", reference, "--json", "url,number,state,baseRefName,isDraft"], timeout: 30)
        guard r.code == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any] else { return nil }
        var url = json["url"] as? String ?? ""
        if url.isEmpty, reference.hasPrefix("http") { url = reference }
        guard !url.isEmpty else { return nil }
        return ExistingPullRequest(
            url: url,
            number: json["number"] as? Int ?? 0,
            state: (json["state"] as? String ?? "").lowercased(),
            base: json["baseRefName"] as? String ?? "",
            draft: json["isDraft"] as? Bool ?? false
        )
    }

    func create(_ dir: String, head: String, base: String, title: String, body: String, draft: Bool) throws -> String {
        var args = ["pr", "create", "--base", base, "--head", head, "--title", title, "--body", body]
        if draft { args.append("--draft") }
        let out = try tool.run(dir, args)
        guard let url = out.split(separator: "\n").map(String.init).last(where: { $0.hasPrefix("http") }) else {
            throw TramaError("o gh não devolveu o endereço do PR")
        }
        return url
    }

    func retarget(_ dir: String, url: String, base: String) throws {
        try patch(dir, url: url, field: "base", value: base)
    }

    func updateBody(_ dir: String, url: String, body: String) throws {
        try patch(dir, url: url, field: "body", value: body)
    }

    private func patch(_ dir: String, url: String, field: String, value: String) throws {
        guard let parts = URLComponents(string: url),
              let host = parts.host else { throw TramaError("endereço de PR inválido: \(url)") }
        let path = parts.path.split(separator: "/").map(String.init)
        guard path.count >= 4, path[2] == "pull", Int(path[3]) != nil else {
            throw TramaError("endereço de PR inválido: \(url)")
        }
        try tool.run(dir, ["api", "--hostname", host, "-X", "PATCH", "repos/\(path[0])/\(path[1])/pulls/\(path[3])", "-f", "\(field)=\(value)"])
    }

    func status(_ dir: String, url: String) -> PullRequestStatus? {
        let r = tool.execute(dir, ["pr", "view", url, "--json", "number,state,isDraft,statusCheckRollup"], timeout: 30)
        guard r.code == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any] else { return nil }
        return PullRequestStatus(
            number: json["number"] as? Int ?? 0,
            state: (json["state"] as? String ?? "?").lowercased(),
            draft: json["isDraft"] as? Bool ?? false,
            ci: ciState(json["statusCheckRollup"] as? [[String: Any]] ?? [])
        )
    }
}
