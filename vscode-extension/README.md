# Trama para VS Code

As tramas do app Trama dentro do editor. A extensão não tem lógica própria: ela chama o comando `trama … --json` e mostra o resultado.

## O que faz

- **Barra lateral Trama**
  - *Tramas*: cada trama com seus repositórios (↑↓, alterados, conflito previsto, agentes do Claude Code trabalhando ou aguardando).
  - *Cápsula*: objetivo, pendências (marque como feitas ali mesmo), handoffs, decisões e diário da trama desta janela.
  - *Achados*: trabalho esquecido nos repositórios (`trama achados`).
- **Barra de status**: a trama da janela atual e quantos agentes aguardam você.
- **Abrir trama…**: gera o `.code-workspace` (`trama vscode`) e abre todos os repositórios da trama numa janela só.
- **Comandos** (paleta, prefixo *Trama*): escrever no diário, registrar decisão, acrescentar pendência, passar trabalho para outro repositório, estacionar, retomar e abrir os PRs.

A trama da janela é descoberta pelas pastas abertas: qualquer pasta dentro de `<raiz>/<trama>/` conta.

## Instalar

Precisa do app Trama instalado (o executável dele também é o comando `trama`). A extensão procura o comando no `PATH` e em `/Applications/Trama.app`; se estiver em outro lugar, ajuste `trama.executable`.

```bash
cd vscode-extension
npm install
npm run package
code --install-extension trama-vscode-0.1.0.vsix
```

Para desenvolver: abra esta pasta no VS Code, rode `npm run watch` e aperte F5.

## Configurações

| Chave | Padrão | Para quê |
|---|---|---|
| `trama.executable` | vazio | caminho do comando `trama` |
| `trama.home` | vazio | pasta das tramas (`TRAMA_HOME`) |
| `trama.refreshSeconds` | 20 | intervalo de atualização |
| `trama.openInNewWindow` | true | abrir a trama escolhida em outra janela |
