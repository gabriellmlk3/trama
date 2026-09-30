# Trama — instruções para agentes

App de macOS (SwiftUI, Swift 5, macOS 14+) que gerencia "tramas": a mesma branch em vários repositórios, cada uma num git worktree, com uma cápsula de contexto em markdown. Leia o README.md para o conceito.

## Estrutura

- `trama/Engine/` — toda a lógica (git, tramas, cápsula, achados, hooks, CLI). **Só Foundation**: nada de AppKit/SwiftUI aqui, para continuar testável.
- `trama/State/` — `AppModel` (ObservableObject, @MainActor) chama o motor fora da thread principal via `Core.run { workspace in ... }`.
- `trama/Screens/` e `trama/Theme/` — interface. Cores e componentes ficam em `Theme.swift`; não use cores soltas nas telas.
- `tramaTests/` — XCTest do motor, com repositórios git temporários reais.

As pastas são sincronizadas com o projeto (Xcode 16+): **arquivo novo dentro delas entra no build sozinho**. Não edite `trama.xcodeproj/project.pbxproj` para adicionar arquivos. Nomes de arquivo `.swift` precisam ser únicos no alvo inteiro.

## Build e testes

```bash
xcodebuild -project trama.xcodeproj -scheme trama -destination 'platform=macOS' build
xcodebuild -project trama.xcodeproj -scheme trama -destination 'platform=macOS' test -only-testing:tramaTests
```

## Convenções

- Código (tipos, funções, propriedades, nomes de arquivo) em inglês. Textos da interface (o que o usuário vê no app, mensagens de erro, saída do CLI, conteúdo da cápsula) continuam em português do Brasil.
- Sem comentários no código: nomes claros substituem a explicação. Só documente uma decisão não óbvia na descrição do commit ou do PR.
- Formatos persistidos (chaves de `config.json`/`tramas.json`, seções da cápsula, valores de estado gravados em disco) mantêm as strings originais em português por compatibilidade, mesmo com os símbolos Swift em inglês — veja os `CodingKeys` em `Engine/Workspace.swift`, `Engine/Status.swift` e as constantes de `TramaState`/`AgentState`/`FindingType` em `Engine/Workspace.swift`, `Engine/Agents.swift` e `Engine/Findings.swift`.
- Erros para o usuário: `throw TramaError("mensagem clara")`; exiba com `errorMessage(error)`.
- Escritas em `tramas.json` e na cápsula passam por `withLock` (flock) — nunca aninhe duas travas.
- O executável do app também é o comando `trama` (`CLI.shouldRunAsCLI` em `tramaApp.swift`); comandos novos vão em `Engine/CLICommands.swift`.
- Mudou comportamento do motor? Acrescente ou ajuste o teste em `tramaTests/tramaTests.swift`.

## Próximas funcionalidades

O backlog priorizado está em `ROADMAP.md`: cada item tem o problema, onde mexer e quando está pronto.
