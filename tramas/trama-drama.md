# Trama Drama

- **Branch:** `trama/trama-drama`
- **Repositórios:** trama
- **Tarefa:** Seleção de direcionamento

## Objetivo

Verificar como usar um agent só com todos os repositórios

## Decisões

- 2026-09-30 19:56 · agente · trama: Destino do Claude (Desktop ou CLI embutido) é uma preferência (UserDefaults 'claudeTarget'); o Desktop abre via claude://code/new?folder=<caminho>. Todos os pontos de chamada passam por AppModel.openClaude.
- 2026-09-30 23:08 · agente · trama: Agent único por trama: 'Abrir no Claude' agora abre uma sessão na raiz da trama com --add-dir para cada worktree (preferência agentScope, padrão 'single'; 'perRepo' mantém o comportamento antigo). No Desktop só a pasta da trama é aberta, pois a URL claude://code/new aceita uma pasta.

## Handoffs


## Pendências


## Diário

- 2026-09-30 19:32 · trama criada com trama
- 2026-09-30 22:03 · repositório de contexto: ~/Documents/GitHub/trama
- 2026-09-30 22:39 · merge de main em trama
- 2026-09-30 23:05 · Objetivo atingido: Fazer com que seja possível selecionar se vai abrir o claude desktop ou cli emblutido, em todos os locais que fazer chamada para tal.
