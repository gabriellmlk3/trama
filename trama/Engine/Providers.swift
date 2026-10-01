import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case github
    case azure
    case gitlab
    case bitbucket
    case manual

    public var title: String {
        switch self {
        case .github: return "GitHub"
        case .azure: return "Azure DevOps"
        case .gitlab: return "GitLab"
        case .bitbucket: return "Bitbucket"
        case .manual: return "Outro"
        }
    }

    public static func named(_ text: String) -> ProviderKind? {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "github", "gh": return .github
        case "azure", "azure-devops", "azuredevops", "devops", "ado", "az": return .azure
        case "gitlab", "glab": return .gitlab
        case "bitbucket": return .bitbucket
        case "manual", "outro": return .manual
        default: return nil
        }
    }
}

public struct AzureCoordinates: Hashable, Sendable {
    public var organizationURL: String
    public var project: String
    public var repository: String

    public var webURL: String {
        organizationURL + "/" + pathEncoded(project) + "/_git/" + pathEncoded(repository)
    }
}

func pathEncoded(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
}

func queryEncoded(_ text: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
}

public struct RemoteRepo: Hashable, Sendable {
    public var scheme: String
    public var host: String
    public var segments: [String]
    public var sshAzure: Bool

    public static func parse(_ raw: String) -> RemoteRepo? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var scheme = "ssh"
        var authority: String
        var path: String
        var hasPort = false
        if let range = text.range(of: "://") {
            scheme = String(text[..<range.lowerBound]).lowercased()
            guard scheme != "file" else { return nil }
            let rest = String(text[range.upperBound...])
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            authority = String(rest[..<slash])
            path = String(rest[rest.index(after: slash)...])
            hasPort = true
        } else if let colon = text.firstIndex(of: ":"), !text.hasPrefix("/"), !text.hasPrefix(".") {
            authority = String(text[..<colon])
            path = String(text[text.index(after: colon)...])
        } else {
            return nil
        }
        if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
        if hasPort, let colon = authority.lastIndex(of: ":") { authority = String(authority[..<colon]) }
        let host = authority.lowercased()
        guard !host.isEmpty else { return nil }
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<cut]) }
        var segments = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if var last = segments.last, last.hasSuffix(".git") {
            last.removeLast(4)
            segments[segments.count - 1] = last
        }
        let sshAzure = host == "ssh.dev.azure.com" || host.hasSuffix("vs-ssh.visualstudio.com")
        if sshAzure, segments.first == "v3" { segments.removeFirst() }
        guard !segments.isEmpty else { return nil }
        return RemoteRepo(scheme: scheme, host: host, segments: segments, sshAzure: sshAzure)
    }

    public var detectedKind: ProviderKind {
        if host == "dev.azure.com" || host == "ssh.dev.azure.com" || host.hasSuffix(".visualstudio.com") || segments.contains("_git") {
            return .azure
        }
        if host.contains("github") { return .github }
        if host.contains("gitlab") { return .gitlab }
        if host.contains("bitbucket") { return .bitbucket }
        return .manual
    }

    public var webURL: String {
        (scheme == "http" ? "http" : "https") + "://" + host + "/" + segments.map(pathEncoded).joined(separator: "/")
    }

    public var azure: AzureCoordinates? {
        if sshAzure {
            guard segments.count >= 3 else { return nil }
            let organization = host.hasSuffix("visualstudio.com") ? "https://\(segments[0]).visualstudio.com" : "https://dev.azure.com/" + pathEncoded(segments[0])
            return AzureCoordinates(organizationURL: organization, project: segments[1], repository: segments[2])
        }
        guard let git = segments.firstIndex(of: "_git"), git + 1 < segments.count else { return nil }
        let repository = segments[git + 1]
        let before = Array(segments[..<git])
        if host == "dev.azure.com" {
            guard let organization = before.first else { return nil }
            let project = before.count >= 2 ? before[before.count - 1] : repository
            return AzureCoordinates(organizationURL: "https://dev.azure.com/" + pathEncoded(organization), project: project, repository: repository)
        }
        if host.hasSuffix(".visualstudio.com") {
            let organization = String(host.dropLast(".visualstudio.com".count))
            let named = before.filter { $0.lowercased() != "defaultcollection" }
            return AzureCoordinates(organizationURL: "https://\(organization).visualstudio.com", project: named.last ?? repository, repository: repository)
        }
        let collection = before.dropLast().map(pathEncoded).joined(separator: "/")
        let base = (scheme == "http" ? "http" : "https") + "://" + host + (collection.isEmpty ? "" : "/" + collection)
        return AzureCoordinates(organizationURL: base, project: before.last ?? repository, repository: repository)
    }

    public func newPullRequestURL(kind: ProviderKind, branch: String, target: String) -> String {
        switch kind {
        case .github:
            return webURL + "/compare/" + pathEncoded(target) + "..." + pathEncoded(branch) + "?expand=1"
        case .azure:
            guard let azure else { return webURL }
            return azure.webURL + "/pullrequestcreate?sourceRef=\(queryEncoded(branch))&targetRef=\(queryEncoded(target))"
        case .gitlab:
            return webURL + "/-/merge_requests/new?merge_request%5Bsource_branch%5D=\(queryEncoded(branch))&merge_request%5Btarget_branch%5D=\(queryEncoded(target))"
        case .bitbucket:
            guard host == "bitbucket.org" else { return webURL }
            return webURL + "/pull-requests/new?source=\(queryEncoded(branch))&dest=\(queryEncoded(target))"
        case .manual:
            return webURL
        }
    }
}

struct PullRequestStatus {
    var number: Int
    var state: String
    var draft: Bool
    var ci: String
}

protocol PullRequestProvider: Sendable {
    var kind: ProviderKind { get }
    var tool: CLITool { get }
    var bodyLimit: Int { get }
    func existing(_ dir: String, _ reference: String) -> ExistingPullRequest?
    func create(_ dir: String, head: String, base: String, title: String, body: String, draft: Bool) throws -> String
    func retarget(_ dir: String, url: String, base: String) throws
    func updateBody(_ dir: String, url: String, body: String) throws
    func status(_ dir: String, url: String) -> PullRequestStatus?
}

struct RepoHost {
    var kind: ProviderKind
    var remote: RemoteRepo?
    var provider: (any PullRequestProvider)?

    var automatic: (any PullRequestProvider)? {
        guard let provider, provider.tool.executable != nil else { return nil }
        return provider
    }

    var missingTool: CLITool? {
        guard let provider, provider.tool.executable == nil else { return nil }
        return provider.tool
    }

    func newPullRequestURL(branch: String, target: String) -> String? {
        remote?.newPullRequestURL(kind: kind, branch: branch, target: target)
    }
}

extension Workspace {
    func host(for r: RepoConfig, dir: String) -> RepoHost {
        let remote = Git.remoteURL(dir).flatMap { RemoteRepo.parse($0) }
        let kind = r.provider ?? remote?.detectedKind ?? .manual
        var provider: (any PullRequestProvider)?
        switch kind {
        case .github:
            provider = GitHubProvider()
        case .azure:
            if let coordinates = remote?.azure { provider = AzureProvider(coordinates: coordinates) }
        case .gitlab:
            provider = GitLabProvider()
        case .bitbucket, .manual:
            break
        }
        return RepoHost(kind: kind, remote: remote, provider: provider)
    }

    public func providerKind(for r: RepoConfig, dir: String? = nil) -> ProviderKind {
        host(for: r, dir: dir ?? r.path).kind
    }

    @discardableResult
    public func setProvider(_ key: String, _ kind: ProviderKind?) throws -> RepoConfig {
        var r = try repo(key)
        r.provider = kind
        try replaceRepo(r)
        return r
    }
}
