import Foundation

struct Arguments {
    var positionals: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    func value(_ name: String) -> String? {
        guard let v = values[name], !v.isEmpty else { return nil }
        return v
    }

    func has(_ name: String) -> Bool { flags.contains(name) }

    func positional(_ i: Int) -> String? {
        i < positionals.count ? positionals[i] : nil
    }

    func text(from i: Int) -> String {
        guard i < positionals.count else { return "" }
        return positionals[i...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ input: [String], valueFlags: [String]) throws -> Arguments {
        let acceptsValue = Set(valueFlags + ["raiz"])
        var a = Arguments()
        var i = 0
        while i < input.count {
            let s = input[i]
            if s == "--" {
                a.positionals += input[(i + 1)...]
                break
            }
            if s == "-h" {
                a.flags.insert("ajuda")
            } else if !s.hasPrefix("--") || s.count == 2 {
                a.positionals.append(s)
            } else {
                let name = String(s.dropFirst(2))
                if let equals = name.firstIndex(of: "=") {
                    a.values[String(name[..<equals])] = String(name[name.index(after: equals)...])
                } else if acceptsValue.contains(name) {
                    guard i + 1 < input.count else {
                        throw TramaError("--\(name) precisa de um valor")
                    }
                    a.values[name] = input[i + 1]
                    i += 1
                } else {
                    a.flags.insert(name == "help" ? "ajuda" : name)
                }
            }
            i += 1
        }
        return a
    }
}

func table(_ rows: [[String]], indent: String = "") -> String {
    var widths: [Int] = []
    for l in rows {
        for (i, c) in l.enumerated() where i < l.count - 1 {
            if i >= widths.count { widths.append(0) }
            widths[i] = max(widths[i], c.count)
        }
    }
    return rows.map { l in
        var s = indent
        for (i, c) in l.enumerated() {
            if i < l.count - 1 {
                s += c + String(repeating: " ", count: widths[i] - c.count + 2)
            } else {
                s += c
            }
        }
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
}

public struct CLI {
    public static let version = "0.2.0"

    var writeOutput: (String) -> Void
    var writeError: (String) -> Void
    var readInput: () -> Data
    var currentDirectory: () -> String
    var environment: [String: String]

    public init(
        output: @escaping (String) -> Void = { FileHandle.standardOutput.write(Data($0.utf8)) },
        error: @escaping (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        input: @escaping () -> Data = { FileHandle.standardInput.readDataToEndOfFile() },
        currentDirectory: @escaping () -> String = { FileManager.default.currentDirectoryPath },
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.writeOutput = output
        self.writeError = error
        self.readInput = input
        self.currentDirectory = currentDirectory
        self.environment = environment
    }

    public static func main() -> Int32 {
        CLI().run(Array(CommandLine.arguments.dropFirst()))
    }

    public static func shouldRunAsCLI(_ argv: [String]) -> Bool {
        if argv.count > 1 {
            let first = argv[1]
            if commands[first] != nil || commandAliases[first] != nil
                || ["ajuda", "help", "--help", "-h"].contains(first) {
                return true
            }
        }
        guard let invoked = argv.first else { return false }
        return !invoked.contains(".app/Contents/MacOS/")
    }

    struct Command {
        let summary: String
        let usage: String
        let valueFlags: [String]
        let run: (Context, Arguments) throws -> Void
    }

    final class Context {
        let cli: CLI
        let root: String?
        let json: Bool

        init(cli: CLI, root: String?, json: Bool) {
            self.cli = cli
            self.root = root
            self.json = json
        }

        func open() throws -> Workspace {
            try Workspace.open(root: root)
        }

        func line(_ s: String = "") { cli.writeOutput(s + "\n") }
        func text(_ s: String) { cli.writeOutput(s) }
        func ok(_ s: String) { line("✓ " + s) }
        func error(_ s: String) { cli.writeError(s + "\n") }

        func emitJSON<T: Encodable>(_ v: T) throws {
            let data = try JSON.encoder().encode(v)
            cli.writeOutput(String(decoding: data, as: UTF8.self) + "\n")
        }

        func warnings(_ list: [Warning]) {
            for a in list {
                if let r = a.repo {
                    error("  aviso · \(r): \(a.message)")
                } else {
                    error("  aviso: \(a.message)")
                }
            }
        }

        var isAgent: Bool {
            cli.environment["CLAUDECODE"] != nil || cli.environment["CLAUDE_CODE_ENTRYPOINT"] != nil
        }

        func author(_ r: RepoConfig?, _ explicit: String?) -> String {
            if let e = explicit { return e }
            if let v = cli.environment["TRAMA_AUTOR"], !v.isEmpty { return v }
            if isAgent {
                return r.map { "agente · \($0.alias)" } ?? "agente"
            }
            return "você"
        }

        func targetTrama(_ w: Workspace, _ explicit: String?) throws -> (trama: Trama, repo: RepoConfig?) {
            let here = try? w.locate(cli.currentDirectory())
            if let explicit {
                let t = try w.trama(explicit)
                if let here, here.trama.slug == t.slug { return (t, here.repo) }
                return (t, nil)
            }
            guard let here else {
                throw TramaError("não sei de qual trama você está falando · rode dentro de um worktree da trama ou passe o nome dela")
            }
            return here
        }
    }

    static let commandAliases: [String: String] = [
        "new": "nova", "list": "ls", "park": "estacionar", "resume": "retomar", "archive": "arquivar",
        "path": "caminho", "where": "onde", "capsule": "capsula", "cápsula": "capsula",
        "decision": "decisao", "decisão": "decisao", "pendência": "pendencia",
        "version": "versao", "--version": "versao", "-v": "versao", "fetch": "buscar",
    ]

    static let order = [
        "init", "repo", "nova", "ls", "status", "puxar", "soltar", "preparar", "subir", "descer", "pr", "merge", "estacionar", "retomar", "arquivar", "caminho", "onde",
        "capsula", "contexto", "objetivo", "decisao", "handoff", "recebido", "pendencia", "feito", "nota", "sincronizar",
        "achados", "adotar", "limpar", "buscar", "agentes", "hooks", "hook", "ferramentas", "estado", "versao",
    ]

    public func run(_ args: [String]) -> Int32 {
        guard let first = args.first, !["ajuda", "help", "--help", "-h"].contains(first) else {
            writeOutput(help())
            return 0
        }
        let name = CLI.commandAliases[first] ?? first
        guard let cmd = CLI.commands[name] else {
            writeError("comando desconhecido: \(first) (veja `trama ajuda`)\n")
            return 2
        }
        let a: Arguments
        do {
            a = try Arguments.parse(Array(args.dropFirst()), valueFlags: cmd.valueFlags)
        } catch {
            writeError("erro: \(errorMessage(error))\n")
            return 2
        }
        if a.has("ajuda") {
            writeOutput("\(cmd.summary)\n\n  \(cmd.usage)\n")
            return 0
        }
        let c = Context(cli: self, root: a.value("raiz"), json: a.has("json"))
        do {
            try cmd.run(c, a)
            return 0
        } catch {
            if c.json, let data = try? JSON.encoder(pretty: false).encode(["erro": errorMessage(error)]) {
                writeError(String(decoding: data, as: UTF8.self) + "\n")
            } else {
                writeError("erro: \(errorMessage(error))\n")
            }
            return 1
        }
    }

    func help() -> String {
        var s = "trama \(CLI.version): pare de trocar de branch, entre numa trama.\n\nUso: trama <comando> [argumentos]\n\n"
        s += table(CLI.order.compactMap { n in CLI.commands[n].map { [n, $0.summary] } }, indent: "  ")
        s += "\nDetalhes de um comando: trama <comando> --ajuda\n"
        s += "Pasta das tramas: $TRAMA_HOME ou ~/Tramas (ou --raiz em qualquer comando).\n"
        return s
    }
}
