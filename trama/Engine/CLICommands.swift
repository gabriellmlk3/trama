import Foundation

extension CLI {
    static let commands: [String: Command] = [
        "init": Command(summary: "configura a pasta das tramas e o repositório de contexto",
                        usage: "trama init [--raiz ~/Tramas] [--contexto <pasta do repo de contexto>]",
                        valueFlags: ["contexto"], run: cmdInit),
        "repo": Command(summary: "cadastra repositórios (add, ls, rm, preparo, servico, ordem, provedor)",
                        usage: "trama repo add <pasta>... [--apelido api] [--rotulo backend] [--base main]\n  trama repo ls\n  trama repo rm <nome>\n  trama repo preparo <nome> [--copiar \".env*,local.properties\"] [--rodar \"npm ci\"] [--limpar]\n  trama repo servico <nome> [--nome api --comando \"npm run dev\" --porta 3000] [--remover api]\n  trama repo ordem <nome> <n>   (ordem de merge dos PRs: menor primeiro)\n  trama repo provedor <nome> [github|azure|gitlab|bitbucket|manual|auto]   (onde os PRs são abertos; auto = detecta pelo remoto)\n  trama repo descobrir [--json]   (repositórios git ao lado dos cadastrados, ainda fora do cadastro)\n  trama repo puxada [livre|aprovacao]   (agentes puxam repositórios sozinhos ou só sugerem e esperam o seu aceite)",
                        valueFlags: ["apelido", "rotulo", "base", "copiar", "rodar", "nome", "comando", "porta", "remover"], run: cmdRepo),
        "nova": Command(summary: "cria uma trama: branch + worktree em cada repositório + cápsula",
                        usage: "trama nova \"Título\" --repos api,admin [--base main] [--tarefa CU-482] [--objetivo \"...\"] [--contexto <pasta>] [--slug x] [--sem-fetch]",
                        valueFlags: ["repos", "base", "tarefa", "objetivo", "contexto", "slug"], run: cmdNew),
        "ls": Command(summary: "lista as tramas", usage: "trama ls [--todas]", valueFlags: [], run: cmdList),
        "status": Command(summary: "situação dos repositórios de uma trama (ou de todas)", usage: "trama status [trama]", valueFlags: [], run: cmdStatus),
        "estado": Command(summary: "tudo em JSON", usage: "trama estado [--todas]", valueFlags: [], run: cmdState),
        "puxar": Command(summary: "inclui repositórios numa trama (agentes viram sugestão quando a puxada exige aprovação)", usage: "trama puxar <trama> <repo>... [--motivo \"por que\"] [--sem-fetch]", valueFlags: ["motivo"], run: cmdPull),
        "sugerir": Command(summary: "sugere incluir outro repositório (cadastrado ou uma pasta) na trama, com o motivo",
                           usage: "trama sugerir <repo|pasta> \"motivo\" [--trama x] [--autor nome]", valueFlags: ["trama", "autor"], run: cmdSuggest),
        "sugestao": Command(summary: "lista, aceita ou dispensa as sugestões de repositório da trama",
                            usage: "trama sugestao [ls] [--trama x] [--json]\n  trama sugestao aceitar <n> [--trama x] [--sem-fetch]\n  trama sugestao dispensar <n> [--trama x]",
                            valueFlags: ["trama"], run: cmdSuggestion),
        "soltar": Command(summary: "tira um repositório da trama (a branch continua)", usage: "trama soltar <trama> <repo> [--forcar]", valueFlags: [], run: cmdDrop),
        "estacionar": Command(summary: "pausa uma trama (os worktrees ficam intactos)", usage: "trama estacionar [trama]", valueFlags: [], run: cmdPark),
        "retomar": Command(summary: "reativa uma trama, com rebase opcional na base", usage: "trama retomar <trama> [--rebase] [--sem-fetch]", valueFlags: [], run: cmdResume),
        "arquivar": Command(summary: "remove os worktrees e arquiva a trama (branches ficam)", usage: "trama arquivar <trama> [--forcar]", valueFlags: [], run: cmdArchive),
        "remover": Command(summary: "remove a trama de vez: worktrees e registro (a cápsula e, por padrão, as branches ficam)", usage: "trama remover <trama> [--forcar] [--branches]", valueFlags: [], run: cmdRemove),
        "subir": Command(summary: "sobe os serviços de desenvolvimento da trama, cada um na sua porta",
                         usage: "trama subir [--trama x] [--repo nome] [--servico nome]", valueFlags: ["trama", "repo", "servico"], run: cmdUp),
        "descer": Command(summary: "derruba os serviços da trama", usage: "trama descer [--trama x] [--repo nome] [--servico nome]", valueFlags: ["trama", "repo", "servico"], run: cmdDown),
        "pr": Command(summary: "abre os PRs de todos os repositórios da trama, ligados entre si (GitHub com gh, Azure DevOps com az, GitLab com glab; outros pelo link)",
                      usage: "trama pr [--rascunho] [--base develop | --base api=staging,admin=develop] [--repo a,b] [--simular] [--trama x]\n  trama pr ls [--trama x]", valueFlags: ["trama", "base", "repo"], run: cmdPullRequests),
        "mesclar": Command(summary: "mescla a branch da trama direto em branches do remoto (sem PR), na ordem de merge",
                          usage: "trama mesclar --base develop | --base api=staging,admin=develop [--repo a,b] [--simular] [--trama x]", valueFlags: ["trama", "base", "repo"], run: cmdMergeIntoBranches),
        "merge": Command(summary: "traz os commits de uma trama para outra, nos repositórios que as duas têm",
                         usage: "trama merge <origem> [--para destino] [--repo a,b] [--permitir-conflito]", valueFlags: ["para", "repo"], run: cmdMerge),
        "preparar": Command(summary: "refaz o preparo dos worktrees (copia arquivos e roda a receita do repositório)", usage: "trama preparar <trama> [repo]", valueFlags: [], run: cmdPrepare),
        "caminho": Command(summary: "imprime a pasta da trama ou de um repositório nela", usage: "trama caminho <trama> [repo]", valueFlags: [], run: cmdPath),
        "onde": Command(summary: "diz em qual trama e repositório você está", usage: "trama onde", valueFlags: [], run: cmdWhere),
        "vscode": Command(summary: "gera o .code-workspace da trama (todos os repositórios numa janela do VS Code)", usage: "trama vscode [trama] [--abrir]", valueFlags: [], run: cmdCode),
        "capsula": Command(summary: "mostra a cápsula da trama", usage: "trama capsula [trama] [--json]", valueFlags: [], run: cmdCapsule),
        "contexto": Command(summary: "define o repositório de contexto de uma trama", usage: "trama contexto <pasta|global> [--trama x]", valueFlags: ["trama"], run: cmdContext),
        "objetivo": Command(summary: "define o objetivo da trama", usage: "trama objetivo \"texto\" [--trama x]", valueFlags: ["trama"], run: cmdGoal),
        "decisao": Command(summary: "registra uma decisão na cápsula", usage: "trama decisao \"texto\" [--trama x] [--autor nome]", valueFlags: ["trama", "autor"], run: cmdDecision),
        "handoff": Command(summary: "passa trabalho para o agente de outro repositório",
                           usage: "trama handoff <repo destino> \"texto\" [--trama x] [--de repo] [--autor nome]",
                           valueFlags: ["trama", "de", "autor"], run: cmdHandoff),
        "recebido": Command(summary: "marca como lidos os handoffs para o seu repositório", usage: "trama recebido [n] [--trama x] [--repo nome]", valueFlags: ["trama", "repo"], run: cmdReceived),
        "pendencia": Command(summary: "acrescenta uma pendência", usage: "trama pendencia \"texto\" [--trama x]", valueFlags: ["trama"], run: cmdPending),
        "feito": Command(summary: "marca uma pendência como feita", usage: "trama feito <n> [--trama x]", valueFlags: ["trama"], run: cmdDone),
        "nota": Command(summary: "escreve no diário da trama", usage: "trama nota \"texto\" [--trama x]", valueFlags: ["trama"], run: cmdNote),
        "sincronizar": Command(summary: "faz commit das cápsulas no repositório de contexto", usage: "trama sincronizar [trama]", valueFlags: [], run: cmdSync),
        "achados": Command(summary: "procura trabalho esquecido em todos os repositórios", usage: "trama achados [--json]", valueFlags: [], run: cmdFindings),
        "adotar": Command(summary: "leva mudanças esquecidas da cópia principal para uma trama", usage: "trama adotar <repo> --para <trama>", valueFlags: ["para"], run: cmdAdopt),
        "limpar": Command(summary: "apaga branches locais que já estão na base", usage: "trama limpar <repo>", valueFlags: [], run: cmdClean),
        "buscar": Command(summary: "atualiza a base (git fetch) de todos os repositórios", usage: "trama buscar", valueFlags: [], run: cmdFetch),
        "agentes": Command(summary: "lista as sessões do Claude Code nas tramas", usage: "trama agentes [--json]", valueFlags: [], run: cmdAgents),
        "hook": Command(summary: "recebe eventos do Claude Code (uso interno)", usage: "trama hook < evento.json", valueFlags: [], run: cmdHook),
        "hooks": Command(summary: "instala ou remove os hooks no Claude Code", usage: "trama hooks instalar|remover|status [--settings caminho]", valueFlags: ["settings"], run: cmdHooks),
        "ferramentas": Command(summary: "mostra ou instala as CLIs dos provedores (gh, glab, az)", usage: "trama ferramentas [instalar [gh|glab|az|todas]] [--json]", valueFlags: [], run: cmdTools),
        "skill": Command(summary: "instala ou remove a skill que ensina agentes do Claude Code a usar o Trama", usage: "trama skill instalar|remover|status", valueFlags: [], run: cmdSkill),
        "versao": Command(summary: "mostra a versão", usage: "trama versao", valueFlags: [], run: { c, _ in c.line("trama \(CLI.version)") }),
    ]


    static func cmdInit(_ c: Context, _ a: Arguments) throws {
        let w = try Workspace.configure(root: c.root, context: a.value("contexto"))
        if c.json { return try c.emitJSON(w.config) }
        c.ok("Trama configurado em \(Paths.abbreviate(w.root))")
        if let context = w.config.context {
            c.line("  cápsulas em \(Paths.abbreviate(context))/\(w.config.capsuleFolder)/")
        } else {
            c.line("  sem repositório de contexto: cada cápsula fica na pasta da própria trama")
            c.line("  (para usar um: trama init --contexto ~/caminho/do/repo-de-contexto)")
        }
        c.line("\nPróximos passos:")
        c.line("  trama repo add ~/caminho/repo-a ~/caminho/repo-b")
        c.line("  trama hooks instalar")
        c.line("  trama nova \"Minha primeira trama\" --repos a,b")
    }

    static func cmdRepo(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        switch a.positional(0) ?? "ls" {
        case "add", "adicionar":
            if c.isAgent && w.config.agentPullPolicy == .approval {
                throw TramaError("cadastrar repositórios exige aprovação · use `trama sugerir <pasta> \"motivo\"` e o usuário aceita no app")
            }
            let paths = Array(a.positionals.dropFirst())
            guard !paths.isEmpty else { throw TramaError("informe a pasta de pelo menos um repositório") }
            if paths.count > 1 && (a.value("apelido") != nil || a.value("rotulo") != nil) {
                throw TramaError("--apelido e --rotulo só valem com um repositório por vez")
            }
            var failures = 0
            for p in paths {
                do {
                    let r = try w.addRepo(p, alias: a.value("apelido"), label: a.value("rotulo"), base: a.value("base"))
                    c.ok("\(r.name) (apelido \(r.alias) · base \(r.base ?? "main")) · \(Paths.abbreviate(r.path))")
                } catch {
                    c.error("✗ \(p): \(errorMessage(error))")
                    failures += 1
                }
            }
            if failures == paths.count { throw TramaError("nenhum repositório foi cadastrado") }
        case "rm", "remover":
            guard let key = a.positional(1) else { throw TramaError("uso: trama repo rm <nome>") }
            let r = try w.removeRepo(key)
            c.ok("\(r.name) saiu do cadastro (nada foi apagado do disco)")
        case "preparo":
            guard let key = a.positional(1) else { throw TramaError("uso: trama repo preparo <nome> [--copiar padrões] [--rodar comando] [--limpar]") }
            var r = try w.repo(key)
            if a.has("limpar") || a.value("copiar") != nil || a.value("rodar") != nil {
                let copy = a.has("limpar") ? [] : a.value("copiar").map { $0.split(separator: ",").map(String.init) } ?? r.copy
                let run = a.has("limpar") ? [] : a.value("rodar").map { [$0] } ?? r.run
                r = try w.setRecipe(r.name, copy: copy, run: run)
            }
            if c.json { return try c.emitJSON(r) }
            c.line("\(r.name)")
            c.line("  copiar: \(r.copy.isEmpty ? "—" : r.copy.joined(separator: ", "))")
            c.line("  rodar:  \(r.run.isEmpty ? "—" : r.run.joined(separator: " && "))")
        case "ordem":
            guard let key = a.positional(1), let n = a.positional(2).flatMap({ Int($0) }) else { throw TramaError("uso: trama repo ordem <nome> <n>") }
            let r = try w.setMergeRank(key, n)
            c.ok("\(r.name): ordem de merge \(r.mergeRank)")
        case "provedor":
            guard let key = a.positional(1) else {
                throw TramaError("uso: trama repo provedor <nome> [github|azure|gitlab|bitbucket|manual|auto]")
            }
            var r = try w.repo(key)
            if let value = a.positional(2) {
                let automatic = value.lowercased() == "auto" || value.lowercased() == "automatico"
                let kind = automatic ? nil : ProviderKind.named(value)
                guard automatic || kind != nil else {
                    throw TramaError("provedor desconhecido: \(value) (use github, azure, gitlab, bitbucket, manual ou auto)")
                }
                r = try w.setProvider(r.name, kind)
            }
            let kind = w.providerKind(for: r)
            if c.json { return try c.emitJSON(["repo": r.name, "provedor": kind.rawValue, "definido": r.provider == nil ? "nao" : "sim"]) }
            c.line("\(r.name): \(kind.title)" + (r.provider == nil ? " (detectado pelo remoto)" : " (definido por você)"))
        case "servico":
            guard let key = a.positional(1) else { throw TramaError("uso: trama repo servico <nome> [--nome x --comando \"...\" --porta 3000] [--remover x]") }
            var r = try w.repo(key)
            if let remove = a.value("remover") {
                guard r.services.contains(where: { $0.name == remove }) else { throw TramaError("\(r.name) não tem o serviço “\(remove)”") }
                r = try w.setServices(r.name, r.services.filter { $0.name != remove })
            } else if let name = a.value("nome") {
                guard let command = a.value("comando"), let port = a.value("porta").flatMap({ Int($0) }) else {
                    throw TramaError("informe --comando e --porta")
                }
                var list = r.services.filter { $0.name != name }
                list.append(ServiceConfig(name: name, command: command, port: port))
                r = try w.setServices(r.name, list)
            }
            if c.json { return try c.emitJSON(r.services) }
            if r.services.isEmpty { return c.line("\(r.name) não tem serviços") }
            for s in r.services {
                c.line("  \(s.name) · porta \(s.port) (+10 por trama) · \(s.command)")
            }
        case "descobrir":
            let found = w.discoverRepos()
            if c.json { return try c.emitJSON(found) }
            guard !found.isEmpty else {
                return c.line("Nenhum repositório novo ao lado dos cadastrados.")
            }
            c.text(table([["NOME", "PASTA"]] + found.map { [$0.name, $0.path] }))
            c.line("\nPara usar um deles numa trama: trama sugerir <pasta> \"motivo\"")
        case "puxada":
            guard let v = a.positional(1) else {
                let current = w.config.agentPullPolicy
                if c.json { return try c.emitJSON(["politica": current.rawValue]) }
                return c.line(current == .free ? "livre · agentes puxam repositórios sozinhos" : "aprovacao · agentes só sugerem; você aceita no app ou com `trama sugestao aceitar`")
            }
            guard let policy = AgentPullPolicy(rawValue: v.lowercased().replacingOccurrences(of: "ç", with: "c").replacingOccurrences(of: "ã", with: "a")) else {
                throw TramaError("use livre ou aprovacao")
            }
            try w.setAgentPullPolicy(policy)
            c.ok(policy == .free ? "agentes puxam repositórios sozinhos" : "agentes só sugerem repositórios; a puxada espera o seu aceite")
        case "ls", "lista":
            if c.json { return try c.emitJSON(w.config.repos) }
            guard !w.config.repos.isEmpty else {
                return c.line("Nenhum repositório cadastrado. Use: trama repo add <pasta>...")
            }
            var rows = [["NOME", "APELIDO", "BASE", "PROVEDOR", "RÓTULO", "PASTA"]]
            for r in w.config.repos {
                rows.append([r.name, r.alias, r.base ?? "", w.providerKind(for: r).title, r.label ?? "", Paths.abbreviate(r.path)])
            }
            c.text(table(rows))
        default:
            throw TramaError("subcomando desconhecido: \(a.positional(0) ?? "") (use add, ls, rm, preparo, servico, ordem, provedor, descobrir ou puxada)")
        }
    }


    static func cmdNew(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let o = NewTramaOptions(
            title: a.text(from: 0),
            repos: a.value("repos").map { [$0] } ?? [],
            slug: a.value("slug"),
            base: a.value("base"),
            task: a.value("tarefa"),
            goal: a.value("objetivo"),
            context: a.value("contexto"),
            noFetch: a.has("sem-fetch")
        )
        let (t, warnings) = try w.newTrama(o)
        if c.json { return try c.emitJSON(w.liveTrama(t, agents: [], predictConflict: false)) }
        c.ok("Trama “\(t.title)” tecida em \(Paths.abbreviate(w.tramaPath(t.slug)))")
        c.line("  branch \(t.branch)")
        for name in t.repos {
            c.line("  • \(name.padding(toLength: max(name.count, 18), withPad: " ", startingAt: 0)) → \(Paths.abbreviate(w.worktreePath(t.slug, name)))")
        }
        c.line("  cápsula: \(Paths.abbreviate(w.capsulePath(t.slug)))")
        c.warnings(warnings)
        if let first = t.repos.first {
            c.line("\nPara abrir um agente:  cd \(Paths.abbreviate(w.worktreePath(t.slug, first))) && claude")
        }
    }

    static func cmdList(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let list = try w.tramas().filter { !$0.isArchived || a.has("todas") }
        if c.json { return try c.emitJSON(list) }
        guard !list.isEmpty else {
            return c.line("Nenhuma trama ainda. Crie uma: trama nova \"Título\" --repos a,b")
        }
        let ags = (try? w.agents()) ?? []
        var rows: [[String]] = []
        for t in list {
            var mark = "●"
            var extra = ""
            if t.isParked {
                mark = "◌"
                extra = "estacionada " + relativeTime(t.parkedAt)
            } else if t.isArchived {
                mark = "·"
                extra = "arquivada"
            } else {
                let n = ags.filter { $0.trama == t.slug }.count
                if n > 0 { extra = "\(n) \(plural(n, "agente", "agentes"))" }
            }
            rows.append(["\(mark) \(t.title)", t.slug, aliases(w, t.repos).joined(separator: " · "), extra])
        }
        c.text(table(rows))
    }

    static func aliases(_ w: Workspace, _ names: [String]) -> [String] {
        names.map { (try? w.repo($0))?.alias ?? $0 }
    }

    static func symbol(_ state: String) -> String {
        switch state {
        case AgentState.working: return "●"
        case AgentState.waiting: return "◐"
        case AgentState.done: return "✓"
        default: return "○"
        }
    }

    static func describe(_ a: Agent) -> String {
        symbol(a.state) + " " + a.state + (a.message.map { $0.isEmpty ? "" : ": " + $0 } ?? "")
    }

    static func printStatus(_ c: Context, _ v: LiveTrama) {
        c.line("\(v.title)  (\(v.branch) · \(v.state))")
        var rows: [[String]] = []
        for s in v.status {
            guard s.exists else {
                rows.append([s.repo, s.error ?? "worktree não encontrado"])
                continue
            }
            let changed = s.changed == 0 ? "limpo" : "\(s.changed) \(plural(s.changed, "alterado", "alterados"))"
            let commit = s.lastCommit.map { "\($0.subject) · \(relativeTime($0.timestamp))" } ?? ""
            var extras: [String] = []
            if s.conflict == "conflito" { extras.append("⚠ conflito previsto com \(s.base)") }
            extras += s.agents.map(describe)
            rows.append([s.repo, "↑\(s.ahead) ↓\(s.behind)", changed, commit, extras.joined(separator: "  ")])
        }
        c.text(table(rows, indent: "  "))
    }

    static func cmdStatus(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        var target: [Trama] = []
        if let s = a.positional(0) {
            target = [try w.trama(s)]
        } else if let here = try? c.targetTrama(w, nil) {
            target = [here.trama]
        } else {
            target = try w.tramas().filter(\.isActive)
        }
        let ags = (try? w.agents()) ?? []
        let live = target.map { w.liveTrama($0, agents: ags) }
        if c.json { return try c.emitJSON(live) }
        guard !live.isEmpty else { return c.line("Nenhuma trama ativa.") }
        for (i, v) in live.enumerated() {
            if i > 0 { c.line() }
            printStatus(c, v)
        }
    }

    static func cmdState(_ c: Context, _ a: Arguments) throws {
        try c.emitJSON(try c.open().fullState(includeArchived: a.has("todas")))
    }

    static func cmdPull(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard a.positionals.count >= 2 else { throw TramaError("uso: trama puxar <trama> <repo>...") }
        if c.isAgent && w.config.agentPullPolicy == .approval {
            let slug = try w.trama(a.positionals[0]).slug
            let reason = a.value("motivo") ?? "o agente pediu para incluir"
            for key in a.positionals.dropFirst().flatMap({ $0.split(separator: ",").map(String.init) }) {
                let item = try w.suggestRepo(slug, target: key, author: c.author(nil, nil), reason: reason)
                c.ok("sugestão \(item.index) registrada: \(item.to ?? key) · espera o aceite do usuário (a puxada de agentes exige aprovação)")
            }
            return
        }
        let (t, warnings) = try w.pullRepos(a.positionals[0], Array(a.positionals.dropFirst()), noFetch: a.has("sem-fetch"))
        c.ok("\(t.title) agora tem \(t.repos.joined(separator: ", "))")
        c.warnings(warnings)
    }

    static func cmdSuggest(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard a.positionals.count >= 2 else { throw TramaError("uso: trama sugerir <repo|pasta> \"motivo\"") }
        let (t, r) = try c.targetTrama(w, a.value("trama"))
        let item = try w.suggestRepo(t.slug, target: a.positionals[0], author: c.author(r, a.value("autor")), reason: a.text(from: 1))
        if c.json { return try c.emitJSON(item) }
        c.ok("sugestão \(item.index) registrada em \(t.title): incluir \(item.to ?? a.positionals[0])")
        c.line("  o usuário aceita no app ou com: trama sugestao aceitar \(item.index) --trama \(t.slug)")
    }

    static func cmdSuggestion(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let action = a.positional(0) ?? "ls"
        let (t, _) = try c.targetTrama(w, a.value("trama"))
        switch action {
        case "ls", "lista":
            let list = try w.readCapsule(t.slug).suggestions
            if c.json { return try c.emitJSON(list) }
            guard !list.isEmpty else { return c.line("Nenhuma sugestão de repositório.") }
            var rows = [["Nº", "REPOSITÓRIO", "SITUAÇÃO", "AUTOR", "MOTIVO"]]
            for s in list {
                rows.append(["\(s.index)", s.to ?? "", s.dismissed ? "dispensada" : (s.done ? "aceita" : "aberta"), s.author ?? "", s.text])
            }
            c.text(table(rows))
        case "aceitar", "dispensar":
            guard let s = a.positional(1), let n = Int(s) else { throw TramaError("uso: trama sugestao \(action) <n>") }
            if action == "aceitar" {
                let (updated, warnings) = try w.acceptSuggestion(t.slug, number: n, noFetch: a.has("sem-fetch"))
                c.ok("\(updated.title) agora tem \(updated.repos.joined(separator: ", "))")
                c.warnings(warnings)
            } else {
                try w.dismissSuggestion(t.slug, number: n)
                c.ok("sugestão \(n) dispensada")
            }
        default:
            throw TramaError("subcomando desconhecido: \(action) (use ls, aceitar ou dispensar)")
        }
    }

    static func cmdDrop(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard a.positionals.count >= 2 else { throw TramaError("uso: trama soltar <trama> <repo>") }
        let t = try w.dropRepo(a.positionals[0], a.positionals[1], force: a.has("forcar"))
        c.ok("\(t.title) agora tem \(t.repos.joined(separator: ", "))")
    }

    static func cmdPark(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let target = try c.targetTrama(w, a.positional(0))
        let (t, status) = try w.park(target.trama.slug)
        if c.json { return try c.emitJSON(t) }
        c.ok("\(t.title) estacionada · os worktrees continuam em \(Paths.abbreviate(w.tramaPath(t.slug))), do jeito que estão")
        for s in status where s.changed > 0 {
            c.line("  \(s.repo) tem \(s.changed) \(plural(s.changed, "arquivo", "arquivos")) não commitado(s) (seguros no worktree)")
        }
    }

    private struct ResumeResponse: Encodable {
        var trama: Trama
        var results: [ResumeResult]
    }

    static func cmdResume(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let target = try c.targetTrama(w, a.positional(0))
        let (t, results) = try w.resume(target.trama.slug, rebase: a.has("rebase"), noFetch: a.has("sem-fetch"))
        if c.json { return try c.emitJSON(ResumeResponse(trama: t, results: results)) }
        c.ok("\(t.title) retomada")
        for r in results {
            c.line("  \(r.repo): \(r.situation)" + (r.detail.map { " · " + $0 } ?? ""))
        }
    }

    static func cmdArchive(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard let slug = a.positional(0) else { throw TramaError("uso: trama arquivar <trama> [--forcar]") }
        let t = try w.archive(slug, force: a.has("forcar"))
        c.ok("\(t.title) arquivada · worktrees removidos, branch \(t.branch) mantida em cada repositório")
    }

    static func cmdRemove(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard let slug = a.positional(0) else { throw TramaError("uso: trama remover <trama> [--forcar] [--branches]") }
        let branches = a.has("branches")
        let t = try w.remove(slug, force: a.has("forcar"), deleteBranches: branches)
        c.ok("\(t.title) removida · " + (branches ? "branches \(t.branch) apagadas" : "branch \(t.branch) mantida em cada repositório"))
    }

    private static func serviceScope(_ c: Context, _ w: Workspace, _ a: Arguments) throws -> (slug: String, repo: String?) {
        let target = try c.targetTrama(w, a.value("trama"))
        return (target.trama.slug, try a.value("repo").map { try w.repo($0).name } ?? target.repo?.name)
    }

    static func cmdUp(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let scope = try serviceScope(c, w, a)
        let started = try w.startServices(scope.slug, repo: scope.repo, service: a.value("servico"))
        if c.json { return try c.emitJSON(started) }
        if started.isEmpty { return c.line("Os serviços já estavam no ar.") }
        for s in started {
            c.ok("\(s.name) → \(s.url) · log em \(Paths.abbreviate(s.log))")
        }
    }

    static func cmdDown(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let scope = try serviceScope(c, w, a)
        let n = w.stopServices(scope.slug, repo: scope.repo, service: a.value("servico"))
        c.ok(n == 0 ? "Nenhum serviço no ar." : "\(n) \(plural(n, "serviço derrubado", "serviços derrubados"))")
    }

    static func cmdPullRequests(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let target = try c.targetTrama(w, a.value("trama"))
        if a.positional(0) == "ls" {
            let infos = w.pullRequestInfos(target.trama)
            if c.json { return try c.emitJSON(infos) }
            guard !infos.isEmpty else { return c.line("Esta trama ainda não tem PRs · rode `trama pr`") }
            var rows = [["REPO", "PR", "ESTADO", "CI", "ENDEREÇO"]]
            for i in infos { rows.append([i.repo, "#\(i.number)", i.draft ? "rascunho" : i.state, i.ci, i.url]) }
            return c.text(table(rows))
        }
        let trama = target.trama
        var targets: [String: String] = [:]
        if let spec = a.value("base") {
            targets = try w.parsePullRequestTargets(spec, for: trama)
        }
        var only: Set<String>?
        if let list = a.value("repo") {
            let names = try list.split(separator: ",").map { try w.repo(String($0)).name }
            only = Set(names)
        }
        if a.has("simular") || a.has("dry-run") {
            _ = try w.remoteBranchCatalog(trama.slug, fetch: true)
            let plan = try w.pullRequestPlan(trama.slug, targets: targets, existing: try w.existingPullRequests(trama.slug))
                .filter { only?.contains($0.repo) ?? true }
            if c.json { return try c.emitJSON(plan) }
            var rows = [["ORDEM", "REPO", "PROVEDOR", "DESTINO", "COMMITS", "CONFLITO", "SITUAÇÃO"]]
            for p in plan {
                let conflict = p.conflictFiles.map { $0.isEmpty ? "nenhum" : "\($0.count) \(plural($0.count, "arquivo", "arquivos"))" } ?? "—"
                rows.append(["\(p.order)", p.repo, p.provider.title, p.target, "↑\(p.ahead)", conflict, p.summary])
            }
            return c.text(table(rows))
        }
        let result = try w.openPullRequests(trama.slug, draft: a.has("rascunho"), targets: targets, only: only)
        if c.json {
            let links = result.manual.map { PullRequestInfo(repo: $0.repo, url: $0.url ?? "", number: 0, state: "manual", draft: false, ci: CIState.none) }
            return try c.emitJSON(result.prs + links)
        }
        for p in result.prs { c.ok("\(p.repo): \(p.url)") }
        for m in result.manual {
            c.line("  \(m.repo): branch enviada · abra o PR em \(m.target) pelo link (\(m.provider.title)): \(m.url ?? "sem endereço para este remoto")")
        }
        c.warnings(result.warnings)
    }

    static func cmdMergeIntoBranches(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let trama = try c.targetTrama(w, a.value("trama")).trama
        var targets: [String: String] = [:]
        if let spec = a.value("base") {
            targets = try w.parsePullRequestTargets(spec, for: trama)
        }
        var only: Set<String>?
        if let list = a.value("repo") {
            only = Set(try list.split(separator: ",").map { try w.repo(String($0)).name })
        }
        if a.has("simular") || a.has("dry-run") {
            _ = try w.remoteBranchCatalog(trama.slug, fetch: true)
            let plan = try w.pullRequestPlan(trama.slug, targets: targets)
                .filter { only?.contains($0.repo) ?? true }
            if c.json { return try c.emitJSON(plan) }
            var rows = [["ORDEM", "REPO", "DESTINO", "COMMITS", "CONFLITO"]]
            for p in plan {
                let conflict = p.conflictFiles.map { $0.isEmpty ? "nenhum" : "\($0.count) \(plural($0.count, "arquivo", "arquivos"))" } ?? "—"
                rows.append(["\(p.order)", p.repo, p.target, "↑\(p.ahead)", conflict])
            }
            return c.text(table(rows))
        }
        let result = try w.mergeIntoBranches(trama.slug, targets: targets, only: only)
        if c.json { return try c.emitJSON(result.results) }
        for r in result.results {
            c.line("  \(r.repo): \(r.situation)" + (r.detail.map { " · " + $0 } ?? ""))
        }
        c.warnings(result.warnings)
    }

    static func cmdMerge(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard let source = a.positional(0) else { throw TramaError("uso: trama merge <origem> [--para destino] [--repo a,b] [--permitir-conflito]") }
        let target = try c.targetTrama(w, a.value("para"))
        let results = try w.mergeTrama(from: source, into: target.trama.slug, repos: a.value("repo").map { [$0] } ?? [], allowConflicts: a.has("permitir-conflito"))
        if c.json { return try c.emitJSON(results) }
        for r in results {
            c.line("  \(r.repo): \(r.situation)" + (r.detail.map { " · " + $0 } ?? ""))
        }
    }

    static func cmdPrepare(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard let slug = a.positional(0) else { throw TramaError("uso: trama preparar <trama> [repo]") }
        let t = try w.trama(slug)
        let names: [String]
        if let key = a.positional(1) {
            names = [try w.repo(key).name]
        } else {
            names = t.repos.filter { (try? w.repo($0).recipe.isEmpty) == false }
        }
        guard !names.isEmpty else { throw TramaError("nenhum repositório da trama tem receita de preparo") }
        var warnings: [Warning] = []
        for name in names {
            warnings += try w.prepare(t.slug, name)
            c.ok("\(name): preparo iniciado · log em \(Paths.abbreviate(w.prepLogPath(t.slug, name)))")
        }
        c.warnings(warnings)
    }

    static func cmdPath(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard let slug = a.positional(0) else { throw TramaError("uso: trama caminho <trama> [repo]") }
        let t = try w.trama(slug)
        if let key = a.positional(1) {
            c.line(w.worktreePath(t.slug, try w.repo(key).name))
        } else {
            c.line(w.tramaPath(t.slug))
        }
    }

    private struct WhereResponse: Encodable {
        var trama: String
        var title: String
        var branch: String
        var repo: String?
    }

    static func cmdWhere(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let (t, r) = try c.targetTrama(w, nil)
        if c.json { return try c.emitJSON(WhereResponse(trama: t.slug, title: t.title, branch: t.branch, repo: r?.name)) }
        c.line("\(t.title) (\(t.slug))" + (r.map { " · \($0.name)" } ?? ""))
    }


    static func cmdCode(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let t = try c.targetTrama(w, a.positional(0)).trama
        if a.has("abrir") {
            let launch = try w.codeWorkspaceLaunch(t.slug)
            try EditorDetection.launch(launch.path, app: launch.app)
            return c.ok("\(t.title) aberta no \(launch.app)")
        }
        c.line(try w.writeCodeWorkspace(t.slug))
    }

    static func cmdCapsule(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let t = try c.targetTrama(w, a.positional(0)).trama
        let capsule = try w.readCapsule(t.slug)
        if c.json { return try c.emitJSON(capsule) }
        guard capsule.exists else {
            throw TramaError("a cápsula de \(t.slug) ainda não existe (\(capsule.path))")
        }
        c.text(capsule.markdown)
    }

    static func cmdContext(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let t = try c.targetTrama(w, a.value("trama")).trama
        guard let target = a.positional(0) else {
            let current = w.contextPath(t.slug).map { Paths.abbreviate($0) } ?? "nenhum"
            c.line("contexto de \(t.title): \(current)\(t.context == nil ? " (padrão global)" : "")")
            return
        }
        let updated = try w.setTramaContext(t.slug, target == "global" ? nil : target)
        c.ok("contexto de \(updated.title): \(updated.context.map { Paths.abbreviate($0) } ?? "padrão global")")
    }

    static func cmdGoal(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let t = try c.targetTrama(w, a.value("trama")).trama
        try w.setGoal(t.slug, a.text(from: 0))
        c.ok("objetivo de \(t.title) atualizado")
    }

    static func cmdDecision(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let (t, r) = try c.targetTrama(w, a.value("trama"))
        try w.addDecision(t.slug, author: c.author(r, a.value("autor")), a.text(from: 0))
        c.ok("decisão registrada na cápsula de \(t.title)")
    }

    static func cmdHandoff(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard a.positionals.count >= 2 else { throw TramaError("uso: trama handoff <repo destino> \"texto\"") }
        let (t, r) = try c.targetTrama(w, a.value("trama"))
        let to = (try? w.repo(a.positionals[0]).name) ?? a.positionals[0]
        var from = r?.name ?? ""
        if let de = a.value("de") {
            from = (try? w.repo(de).name) ?? de
        }
        try w.addHandoff(t.slug, from: from, to: to, author: c.author(r, a.value("autor")), a.text(from: 1))
        c.ok("handoff para \(to) registrado na cápsula de \(t.title)")
        if !t.repos.contains(to) {
            c.error("  aviso: \(to) não faz parte desta trama · para incluir: trama sugerir \(to) \"motivo\" --trama \(t.slug)")
        }
    }

    static func cmdReceived(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let (t, r) = try c.targetTrama(w, a.value("trama"))
        var n = 0
        if let s = a.positional(0) {
            guard let v = Int(s) else { throw TramaError("número inválido: \(s)") }
            n = v
        }
        var to = r?.name
        if let v = a.value("repo") {
            to = try w.repo(v).name
        }
        if n == 0 && to == nil {
            throw TramaError("rode dentro do worktree do repositório, passe --repo ou o número do handoff")
        }
        let count = try w.confirmHandoffs(t.slug, to: to, number: n)
        if count == 0 {
            c.line("Nenhum handoff pendente para marcar.")
        } else {
            c.ok("\(count) \(plural(count, "handoff marcado como recebido", "handoffs marcados como recebidos"))")
        }
    }

    static func cmdPending(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let t = try c.targetTrama(w, a.value("trama")).trama
        try w.addPending(t.slug, a.text(from: 0))
        c.ok("pendência adicionada em \(t.title)")
    }

    static func cmdDone(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let t = try c.targetTrama(w, a.value("trama")).trama
        guard let n = a.positional(0).flatMap(Int.init), n >= 1 else {
            throw TramaError("uso: trama feito <número da pendência> (veja os números em `trama capsula --json`)")
        }
        try w.completePending(t.slug, n)
        c.ok("pendência \(n) concluída")
    }

    static func cmdNote(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let t = try c.targetTrama(w, a.value("trama")).trama
        let text = a.text(from: 0)
        guard !text.isEmpty else { throw TramaError("a nota está vazia") }
        try w.addJournal(t.slug, text)
        c.ok("nota registrada no diário de \(t.title)")
    }

    static func cmdSync(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let slugs = try a.positional(0).map { [try w.trama($0).slug] } ?? w.tramas().map(\.slug)
        var n = 0
        for s in slugs {
            do {
                if try w.syncCapsule(s) {
                    n += 1
                    c.ok("cápsula de \(s) commitada")
                }
            } catch {
                throw TramaError("\(s): \(errorMessage(error))")
            }
        }
        if n == 0 { c.line("Nada novo nas cápsulas.") }
    }


    static func cmdFindings(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let list = try w.findings()
        if c.json { return try c.emitJSON(list) }
        guard !list.isEmpty else { return c.line("Nada perdido por aqui. ✨") }
        for x in list {
            let timestamp = x.timestamp.map { $0 > 0 ? " · " + relativeTime($0) : "" } ?? ""
            c.line("• \(x.title) · \(x.detail)\(timestamp)")
            if let s = x.suggestion { c.line("    \(s)") }
            if let items = x.items, !items.isEmpty { c.line("    \(items.joined(separator: ", "))") }
            if let cmd = x.command { c.line("    → \(cmd)") }
        }
    }

    static func cmdAdopt(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard let repo = a.positional(0), let into = a.value("para") else {
            throw TramaError("uso: trama adotar <repo> --para <trama>")
        }
        try w.adoptChanges(repo, into: into)
        c.ok("mudanças levadas para a trama \(into)")
    }

    static func cmdClean(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        guard let repo = a.positional(0) else { throw TramaError("uso: trama limpar <repo>") }
        let deleted = try w.cleanMerged(repo).sorted()
        guard !deleted.isEmpty else { return c.line("Nenhuma branch para limpar.") }
        let n = deleted.count
        c.ok("\(n) \(plural(n, "branch apagada", "branches apagadas")): \(deleted.joined(separator: ", "))")
    }

    static func cmdFetch(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let warnings = w.fetchAll()
        let total = w.config.repos.count
        if total > 0 && warnings.count == total {
            c.warnings(warnings)
            throw TramaError("não consegui atualizar nenhum repositório")
        }
        let ok = total - warnings.count
        c.ok("bases atualizadas em \(ok) \(plural(ok, "repositório", "repositórios"))")
        c.warnings(warnings)
    }

    static func cmdAgents(_ c: Context, _ a: Arguments) throws {
        let w = try c.open()
        let list = try w.agents()
        if c.json { return try c.emitJSON(list) }
        guard !list.isEmpty else { return c.line("Nenhum agente rodando em tramas agora.") }
        c.text(table(list.map { [$0.trama, $0.repo, describe($0), relativeTime($0.updatedAt)] }))
    }


    static func cmdHook(_ c: Context, _ a: Arguments) throws {
        let data = c.cli.readInput()
        guard let input = try? JSONDecoder().decode(HookInput.self, from: data),
              let w = try? c.open(),
              let out = try? w.handleHook(input),
              !out.isEmpty else { return }
        c.line(out)
    }

    static func cmdTools(_ c: Context, _ a: Arguments) throws {
        switch a.positional(0) ?? "status" {
        case "status":
            let rows = ToolInstaller.all.map { (tool: $0, version: $0.version) }
            if c.json {
                return try c.emitJSON(Dictionary(uniqueKeysWithValues: rows.map { ($0.tool.id, $0.tool.isInstalled) }))
            }
            for row in rows {
                c.line("\(row.tool.isInstalled ? "✓" : "✗") \(row.tool.id) · \(row.tool.title) · \(row.version ?? "não instalado")")
            }
            if !ToolInstaller.missing().isEmpty { c.line("  instale com: trama ferramentas instalar todas") }
        case "instalar", "install":
            let target = a.positional(1) ?? "todas"
            let tools: [InstallableTool]
            if ["todas", "todos", "all"].contains(target) {
                tools = ToolInstaller.missing()
            } else if let tool = ToolInstaller.named(target) {
                tools = [tool]
            } else {
                throw TramaError("ferramenta desconhecida: \(target) (use gh, glab, az ou todas)")
            }
            guard !tools.isEmpty else { return c.ok("todas as ferramentas já estão instaladas") }
            for tool in tools {
                guard !tool.isInstalled else {
                    c.line("✓ \(tool.id) já instalado")
                    continue
                }
                c.line("instalando \(tool.id)…")
                guard ToolInstaller.runInTerminal(tool.installCommand) == 0, tool.isInstalled else {
                    throw TramaError("não consegui instalar o \(tool.id)")
                }
                c.ok("\(tool.id) instalado")
            }
        default:
            throw TramaError("use: trama ferramentas [status|instalar [gh|glab|az|todas]]")
        }
    }

    static func cmdHooks(_ c: Context, _ a: Arguments) throws {
        let settings = a.value("settings") ?? Hooks.settingsPath()
        switch a.positional(0) ?? "status" {
        case "instalar", "install":
            try Hooks.install(settings: settings, executable: Workspace.currentExecutable())
            c.ok("hooks do Trama instalados em \(Paths.abbreviate(settings))")
            c.line("  (cópia do arquivo original em settings.json.antes-da-trama)")
            c.line("  Sessões novas do Claude Code dentro de uma trama já recebem a cápsula e aparecem no app.")
        case "remover", "uninstall":
            let n = try Hooks.remove(settings: settings)
            c.ok("\(n) \(plural(n, "hook do Trama removido", "hooks do Trama removidos"))")
        case "status":
            let st = try Hooks.status(settings: settings)
            if c.json { return try c.emitJSON(st) }
            for name in st.keys.sorted() {
                c.line("\(st[name] == true ? "✓" : "✗") \(name)")
            }
        default:
            throw TramaError("use: trama hooks instalar|remover|status")
        }
    }

    static func cmdSkill(_ c: Context, _ a: Arguments) throws {
        switch a.positional(0) ?? "status" {
        case "instalar", "install":
            try AgentSkill.install(executable: Workspace.currentExecutable())
            c.ok("skill do Trama instalada em \(Paths.abbreviate(AgentSkill.path()))")
            c.line("  Sessões novas do Claude Code, em qualquer pasta, passam a saber criar e gerenciar tramas.")
        case "remover", "uninstall":
            let removed = try AgentSkill.remove()
            c.ok(removed ? "skill do Trama removida" : "a skill do Trama não estava instalada")
        case "status":
            let on = AgentSkill.isInstalled()
            if c.json { return try c.emitJSON(["instalada": on]) }
            c.line("\(on ? "✓" : "✗") skill do Trama (\(Paths.abbreviate(AgentSkill.path())))")
        default:
            throw TramaError("use: trama skill instalar|remover|status")
        }
    }
}
