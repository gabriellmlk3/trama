import Foundation

struct InstallableTool: Identifiable, Sendable {
    let cli: CLITool
    let title: String
    let purpose: String
    let formula: String
    let afterInstall: String?

    var id: String { cli.name }
    var isInstalled: Bool { cli.executable != nil }

    var version: String? {
        guard isInstalled else { return nil }
        let r = cli.execute(NSHomeDirectory(), ["--version"], timeout: 15)
        guard r.code == 0 else { return nil }
        return r.output.split(separator: "\n").first.map(String.init)
    }

    var installCommand: String {
        var steps = [ToolInstaller.homebrewSetup, "brew install \(formula)"]
        if let afterInstall { steps.append(afterInstall) }
        return steps.joined(separator: " && ")
    }

    var ensureCommand: String {
        "(command -v \(cli.name) >/dev/null || (\(installCommand)))"
    }
}

enum ToolInstaller {
    private static let shellenv = "for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x \"$b\" ] && eval \"$($b shellenv)\" && break; done"

    static let homebrewSetup = "{ \(shellenv); command -v brew >/dev/null || { /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && \(shellenv); }; }"

    static let all: [InstallableTool] = [
        InstallableTool(
            cli: .gh,
            title: "GitHub CLI",
            purpose: "PRs e CI no GitHub",
            formula: "gh",
            afterInstall: nil
        ),
        InstallableTool(
            cli: .glab,
            title: "GitLab CLI",
            purpose: "MRs e pipelines no GitLab",
            formula: "glab",
            afterInstall: nil
        ),
        InstallableTool(
            cli: .az,
            title: "Azure CLI",
            purpose: "PRs e políticas no Azure DevOps",
            formula: "azure-cli",
            afterInstall: "az extension add --name azure-devops --yes"
        )
    ]

    static func named(_ text: String) -> InstallableTool? {
        let key = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let provider = ProviderKind.named(key), let cli = provider.cliName {
            return all.first { $0.id == cli }
        }
        return all.first { $0.id == key }
    }

    static func missing() -> [InstallableTool] {
        all.filter { !$0.isInstalled }
    }

    static func runInTerminal(_ command: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
