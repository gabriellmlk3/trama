import Foundation
import Security

struct GitCredential: Codable, Hashable, Identifiable, Sendable {
    var kind: ProviderKind
    var host: String
    var username: String?
    var token: String

    var id: String { host }
}

extension ProviderKind {
    /// Provedores que aceitam token por HTTPS.
    static let withCredentials: [ProviderKind] = [.github, .gitlab, .azure, .bitbucket]

    var defaultHost: String {
        switch self {
        case .github: return "github.com"
        case .gitlab: return "gitlab.com"
        case .azure: return "dev.azure.com"
        case .bitbucket: return "bitbucket.org"
        case .manual: return ""
        }
    }

    var needsUsername: Bool { self == .bitbucket }

    var tokenHint: String {
        switch self {
        case .github: return "Token com escopo repo"
        case .gitlab: return "Token com escopos api e write_repository"
        case .azure: return "Token (PAT) com Code: Read & write"
        case .bitbucket: return "Senha de app ou token com acesso a repositórios"
        case .manual: return "Token"
        }
    }

    /// Ferramenta de linha de comando do provedor, se houver.
    var cliName: String? {
        switch self {
        case .github: return "gh"
        case .gitlab: return "glab"
        case .azure: return "az"
        default: return nil
        }
    }

    func tokenPage(host: String, organization: String) -> URL? {
        switch self {
        case .github:
            return URL(string: "https://\(host)/settings/tokens/new?scopes=repo&description=Trama")
        case .gitlab:
            return URL(string: "https://\(host)/-/user_settings/personal_access_tokens?name=Trama&scopes=api,write_repository")
        case .azure:
            let org = organization.trimmingCharacters(in: .whitespaces)
            return URL(string: org.isEmpty ? "https://dev.azure.com" : "https://dev.azure.com/\(pathEncoded(org))/_usersSettings/tokens")
        case .bitbucket:
            return URL(string: "https://\(host)/account/settings/app-passwords/")
        case .manual:
            return nil
        }
    }

    /// Comando que instala a CLI (se faltar) e abre o login dela no terminal.
    func loginCommand(host: String) -> String? {
        switch self {
        case .github:
            return "(command -v gh >/dev/null || brew install gh) && gh auth login -h \(host) -p https -w && gh auth setup-git"
        case .gitlab:
            return "(command -v glab >/dev/null || brew install glab) && glab auth login -h \(host)"
        case .azure:
            return "(command -v az >/dev/null || brew install azure-cli) && az extension add --name azure-devops --yes && az login"
        case .bitbucket, .manual:
            return nil
        }
    }
}

enum GitCredentials {
    private static let service = "com.trama.git-credentials"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [GitCredential]?

    static func all() -> [GitCredential] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let loaded = load()
        cache = loaded
        return loaded
    }

    private static func load() -> [GitCredential] {
        let list: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(list as CFDictionary, &items) == errSecSuccess,
              let rows = items as? [[String: Any]] else { return [] }
        var result: [GitCredential] = []
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { continue }
            let one: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var data: CFTypeRef?
            guard SecItemCopyMatching(one as CFDictionary, &data) == errSecSuccess,
                  let bytes = data as? Data,
                  let credential = try? JSONDecoder().decode(GitCredential.self, from: bytes) else { continue }
            result.append(credential)
        }
        return result.sorted { $0.host < $1.host }
    }

    static func save(_ credential: GitCredential) throws {
        remove(host: credential.host)
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.host,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        invalidate()
        guard status == errSecSuccess else {
            throw TramaError("não consegui guardar o token no Keychain (código \(status))")
        }
    }

    static func remove(host: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
        SecItemDelete(query as CFDictionary)
        invalidate()
    }

    private static func invalidate() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    private static func basic(_ credential: GitCredential) -> String {
        let user: String
        switch credential.kind {
        case .github: user = "x-access-token"
        case .gitlab: user = "oauth2"
        case .azure: user = ""
        default: user = credential.username ?? ""
        }
        return Data("\(user):\(credential.token)".utf8).base64EncodedString()
    }

    /// Variáveis que fazem o git usar o token de cada host guardado nos remotos HTTPS.
    static func gitEnvironment() -> [String: String] {
        let credentials = all()
        guard !credentials.isEmpty else { return [:] }
        var env = ["GIT_CONFIG_COUNT": String(credentials.count)]
        for (index, credential) in credentials.enumerated() {
            env["GIT_CONFIG_KEY_\(index)"] = "http.https://\(credential.host)/.extraheader"
            env["GIT_CONFIG_VALUE_\(index)"] = "AUTHORIZATION: basic \(basic(credential))"
        }
        return env
    }

    /// Variáveis que fazem a CLI do provedor (gh, glab, az) usar o token guardado.
    static func cliEnvironment(tool: String) -> [String: String] {
        let kind: ProviderKind
        let key: String
        switch tool {
        case "gh": (kind, key) = (.github, "GH_TOKEN")
        case "glab": (kind, key) = (.gitlab, "GITLAB_TOKEN")
        case "az": (kind, key) = (.azure, "AZURE_DEVOPS_EXT_PAT")
        default: return [:]
        }
        let matching = all().filter { $0.kind == kind }
        guard let credential = matching.first(where: { $0.host == kind.defaultHost }) ?? matching.first else { return [:] }
        return [key: credential.token]
    }

    /// Confere o token no provedor e devolve o nome da conta (ou nil quando não dá para conferir).
    static func validate(_ credential: GitCredential, organization: String = "") async throws -> String? {
        var request: URLRequest
        switch credential.kind {
        case .github:
            let base = credential.host == "github.com" ? "https://api.github.com" : "https://\(credential.host)/api/v3"
            request = URLRequest(url: URL(string: base + "/user")!)
            request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        case .gitlab:
            request = URLRequest(url: URL(string: "https://\(credential.host)/api/v4/user")!)
            request.setValue(credential.token, forHTTPHeaderField: "PRIVATE-TOKEN")
        case .azure:
            let org = organization.trimmingCharacters(in: .whitespaces)
            guard !org.isEmpty else { return nil }
            request = URLRequest(url: URL(string: "https://dev.azure.com/\(pathEncoded(org))/_apis/connectionData")!)
            request.setValue("Basic " + basic(credential), forHTTPHeaderField: "Authorization")
        case .bitbucket:
            request = URLRequest(url: URL(string: "https://api.bitbucket.org/2.0/user")!)
            request.setValue("Basic " + basic(credential), forHTTPHeaderField: "Authorization")
        case .manual:
            return nil
        }
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TramaError("resposta inválida de \(credential.host)") }
        // Azure responde 203 com a página de login quando o token não vale.
        let rejected = http.statusCode == 401 || (credential.kind == .azure && http.statusCode == 203)
        if rejected { throw TramaError("\(credential.kind.title) recusou o token") }
        // Tokens restritos (ex.: de repositório no Bitbucket) podem não ler o usuário: vale mesmo assim.
        guard http.statusCode == 200 else {
            if http.statusCode == 403 { return nil }
            throw TramaError("\(credential.host) respondeu \(http.statusCode)")
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch credential.kind {
        case .github: return json?["login"] as? String
        case .gitlab: return json?["username"] as? String
        case .bitbucket: return json?["username"] as? String ?? json?["display_name"] as? String
        case .azure: return (json?["authenticatedUser"] as? [String: Any])?["providerDisplayName"] as? String
        case .manual: return nil
        }
    }
}
