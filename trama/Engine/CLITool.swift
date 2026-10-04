import Foundation

struct CLITool: Sendable {
    let name: String
    let environmentKey: String
    let candidates: [String]
    let installHint: String
    let environment: [String: String]
    var commandWords = 2

    var executable: String? {
        if let v = ProcessInfo.processInfo.environment[environmentKey], !v.isEmpty {
            return FileManager.default.isExecutableFile(atPath: v) ? v : nil
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var missingMessage: String { "não encontrei o `\(name)` · \(installHint)" }

    func execute(_ dir: String, _ args: [String], timeout: TimeInterval = 60) -> GitResult {
        guard let exe = executable else {
            return GitResult(output: "", error: missingMessage, code: -1)
        }
        var env = ProcessInfo.processInfo.environment
        for (key, value) in GitCredentials.cliEnvironment(tool: name) where env[key] == nil { env[key] = value }
        for (key, value) in environment { env[key] = value }
        var result = ProcessRunner.run(exe, args, directory: dir, environment: env, timeout: timeout)
        if result.code == ProcessRunner.launchFailureCode && result.output.isEmpty {
            result.error = "não consegui executar o \(name): \(result.error)"
        }
        return result
    }

    @discardableResult
    func run(_ dir: String, _ args: [String]) throws -> String {
        let r = execute(dir, args)
        guard r.code == 0 else {
            let message = r.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TramaError("\(name) \(args.prefix(commandWords).joined(separator: " ")): \(message.isEmpty ? "código \(r.code)" : message)")
        }
        return r.output
    }

    func json(_ dir: String, _ args: [String], timeout: TimeInterval = 30) -> Any? {
        let r = execute(dir, args, timeout: timeout)
        guard r.code == 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(r.output.utf8))
    }
}

extension CLITool {
    private static func candidates(_ name: String) -> [String] {
        ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", NSHomeDirectory() + "/.local/bin/\(name)"]
    }

    static let gh = CLITool(
        name: "gh",
        environmentKey: "TRAMA_GH",
        candidates: candidates("gh"),
        installHint: "instale com `brew install gh` e rode `gh auth login`",
        environment: ["GH_PROMPT_DISABLED": "1", "NO_COLOR": "1", "GH_NO_UPDATE_NOTIFIER": "1"]
    )

    static let az = CLITool(
        name: "az",
        environmentKey: "TRAMA_AZ",
        candidates: candidates("az"),
        installHint: "instale com `brew install azure-cli`, depois `az extension add --name azure-devops` e `az login`",
        environment: [
            "AZURE_EXTENSION_USE_DYNAMIC_INSTALL": "yes_without_prompt",
            "AZURE_CORE_ONLY_SHOW_ERRORS": "true",
            "AZURE_CORE_NO_COLOR": "true",
            "AZURE_CORE_COLLECT_TELEMETRY": "false",
            "NO_COLOR": "1"
        ],
        commandWords: 3
    )

    static let glab = CLITool(
        name: "glab",
        environmentKey: "TRAMA_GLAB",
        candidates: candidates("glab"),
        installHint: "instale com `brew install glab` e rode `glab auth login`",
        environment: ["NO_PROMPT": "1", "NO_COLOR": "1", "GLAB_CHECK_UPDATE": "false", "GLAB_SEND_TELEMETRY": "false"]
    )
}
