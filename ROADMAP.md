# Roadmap do Trama

Próximas funcionalidades, em ordem de prioridade dentro de cada grupo. Cada item cabe numa trama e numa sessão de agente: tem o problema, onde mexer no código e quando está pronto. A camada de IA (resumo ao retomar, revisor da trama, "ondas") fica para depois destes.

Convenções do projeto: veja `CLAUDE.md`. Lógica nova vai em `trama/Motor/` (só Foundation, com teste em `tramaTests/`); interface em `trama/Telas/`.

---

## 1. O que mais faz falta agora

### 1.1 Preparar o worktree ao criar

**Problema.** Um worktree novo não traz arquivos ignorados pelo git (`.env`, `local.properties`) nem dependências (`node_modules`). O agente abre a pasta e nada roda.

**Como.**
- `RepoConfig` ganha uma receita: `copiar: [String]` (padrões de arquivo, ex.: `.env*`, `local.properties`) e `rodar: [String]` (comandos, ex.: `npm ci`).
- Novo `Motor/Preparo.swift`: depois de `criarWorktree`, copia os arquivos da cópia principal e roda os comandos em segundo plano, com log em `<raiz>/.trama/logs/<trama>-<repo>.log`.
- Sugestão automática ao cadastrar o repositório: lockfile do npm/pnpm/yarn → install correspondente; `Podfile` → `pod install`; `.env*` existentes → copiar.
- Estado do preparo no tear: "preparando…", "pronto" ou "falhou", com link para o log.
- Comando: `trama repo preparo api --copiar .env --rodar "npm ci"`.
- Ajustes ▸ Repositórios: editar a receita.

**Pronto quando** uma trama nova no `rebocs_api` já abre com `.env` e dependências instaladas, sem intervenção.

### 1.2 Portas por trama

**Problema.** Duas tramas abertas brigam pela mesma porta (a API de uma derruba a da outra).

**Como.**
- Cada trama recebe um índice fixo; a faixa de portas é `base + 10 × índice`.
- `RepoConfig.servicos: [{nome, comando, porta}]` (ex.: `api`, `npm run dev`, `3000`).
- `trama subir [repo]` / `trama descer` sobem os serviços da trama com `PORT` e `TRAMA_PORTA_BASE` no ambiente; o app guarda os processos, mostra o log e derruba ao estacionar.
- Antes de subir, verifica se a porta está livre e avisa se não estiver.
- No tear: URL de cada serviço (`http://localhost:3010`) e botão de subir/descer.

**Pronto quando** duas tramas rodam a API ao mesmo tempo, cada uma na sua porta, com um clique.

### 1.3 Notificações

**Problema.** Um agente fica parado esperando aprovação e ninguém vê.

**Como.**
- Em `ModeloApp.atualizar`, comparar o estado anterior e o novo de cada agente; nas transições para `aguardando` e `concluiu`, disparar uma notificação (`UserNotifications`).
- Clicar na notificação abre a trama no app e traz o Terminal para frente.
- No ícone da barra de menus, o número de agentes esperando por você.
- Ajustes: ligar ou desligar cada tipo de aviso.

**Pronto quando** um agente pedir permissão com o app em segundo plano e aparecer uma notificação em até 5 s.

### 1.4 PRs da trama

**Problema.** Abrir e ligar os PRs de cada repositório à mão, na ordem certa, é onde as coisas se perdem.

**Como.**
- Usar o `gh`. Para cada repositório com commits à frente da base: `git push -u`, depois `gh pr create --base <base> --head <branch>`, com título da trama e corpo gerado a partir da cápsula (objetivo, decisões).
- Depois de criar todos, editar os corpos para incluir links cruzados entre os PRs.
- Ordem de merge configurável (ex.: API antes dos clientes), mostrada no corpo de cada PR.
- `Trama` guarda as URLs dos PRs; o tear mostra o estado e o CI de cada um (`gh pr view --json state,statusCheckRollup`).
- Comando: `trama pr [--rascunho]`. Botão "Abrir PRs" no cabeçalho da trama.

**Pronto quando** um clique abre os PRs de todos os repositórios, ligados entre si, e o tear mostra o CI de cada um.

---

## 2. Ligado ao que você já usa

### 2.1 ClickUp

**Problema.** A tarefa vive no ClickUp e a trama vive no Trama; o objetivo e o status ficam duplicados à mão.

**Como.**
- Token pessoal do ClickUp guardado no Keychain (Ajustes ▸ Integrações).
- Nova trama a partir do ID da tarefa: título vira o nome, descrição vira o objetivo da cápsula, ID e link vão para `Trama.tarefa`.
- Quando os PRs abrem (item 1.4): comentário na tarefa com os links e mudança de status configurável (ex.: "em revisão").
- Ao arquivar a trama: status final configurável.
- Comando: `trama nova --tarefa CU-482` busca o resto sozinho.

**Pronto quando** criar uma trama só com o ID da tarefa e ver os links dos PRs aparecerem no ClickUp.

### 2.2 Editor e terminal por repositório

**Problema.** Cada repositório abre num lugar diferente (admin no Cursor, iOS no Xcode, Android no Android Studio), e nem todo mundo usa o Terminal da Apple.

**Como.**
- `RepoConfig.editor` com detecção automática: `.xcodeproj` → Xcode, `build.gradle` → Android Studio, `package.json` → Cursor ou VS Code.
- Terminal escolhido nos Ajustes: Terminal, iTerm2, Ghostty ou Warp. O Terminal continua com o `.command`; para os outros, o jeito de abrir numa pasta e rodar `claude` de cada um.
- Botão "abrir no editor" em cada linha do tear e em "Abrir no Claude".

**Pronto quando** cada repositório abre no editor certo e o `claude` sobe no terminal escolhido.

---

## 3. Mais fora da caixa

### 3.1 Ponto de restauração

**Problema.** Um agente estraga algo em três repositórios ao mesmo tempo e não há como voltar todos juntos.

**Como.**
- `trama marcar "antes do refactor"`: para cada repositório, guarda o commit atual e as mudanças não commitadas (`git stash create`) em refs próprias, `refs/trama/<slug>/<ponto>/…`, para o git não apagar.
- `trama voltar <ponto>`: marca o estado atual antes (para dar para desfazer), volta cada repositório ao commit e reaplica as mudanças guardadas.
- Na cápsula: lista de pontos com data; no app, botão de marcar e voltar.

**Pronto quando** voltar um ponto deixar os três repositórios exatamente como estavam, inclusive arquivos não commitados.

### 3.2 Vestir a trama de outra máquina (ou de um colega)

**Problema.** A trama só existe na máquina onde foi criada.

**Como.**
- `trama publicar`: push de todas as branches da trama e da cápsula no repositório de contexto.
- Metadados da trama (repositórios, base, tarefa) gravados junto da cápsula, em `tramas/<slug>.json`.
- `trama vestir <slug>`: `git fetch` em cada repositório cadastrado, cria os worktrees a partir das branches remotas e reconstrói a trama a partir dos metadados.

**Pronto quando** `trama vestir surcharge-noturno` em outro Mac recriar a trama completa, com a cápsula.

### 3.3 Tramas empilhadas

**Problema.** Uma feature depende de outra que ainda não entrou na `main`.

**Como.**
- `NovaTramaOpcoes.tramaBase`: nos repositórios que a trama-mãe tem, a branch nova parte da branch da mãe; nos outros, da base normal.
- Status compara com a branch da mãe.
- Quando a mãe entra na `main`: `trama reancorar` faz `git rebase --onto main trama/<mãe>` em cada repositório.
- No tear, o fio da trama filha sai do fio da mãe.

**Pronto quando** criar uma trama em cima de outra, e ela seguir certa depois que a mãe for integrada.
