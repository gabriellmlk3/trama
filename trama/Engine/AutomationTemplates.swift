import Foundation

public struct AutomationTemplate: Identifiable, Sendable {
    public var id: String
    public var stack: String
    public var automation: Automation

    public var title: String { automation.name }

    public func instantiate() -> Automation {
        var a = automation
        a.id = Automation.newID()
        return a
    }
}

extension AutomationTemplate {
    public static let all: [AutomationTemplate] = [
        AutomationTemplate(id: "caminhos-foco", stack: "Qualquer stack", automation: Automation(
            name: "Arquivos locais seguem a trama em foco", kind: .paths, scope: .primaries,
            files: [".env", "local.properties"])),
        AutomationTemplate(id: "flutter-foco", stack: "Flutter/Dart", automation: Automation(
            name: "pubspec_overrides.yaml segue a trama em foco", kind: .paths, scope: .primaries,
            files: ["pubspec_overrides.yaml"])),
        AutomationTemplate(id: "flutter-worktrees", stack: "Flutter/Dart", automation: Automation(
            name: "pubspec_overrides.yaml dos worktrees aponta para a trama", kind: .paths, scope: .worktrees,
            files: ["pubspec_overrides.yaml"])),
        AutomationTemplate(id: "flutter-pub-get", stack: "Flutter/Dart", automation: Automation(
            name: "flutter pub get ao focar", events: [.focus], scope: .primaries,
            command: "if [ -f .fvmrc ]; then fvm flutter pub get; else flutter pub get; fi")),
        AutomationTemplate(id: "node-install", stack: "Node", automation: Automation(
            name: "Instalar dependências ao criar", events: [.create], scope: .worktrees,
            command: "if [ -f pnpm-lock.yaml ]; then pnpm install; elif [ -f yarn.lock ]; then yarn install; elif [ -f package.json ]; then npm install; fi")),
        AutomationTemplate(id: "go-work", stack: "Go", automation: Automation(
            name: "go.work com os módulos da trama", events: [.create, .pull], scope: .trama,
            command: "[ -f go.work ] || go work init; for r in ${=TRAMA_REPOS}; do if [ -f \"$r/go.mod\" ]; then go work use \"./$r\"; fi; done")),
        AutomationTemplate(id: "pod-install", stack: "iOS", automation: Automation(
            name: "pod install ao criar", events: [.create], scope: .worktrees,
            command: "if [ -f Podfile ]; then pod install; fi")),
        AutomationTemplate(id: "docker-compose", stack: "Docker", automation: Automation(
            name: "Containers sobem ao focar e param ao sair", events: [.focus, .unfocus], scope: .worktrees,
            command: "if [ -f compose.yaml ] || [ -f docker-compose.yml ]; then if [ \"$TRAMA_EVENTO\" = focar ]; then docker compose up -d; else docker compose stop; fi; fi")),
    ]

    public static func find(_ key: String) throws -> AutomationTemplate {
        let k = key.trimmingCharacters(in: .whitespaces)
        if let n = Int(k), n >= 1, n <= all.count { return all[n - 1] }
        if let t = all.first(where: { $0.id == k }) { return t }
        throw TramaError("modelo “\(k)” não encontrado (veja `trama automacao modelos`)")
    }
}
