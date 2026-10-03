# Trama

**Pare de trocar de branch. Entre numa trama.**

App de macOS para trabalhar com vários repositórios ao mesmo tempo usando agentes (Claude Code). Em vez de fazer `checkout` em cada repositório, você cria uma **trama**: a mesma branch em todos os repositórios envolvidos, cada um no seu próprio *git worktree*, mais uma **cápsula de contexto** que os agentes leem ao começar e escrevem ao terminar.

```
~/Tramas/
  surcharge-noturno/          ← uma trama
    CLAUDE.md                 ← instruções que todo agente desta trama carrega
    CAPSULA.md → rebocs-context/tramas/surcharge-noturno.md
    rebocs_api/               ← worktree na branch trama/surcharge-noturno
    rebocs-admin/             ← worktree na mesma branch
  onboarding-prestador/       ← outra trama, em paralelo
```

Trocar de trama é trocar de pasta. Várias tramas vivem ao mesmo tempo, cada uma com seus agentes.

## Rodar

1. Abra `trama.xcodeproj` no Xcode e aperte **⌘R**.
2. Na primeira vez, o app pede o repositório de contexto (ex.: `rebocs-context`), os repositórios que podem entrar em tramas, e se deve ligar os hooks do Claude Code e o comando `trama` no Terminal.
3. **⌘N** cria uma trama.

Para usar no dia a dia, copie o app para Aplicativos (Product ▸ Archive… ▸ Distribute App ▸ Copy App, ou arraste `Trama.app` da pasta de build). Ao abrir de lá, ele reaponta os hooks e o comando para a nova cópia sozinho.

## Como os agentes entram na trama

- **`CLAUDE.md` na pasta da trama.** O Claude Code carrega os `CLAUDE.md` das pastas acima de onde é aberto, então todo agente aberto em `~/Tramas/<trama>/<repo>` já sabe que está numa trama e como registrar o que faz.
- **Hooks do Claude Code** (em `~/.claude/settings.json`, com cópia do original em `settings.json.antes-da-trama`): no início da sessão o agente recebe a cápsula e os handoffs endereçados ao repositório dele; durante a sessão o app mostra se ele está trabalhando, esperando aprovação ou terminou. Fora de uma trama os hooks não fazem nada.
- **Skill `trama`** (em `~/.claude/skills/trama/SKILL.md`, instalada junto com os hooks ou por `trama skill instalar`): ensina qualquer agente, aberto em qualquer pasta, a criar, acompanhar, estacionar, arquivar e abrir PRs de tramas pelo comando `trama`, sem precisar estar dentro de uma.
- **O comando `trama`.** É o próprio executável do app: chamado pelo link `~/.local/bin/trama` (ou como `Trama.app/Contents/MacOS/Trama <comando>`), ele roda a linha de comando e sai sem abrir janela.

| Comando | Para quê |
|---|---|
| `trama decisao "texto"` | Registra uma decisão que afeta a trama |
| `trama handoff <repo> "texto"` | Passa trabalho para o agente de outro repositório |
| `trama recebido` | Marca como lidos os handoffs para o seu repositório |
| `trama pendencia "texto"` / `trama feito <n>` | Pendências da trama |
| `trama capsula` | Mostra a cápsula atual |
| `trama status` | Situação de todos os repositórios da trama |
| `trama nova "Título" --repos a,b` | Cria uma trama pelo terminal |
| `trama estacionar` / `trama retomar <trama> --rebase` | Pausa e retoma (conflitos de rebase são desfeitos e avisados) |
| `trama achados` | Procura trabalho esquecido: mudanças soltas, commits só locais, branches órfãs, handoffs sem resposta |

`trama ajuda` lista todos; `trama <comando> --ajuda` mostra os detalhes.

## Estrutura

| Pasta | O que é |
|---|---|
| `trama/Engine/` | O motor: git, tramas, worktrees, cápsula, achados, hooks e o comando `trama`. Só Foundation, sem AppKit/SwiftUI. |
| `trama/State/` | Ponte entre motor e interface (`AppModel`), integração com hooks/Terminal. |
| `trama/Screens/` | As telas em SwiftUI: o tear, a cápsula, nova trama, retomar, achados & perdidos, barra de menus, ajustes. |
| `trama/Theme/` | Cores, tipografia e componentes visuais (tema escuro). |
| `tramaTests/` | Testes do motor com repositórios git reais (⌘U). |

O app não usa App Sandbox: ele precisa rodar `git` nos seus repositórios, criar worktrees em `~/Tramas` e editar `~/.claude/settings.json`.
