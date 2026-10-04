# Trama Drama

- **Branch:** `trama/trama-drama`
- **Repositórios:** trama
- **Tarefa:** Seleção de direcionamento

## Objetivo

Outro

## Decisões

- 2026-09-30 19:56 · agente · trama: Destino do Claude (Desktop ou CLI embutido) é uma preferência (UserDefaults 'claudeTarget'); o Desktop abre via claude://code/new?folder=<caminho>. Todos os pontos de chamada passam por AppModel.openClaude.
- 2026-10-01 18:01 · agente · trama: Credenciais Git ficam no Keychain por host (Ajustes > Contas Git), injetadas via GIT_CONFIG_* nos comandos git e via GH_TOKEN/GITLAB_TOKEN/AZURE_DEVOPS_EXT_PAT nas CLIs. Falhas de autenticação do git orientam o usuário para essa tela (GitError.isAuthenticationFailure).
- 2026-10-01 18:20 · agente · trama: Ferramentas (gh, glab, az) são instaladas pelo Trama via Homebrew (instalado se faltar): Ajustes > Ferramentas, botão de login em Contas Git e 'trama ferramentas [instalar]'. Lógica em Engine/Tools.swift.
- 2026-10-01 18:38 · agente · trama: Blur no topo da aba Git (BlurScrollView em Theme.swift) usa o efeito nativo do macOS 26 (scrollEdgeEffectStyle .soft + safeAreaBar), pois .ultraThinMaterial com máscara não borra o conteúdo que rola. Ainda sem confirmação visual; se não aparecer, colocar conteúdo real na barra do topo.
- 2026-10-01 18:54 · você: Nunca enviar commits com coauthors

## Handoffs


## Pendências


## Diário

- 2026-09-30 19:32 · trama criada com trama
- 2026-09-30 22:03 · repositório de contexto: ~/Documents/GitHub/trama
- 2026-09-30 22:39 · merge de main em trama
- 2026-10-01 11:21 · Objetivo atingido: Fazer com que seja possível selecionar se vai abrir o claude desktop ou cli emblutido, em todos os locais que fazer chamada para tal.
- 2026-10-01 12:21 · merge de main em trama
- 2026-10-01 13:20 · merge de main em trama
- 2026-10-01 14:42 · merge de main em trama
- 2026-10-01 14:52 · adotou 1 arquivo(s) esquecido(s) de trama
- 2026-10-01 14:53 · repositório de contexto: ~/Documents/GitHub/trama
- 2026-10-01 16:45 · merge de main em trama
- 2026-10-01 16:46 · merge de main concluído em trama com conflitos resolvidos
- 2026-10-01 17:13 · puxou rebocs_api para a trama
- 2026-10-01 17:13 · soltou rebocs_api da trama (a branch trama/trama-drama continua existindo)
- 2026-10-01 17:15 · puxou rebocs_api para a trama
- 2026-10-01 17:15 · soltou rebocs_api da trama (a branch trama/trama-drama continua existindo)
- 2026-10-01 18:16 · PRs: trama → main (GitHub, pelo navegador)
- 2026-10-01 18:24 · PRs: trama https://github.com/gabriellmlk3/trama/pull/1 → main
- 2026-10-01 18:45 · mescla direta de trama/trama-drama: trama → main
- 2026-10-01 18:46 · estacionada
- 2026-10-01 18:47 · retomada com rebase (trama: rebase)
- 2026-10-01 19:14 · mescla direta de trama/trama-drama: trama → main
- 2026-10-02 15:42 · merge de main em trama
- 2026-10-02 21:20 · merge de main em trama
