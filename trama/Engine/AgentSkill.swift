import Foundation

public enum AgentSkill {
    static let marker = "<!-- gerado pelo Trama -->"

    public static func path(home: String = Paths.home) -> String {
        Paths.join(home, ".claude", "skills", "trama", "SKILL.md")
    }

    static func command(_ executable: String) -> String {
        executable.contains(" ") ? "\"\(executable)\"" : executable
    }

    static func content(executable: String) -> String {
        let trama = command(executable)
        return """
        ---
        name: trama
        description: Cria e gerencia tramas (a mesma branch em vários repositórios, cada um num git worktree, com uma cápsula de contexto). Use quando o pedido envolver mudar mais de um repositório junto, começar uma tarefa multi-repo, listar, retomar, estacionar, arquivar ou abrir PRs de uma trama, ou quando falarem em "trama".
        ---
        \(marker)

        # Trama

        Uma **trama** é uma branch em vários repositórios, cada um no seu worktree em `<raiz>/<trama>/<repo>`, mais uma **cápsula** em markdown (objetivo, decisões, handoffs, pendências, diário). Tudo é feito pelo comando `trama`; se ele não estiver no PATH, use `\(trama)`.

        ## Regras para agentes

        - Antes de qualquer coisa: `trama estado` (JSON com repositórios cadastrados e tramas). Os nomes e apelidos válidos de repositório vêm de lá.
        - Prefira `--json` quando for ler a saída. Os comandos nunca pedem interação.
        - Fora do worktree de uma trama, informe a trama: `--trama <slug>` ou como argumento posicional, conforme o `uso` de cada comando (`trama <comando> --ajuda` mostra).
        - Não apague worktrees nem branches à mão: use `estacionar`, `arquivar` e `soltar`. Os comandos destrutivos (`arquivar`, `soltar`, `limpar`) recusam trabalho não commitado; só passe `--forcar` se o usuário pedir.
        - Se o usuário exigir aprovação para puxar repositórios (`trama repo puxada`), `trama puxar` e `trama repo add` feitos por você viram sugestão e esperam o aceite dele: não tente contornar.
        - Percebeu que a mudança toca um repositório fora da trama? Puxe com o motivo ou sugira (`trama sugerir`) em vez de editar a cópia principal dele.
        - Não rode `trama pr` sem o usuário pedir: ele faz push e abre PRs. Use `--simular` antes para mostrar o plano.

        ## Criar

        ```
        trama repo ls --json
        trama nova "Título da trama" --repos api,admin --objetivo "o que precisa ficar pronto" [--base main] [--tarefa CU-482]
        ```

        Escolha os repositórios que a mudança realmente toca; dá para incluir outros depois com `trama puxar <trama> <repo>`. O comando imprime a pasta de cada worktree: trabalhe lá, não na cópia principal do repositório. Cadastrar um repositório novo: `trama repo add <pasta>`.

        ## Acompanhar

        - `trama ls [--todas]` · tramas ativas (`--todas` inclui as arquivadas)
        - `trama status [trama]` · alterações, commits à frente/atrás e conflito previsto por repositório
        - `trama agentes` · sessões do Claude Code rodando nas tramas
        - `trama capsula <trama>` · contexto compartilhado
        - `trama caminho <trama> [repo]` · pasta da trama ou do worktree
        - `trama achados` · trabalho esquecido (mudanças soltas, branches sem PR)

        ## Alterar a trama

        - `trama puxar <trama> <repo>... --motivo "por que"` / `trama soltar <trama> <repo>` · inclui ou tira repositórios
        - `trama sugerir <repo|pasta> "motivo" --trama <slug>` · pede ao usuário para incluir outro repositório (cadastrado ou uma pasta git); ele aceita no app
        - `trama repo descobrir` · repositórios git ao lado dos cadastrados que ainda não estão no Trama
        - `trama estacionar <trama>` / `trama retomar <trama> [--rebase]` · pausa e reativa; os worktrees ficam como estão
        - `trama arquivar <trama>` · remove os worktrees quando tudo foi mergeado; as branches ficam
        - `trama merge <origem> --para <destino>` · traz os commits de uma trama para outra
        - `trama pr [--rascunho] [--base develop | --base api=staging] [--simular] --trama <slug>` · abre os PRs ligados entre si; `trama pr ls` mostra estado e CI

        ## Cápsula

        Registre o que o próximo agente precisa saber:

        - `trama objetivo "texto" --trama <slug>`
        - `trama decisao "texto" --trama <slug>` · contratos, escolhas de arquitetura
        - `trama handoff <repo destino> "texto" --trama <slug> --de <repo origem>` · pede trabalho ao agente de outro repositório
        - `trama pendencia "texto"` e `trama feito <n>` · lista de pendências
        - `trama nota "texto"` · diário

        ## Fluxo típico

        1. `trama estado` para ver repositórios e tramas existentes (talvez já exista uma trama para isso: retome-a em vez de criar outra).
        2. `trama nova ...` com título, repositórios e objetivo.
        3. Trabalhar nos worktrees, registrando decisões e handoffs.
        4. `trama status` para conferir; `trama pr --simular` e, com o aval do usuário, `trama pr`.
        5. Depois do merge: `trama arquivar <trama>`.
        """
    }

    public static func install(executable: String, home: String = Paths.home) throws {
        try File.write(content(executable: executable), to: path(home: home))
    }

    public static func isInstalled(home: String = Paths.home) -> Bool {
        isOurs(path(home: home))
    }

    @discardableResult
    public static func remove(home: String = Paths.home) throws -> Bool {
        let file = path(home: home)
        guard isOurs(file) else { return false }
        try FileManager.default.removeItem(atPath: file)
        let folder = Paths.parent(file)
        if (try? FileManager.default.contentsOfDirectory(atPath: folder))?.isEmpty == true {
            try? FileManager.default.removeItem(atPath: folder)
        }
        return true
    }

    @discardableResult
    public static func refreshIfInstalled(executable: String, home: String = Paths.home) -> Bool {
        guard isInstalled(home: home), let current = try? File.read(path(home: home)),
              current != content(executable: executable) else { return false }
        return (try? install(executable: executable, home: home)) != nil
    }

    private static func isOurs(_ file: String) -> Bool {
        ((try? File.read(file)) ?? nil)?.contains(marker) == true
    }
}
