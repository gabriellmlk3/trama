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
- Usar a CLI do provedor do repositório (`gh`, `az` ou `glab`; veja "Provedores" abaixo). Para cada repositório com commits à frente da base: `git push -u`, depois criar o PR com `--base <base>` e a branch da trama, com título da trama e corpo gerado a partir da cápsula (objetivo, decisões).
- Depois de criar todos, editar os corpos para incluir links cruzados entre os PRs.
- Ordem de merge configurável (ex.: API antes dos clientes), mostrada no corpo de cada PR.
- `Trama` guarda as URLs dos PRs; o tear mostra o estado e o CI de cada um (no GitHub, `gh pr view --json state,statusCheckRollup`; no Azure DevOps, as políticas de build do PR; no GitLab, o pipeline do MR).
- Comando: `trama pr [--rascunho]`. Botão "Abrir PRs" no cabeçalho da trama.
- Destino selecionável: o botão abre uma folha com uma linha por repositório (destino, commits à frente, conflito previsto contra o destino escolhido e situação do PR). "Todos para" aplica uma branch aos repositórios que a têm; cada linha pode ter o seu destino. A escolha fica em `destinosPR` na trama; PR aberto que aponta para outra branch é redirecionado (`gh pr edit --base`, `glab mr update --target-branch` ou, no Azure DevOps, `az devops invoke` com PATCH em `targetRefName`); PR mesclado ou fechado não é tocado. Outras tramas (`trama/…`) aparecem como destino para empilhar PRs.
- Provedores: cada repositório abre PR no seu provedor, detectado pelo remoto `origin` (github.com ou host com "github" → GitHub; `dev.azure.com`, `*.visualstudio.com` ou URL com `/_git/` → Azure DevOps; gitlab.com ou host com "gitlab" → GitLab; bitbucket.org → Bitbucket). Um repositório pode fixar o provedor (`provedor` em `config.json`; Preferências ou `trama repo provedor <nome> <github|azure|gitlab|bitbucket|manual|auto>`), o que serve para hosts com domínio próprio. Variáveis `TRAMA_GH`, `TRAMA_AZ` e `TRAMA_GLAB` apontam para o executável de cada CLI.
- Sem automação (Bitbucket, host desconhecido ou CLI não instalada) a branch sobe e o PR abre pelo link de "novo PR" do provedor, no navegador. Nada é gravado em `prs`, só o destino escolhido.
- Limites por provedor: o Azure DevOps limita a descrição a 4000 caracteres (as decisões são cortadas, os links entre PRs ficam); trocar o destino de um PR no Azure depende de o recurso estar habilitado na organização.
- Na linha de comando: `trama pr --base develop`, `--base api=staging,admin=develop`, `--repo a,b` para limitar a rodada e `--simular` para ver o plano sem enviar nada.

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

---

## 4. Terminal próprio

Objetivo: desempenho, controle e aparência no terminal embutido, no estilo do Warp. Hoje o terminal é o SwiftTerm (`LocalProcessTerminalView`) usado em `State/TerminalSessions.swift` e `Screens/TerminalDrawer.swift`. A troca é gradual: cada fase deixa o app funcionando, e o motor só muda depois de validado contra gravações reais.

Decisões: barra de entrada própria no lugar do prompt do shell; só zsh no início. Lógica em `trama/Engine/Terminal/` (só Foundation, com teste em `tramaTests/`); interface e renderizador em `trama/Screens/`.

### 4.1 Isolar o terminal atrás de um protocolo

**Problema.** `TerminalSession`, `TerminalStore` e `TerminalDrawer` conhecem o `LocalProcessTerminalView`, então trocar o motor mexe em tudo.

**Como.**
- Protocolo `TerminalEngine` (iniciar, enviar bytes, redimensionar, encerrar, entregar saída e eventos); o SwiftTerm fica atrás de uma implementação.
- `TerminalSession` guarda o protocolo, não a view; o drawer pede a view ao motor.

**Pronto quando** nenhum arquivo fora da implementação do SwiftTerm importa SwiftTerm e o terminal se comporta como antes.

### 4.2 PTY próprio

**Problema.** O `LocalProcess` do SwiftTerm é dono do PTY, então não dá para interceptar a entrada e a saída.

**Como.**
- `Engine/Terminal/PTY.swift`: `forkpty`/`posix_spawn`, leitura numa fila dedicada com buffers em lote, redimensionamento (`TIOCSWINSZ`), encerramento e código de saída.
- O SwiftTerm passa a receber os bytes pelo `TerminalEngine`.

**Pronto quando** as sessões abertas pelo app funcionam como antes, usando o PTY próprio, e a saída pode ser gravada e reproduzida.

### 4.3 Integração com o zsh e blocos

**Problema.** O app não sabe onde cada comando começa e termina, nem o diretório atual.

**Como.**
- `ZDOTDIR` temporário com um `.zshrc` que carrega o do usuário e acrescenta os hooks `precmd`/`preexec`, emitindo OSC 133 (A/B/C/D) e OSC 7.
- Parser desses marcadores sobre o fluxo de bytes e modelo `TerminalBlock` (comando, saída, código de saída, duração, diretório).
- Teste com um zsh real: os blocos de `ls`, de um comando que falha e de um multilinha.

**Pronto quando** cada comando executado numa sessão gera um bloco com início, fim, código de saída e duração corretos.

### 4.4 Spike da libghostty-vt

**Problema.** Escrever parser e grade próprios é o trecho mais arriscado do plano; a `libghostty-vt` pode entregá-lo pronto.

**Como.**
- Confirmar no repositório o estado atual da API C e como obter um `.xcframework` (ou compilar com Zig).
- Alimentar a biblioteca com os bytes gravados de sessões do Claude Code, vim e htop e ler a grade resultante.
- Medir: tempo de build, tamanho do binário, vazão em `yes`/`cat` de arquivo grande, e cobertura do que o Claude Code usa (tela alternativa, mouse, bracketed paste, teclado estendido).
- Registrar a decisão no commit/PR: adotar, ou seguir para 4.5.

**Pronto quando** houver uma decisão escrita (adotar ou parser próprio) com os números do spike.

### 4.5 Parser e grade (biblioteca ou próprios)

**Problema.** O SwiftTerm limita desempenho e controle sobre a grade.

**Como.**
- Implementação de `TerminalEngine` sobre a `libghostty-vt` (se 4.4 aprovar) ou sobre um parser VT e uma grade próprios em `Engine/Terminal/`.
- Rodar em paralelo ao SwiftTerm com a mesma suíte: vttest/esctest e as gravações de 4.4, comparando a grade célula a célula.
- Reflow, Unicode largo, emoji, seleção e scrollback com testes próprios.

**Pronto quando** a grade coincide com a do SwiftTerm em toda a suíte, ou as diferenças estão documentadas e aceitas.

### 4.6 Renderizador Metal

**Problema.** A view do SwiftTerm redesenha mais do que precisa.

**Como.**
- `Screens/Terminal/`: `MTKView` com atlas de glifos via CoreText, redesenhando só as linhas sujas; cursor, seleção e cores vindos de `Theme.swift`.
- Entrada de teclado, mouse, colar com bracketed paste e arrastar arquivos.

**Pronto quando** `yes` e `cat` de um arquivo grande rolam sem queda de quadros e com menos CPU que o SwiftTerm, na mesma máquina.

### 4.7 Trocar o motor e remover o SwiftTerm

**Problema.** Duas implementações em paralelo custam manutenção.

**Como.**
- Motor novo passa a ser o padrão; um ajuste temporário permite voltar ao SwiftTerm por uma versão.
- Depois de um tempo de uso real, remover o pacote do `project.pbxproj` e o código antigo.

**Pronto quando** o app roda sem a dependência do SwiftTerm e sem regressão nas sessões do dia a dia.

### 4.8 Interface estilo Warp

**Problema.** O terminal ainda parece um terminal comum e não conhece a trama.

**Como.**
- Linha do tempo de blocos (cabeçalho com comando, duração e status; copiar só a saída; recolher; pular entre blocos).
- Barra de entrada própria em SwiftUI com edição multilinha, histórico e atalhos; envia a linha ao PTY e vira passagem direta quando um programa de tela cheia assume (tela alternativa).
- Integração com o Trama: sessão ligada à trama e ao repositório, estado do agente (`Agents.swift`), enviar um bloco para a cápsula ou para os achados, abrir o arquivo citado num erro.
- Reabrir as sessões da trama no mesmo diretório ao reiniciar o app.

**Pronto quando** uma sessão de shell mostra blocos com a barra própria, o Claude Code roda em tela cheia sem a barra, e um bloco pode ser enviado para a cápsula com um clique.

**Ordem.** 4.1 → 4.2 → 4.3 (o app já ganha status por comando); 4.8 pode começar depois de 4.3, em cima do SwiftTerm; 4.4 → 4.5 → 4.6 → 4.7 trocam o motor sem mexer na interface.

---

## 5. Time na rede

Objetivo: os devs de um mesmo escritório verem o que os outros estão fazendo e serem avisados antes de um conflito. Tudo isso só existe quando há um servidor de time configurado; sem ele, nenhuma tela, comando ou hook muda.

Decisões:
- **Escopo.** 8 pessoas, presenciais, na mesma rede. Um único time por servidor. Só metadados (caminhos, estados, textos de handoff), nunca conteúdo de arquivo.
- **Servidor.** O próprio executável do app, como `trama servidor`, num processo separado e desacoplado do app (arquivo de pid com `flock` em `~/.trama/servidor/`, um por Mac). Estado em SQLite. O host também é cliente, conectando em `localhost`. Mantém o Mac acordado enquanto houver conexões. Por ora o host é o Mac de uma pessoa; migrar para um host fixo não deve mudar o protocolo.
- **Transporte.** Um único canal WebSocket (`NWListener` com `NWProtocolWebSocket` no servidor, `URLSessionWebSocketTask` no cliente), HTTP puro sem TLS na v1. Mensagens JSON com `id` e `type`; o cliente reconecta com backoff e manda `resume { since }` para receber o que perdeu. Porta fixa, 7447 por padrão.
- **Descoberta.** Bonjour (`_trama._tcp`) só como catálogo, anunciando o nome do time e a versão do protocolo, nada mais. O app guarda o nome do servidor e o resolve de novo ao reconectar, com o último endereço conhecido e a digitação manual como fallback. Exige `NSLocalNetworkUsageDescription` e `NSBonjourServices`.
- **Identidade.** Convite de uso único: `trama time entrar <endereço> <código>` devolve um token por pessoa, guardado no Keychain (o servidor guarda só o hash). Nome de exibição vindo de `git config user.name`. `trama time remover <nome>` revoga.
- **Versões.** Número de `protocol` no handshake; o servidor aceita o protocolo atual e o anterior e responde com erro claro ("atualize o Trama"). Campos novos só aditivos, campos desconhecidos ignorados.
- **Repositório.** Chave `repoKey` = URL do `origin` normalizada (sem protocolo, usuário nem `.git`; SSH e HTTPS equivalem). Repo sem `origin` não participa. Colisão só dentro da mesma `repoKey` e da mesma base.

### 5.0 Spike do transporte

**Problema.** A hipótese de uma única porta só com WebSocket (sem HTTP puro) e com token no header do handshake ainda não foi confirmada.

**Como.**
- Protótipo descartável: `NWListener` com `NWProtocolWebSocket`, autenticação no handshake, cliente com `URLSessionWebSocketTask`, queda e reconexão.
- Se não servir, o plano cai para HTTP com polling por cursor (`GET /v1/changes?since=`), mantendo o mesmo modelo de mensagens.

**Pronto quando** dois processos conversam por WebSocket autenticado e o cliente retoma depois de uma queda do servidor.

### 5.1 Servidor, convite e conexão

**Problema.** Não há onde as máquinas se encontrem.

**Como.**
- `trama/Engine/Team/` (só Foundation e Network): servidor, cliente, protocolo, armazenamento SQLite, anúncio e busca por Bonjour.
- Comandos em `Engine/CLICommands.swift`: `trama servidor`, `trama time criar|entrar|sair|remover|status`.
- Preferências ▸ "Time (opcional)": conectar, hospedar (liga e desliga o processo), copiar convite, mostrar estado lendo o pid e tentando a porta.
- Indicador discreto na barra quando o time está configurado mas offline ou incompatível. Sem time configurado, não aparece nada.

**Pronto quando** uma segunda máquina entra com o convite, reconecta sozinha depois de o host reiniciar e mostra "versão incompatível" quando o protocolo difere.

### 5.2 Presença e aviso de colisão

**Problema.** Dois devs mexem no mesmo arquivo sem saber, e o conflito só aparece no merge.

**Como.**
- Cada Trama publica, por repo de cada trama compartilhada: `repoKey`, base, estado (ativa, estacionada), agentes, e a lista de caminhos alterados em relação à base (commits locais, working tree e arquivos que o agente editou; a lista nasce de `Git.statusLines`).
- O hook `PostToolUse` já instalado registra o arquivo editado pelo agente no estado local; o app (ou o processo do CLI) publica no ciclo seguinte, então o hook nunca depende do servidor.
- Interruptor "compartilhar com o time" por trama, ligado por padrão; trama privada não publica, não gera nem recebe aviso.
- Validade: retratação imediata ao arquivar, apagar ou desligar o compartilhamento; offline não apaga; estacionada conta, com rótulo; expira após 7 dias sem atualização (configurável no servidor).
- Dois níveis: **ativa** (o outro está online e mexeu há pouco: notificação do sistema) e **latente** (offline, estacionado ou parado: só a linha na trama).
- Interface: linha de aviso no repo dentro de `TramaDetail` ("Ana também altera 2 arquivos") com a lista de arquivos, pessoa, trama e quando. Também entra em `trama achados`.

**Pronto quando** duas máquinas com o mesmo `origin` e a mesma base editam o mesmo arquivo e ambas veem o aviso em até alguns segundos, e a Ana fechar o app mantém o aviso como latente.

### 5.3 Aviso ao agente

**Problema.** Quem está editando naquele momento é o agente, e ele não sabe da colisão.

**Como.**
- O hook devolve `additionalContext` curto, em português e marcado como informativo ("Ana, na trama `x`, também está alterando `Arquivo.kt`. Evite refatorar esse arquivo ou avise antes").
- Um aviso por arquivo por sessão, nunca bloqueia a edição, e fica em silêncio enquanto o servidor estiver offline (o aviso poderia estar velho).

**Pronto quando** um agente que edita um arquivo já alterado por outra pessoa recebe o aviso uma única vez na sessão.

### 5.4 Aba "Time" e handoff entre pessoas

**Problema.** Não há como ver quem está em quê nem passar trabalho para outra pessoa.

**Como.**
- Aba "Time" na barra lateral: pessoas com online/offline e última atividade, tramas ativas, repos, estado dos agentes, e a caixa de entrada com badge de não lidos.
- `trama handoff <repo> "texto" --para <pessoa>`: o handoff vai para a caixa pessoal no servidor, roteado por `repoKey`, com remetente e, opcionalmente, trama e branch de origem. Qualquer agente da pessoa que abrir sessão num repo com a mesma `repoKey` o recebe no contexto até ela marcar como lido. Não escreve na cápsula de ninguém.
- Fila local para handoffs enviados offline, entregues ao reconectar (é a única coisa que persiste localmente).
- Notificação do sistema só para colisão ativa e handoff recebido; nada de notificar presença.
- Fora do escopo: chat, histórico de atividade, quadro do time.

**Pronto quando** a Ana recebe, com o app fechado ao enviar, um handoff endereçado a ela assim que reconectar, e o agente dela o lê ao abrir uma sessão no repo indicado.

### Riscos

- O host é o Mac de uma pessoa: quando ele dorme ou o servidor para, o ao vivo some (o histórico fica no SQLite).
- Versões diferentes do app: se o host atualiza o protocolo antes dos outros, todos caem até atualizarem.
- `NWProtocolWebSocket` no servidor pode não permitir o desenho de porta única (ver 5.0).
- O macOS pede a permissão de Rede Local na primeira busca por Bonjour; negar quebra a descoberta (o fallback manual continua valendo).
- Processo servidor órfão se o pid se perder; o estado é checado também tentando a porta.

**Ordem.** 5.0 → 5.1 → 5.2 → 5.3 → 5.4. Fora desta seção: ligar com "Vestir a trama de outra máquina" (3.2), TLS, LaunchAgent para iniciar no login e a extensão do VS Code.
