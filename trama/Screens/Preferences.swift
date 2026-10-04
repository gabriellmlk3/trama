import Foundation
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    @State private var hooksOn = Integration.areHooksInstalled()
    @State private var commandOn = Integration.isCommandInstalled()
    @State private var localError: String?
    @State private var defaultBranch = ""
    @State private var pullPolicy = AgentPullPolicy.free
    @AppStorage(ClaudeTarget.storageKey) private var claudeTarget = ClaudeTarget.docked.rawValue
    @AppStorage(AgentScope.storageKey) private var agentScope = AgentScope.single.rawValue
    @State private var editingRecipe: RepoConfig?
    @State private var toolVersions: [String: String?] = [:]
    @State private var credentials = GitCredentials.all()
    @State private var credentialKind = ProviderKind.github
    @State private var credentialHost = ProviderKind.github.defaultHost
    @State private var credentialUser = ""
    @State private var credentialOrganization = ""
    @State private var credentialToken = ""
    @State private var credentialBusy = false
    @State private var credentialMessage: String?
    @AppStorage(NotificationPreference.waiting) private var notifyWaiting = true
    @AppStorage(NotificationPreference.done) private var notifyDone = true

    var body: some View {
        Form {
            Section {
                Picker("Abrir o Claude em", selection: $claudeTarget) {
                    ForEach(ClaudeTarget.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Picker("Ao abrir uma trama", selection: $agentScope) {
                    ForEach(AgentScope.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Agent acoplado abre uma janela no app, com a conversa e a lista de sessões da trama (sempre um agent na raiz dela, com todos os repositórios). Console embutido e Claude Desktop abrem o Claude Code como antes; neles, “Ao abrir uma trama” define um agent para a trama (raiz, com todos os repositórios; no Desktop, só a pasta da trama) ou um por repositório. Vale para “Abrir agent”, “Revisar” e para abrir agentes ao criar uma trama.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Hooks do Claude Code") {
                    HStack(spacing: 10) {
                        OnIndicator(on: hooksOn, text: hooksOn ? "instalados" : "desligados")
                        Button(hooksOn ? "Remover" : "Instalar") { toggleHooks() }
                    }
                }
                LabeledContent("Comando no Terminal") {
                    HStack(spacing: 10) {
                        OnIndicator(on: commandOn, text: commandOn ? "~/.local/bin/trama" : "não instalado")
                        if !commandOn {
                            Button("Instalar") { installCommand() }
                        }
                    }
                }
                if let localError {
                    Text(localError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Integração")
            } footer: {
                Text("Os hooks entregam a cápsula a cada sessão aberta dentro de uma trama e mostram aqui o que cada agente está fazendo. Fora das tramas eles não fazem nada. Junto vai a skill “trama” em ~/.claude/skills, que ensina qualquer agente a criar e gerenciar tramas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ToolInstaller.all) { tool in
                    LabeledContent("\(tool.title) (\(tool.id))") {
                        HStack(spacing: 10) {
                            if let loaded = toolVersions[tool.id] {
                                OnIndicator(on: loaded != nil, text: loaded ?? "não instalado")
                                if loaded == nil {
                                    Button("Instalar") {
                                        model.terminals.open(path: NSHomeDirectory(), command: tool.installCommand, title: "instalar \(tool.id)")
                                    }
                                    .help(tool.purpose)
                                }
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button("Instalar as que faltam") {
                        let missing = ToolInstaller.missing()
                        guard !missing.isEmpty else { return }
                        model.terminals.open(path: NSHomeDirectory(), command: missing.map(\.installCommand).joined(separator: " && "), title: "instalar ferramentas")
                    }
                    .disabled(toolVersions.values.allSatisfy { $0 != nil })
                    Button("Atualizar") { refreshTools() }
                }
            } header: {
                Text("Ferramentas")
            } footer: {
                Text("As CLIs dos provedores são instaladas pelo Homebrew (que também é instalado se faltar) no terminal do Trama. Depois, entre na conta em Contas Git. A lista se atualiza quando você volta ao app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .task { refreshTools() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshTools() }

            Section {
                ForEach(credentials) { c in
                    LabeledContent("\(c.kind.title) · \(c.host)") {
                        HStack(spacing: 10) {
                            OnIndicator(on: true, text: c.username ?? "token no Keychain")
                            Button("Remover") {
                                GitCredentials.remove(host: c.host)
                                credentials = GitCredentials.all()
                            }
                        }
                    }
                }
                Picker("Provedor", selection: $credentialKind) {
                    ForEach(ProviderKind.withCredentials, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: credentialKind) { _, kind in
                    credentialHost = kind.defaultHost
                    credentialMessage = nil
                }
                TextField("Servidor", text: $credentialHost)
                    .textFieldStyle(.roundedBorder)
                    .disabled(credentialKind == .azure)
                if credentialKind.needsUsername {
                    TextField("Usuário", text: $credentialUser)
                        .textFieldStyle(.roundedBorder)
                }
                if credentialKind == .azure {
                    TextField("Organização (opcional, para validar o token)", text: $credentialOrganization)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 10) {
                    SecureField(credentialKind.tokenHint, text: $credentialToken)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveCredential)
                    Button("Salvar") { saveCredential() }
                        .disabled(!canSaveCredential)
                }
                HStack(spacing: 10) {
                    Button("Criar token") {
                        if let url = credentialKind.tokenPage(host: credentialHost, organization: credentialOrganization) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    if let command = credentialKind.loginCommand(host: credentialHost), let cli = credentialKind.cliName {
                        Button("Instalar \(cli) e entrar") {
                            model.terminals.open(path: NSHomeDirectory(), command: command, title: "\(cli) · login")
                        }
                        .help("Instala a CLI com o Homebrew (se faltar) e abre o login no terminal do Trama")
                    }
                }
                if let credentialMessage {
                    Text(credentialMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Contas Git")
            } footer: {
                Text("O token fica no Keychain e é usado nos pushes por HTTPS e nos comandos da CLI do provedor (gh, glab, az). Para GitHub Enterprise ou GitLab próprio, troque o servidor. O login pela CLI serve para entrar pelo navegador; os pushes do Trama usam o token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Agente esperando aprovação", isOn: $notifyWaiting)
                Toggle("Agente concluiu", isOn: $notifyDone)
            } header: {
                Text("Notificações")
            } footer: {
                Text("Aparecem com o app em segundo plano. O número de agentes esperando fica no ícone da barra de menus e no Dock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pastas") {
                LabeledContent("Tramas") {
                    Text(Paths.abbreviate(model.state?.root ?? Workspace.defaultRoot()))
                        .textSelection(.enabled)
                }
                LabeledContent("Repositório de contexto") {
                    HStack(spacing: 10) {
                        Text(model.state?.context.map { Paths.abbreviate($0) } ?? "nenhum")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Escolher…") {
                            if let folder = Terminal.choosePaths(multiple: false, title: "Escolha o repositório de contexto").first {
                                Task { await model.setContext(folder) }
                            }
                        }
                    }
                }
            }

            Section {
                LabeledContent("Branch padrão") {
                    HStack(spacing: 10) {
                        TextField("main", text: $defaultBranch)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160)
                            .onSubmit(saveDefaultBranch)
                        Button("Salvar") { saveDefaultBranch() }
                            .disabled(defaultBranch.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } footer: {
                Text("Usada para novas tramas e repositórios quando nenhuma base específica é escolhida.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Agentes puxam repositórios", selection: $pullPolicy) {
                    Text("Sozinhos").tag(AgentPullPolicy.free)
                    Text("Só com a minha aprovação").tag(AgentPullPolicy.approval)
                }
                .onChange(of: pullPolicy) { _, new in
                    guard (try? Workspace.open())?.config.agentPullPolicy != new else { return }
                    Task { await model.setAgentPullPolicy(new) }
                }
            } footer: {
                Text("Quando um agente precisa de outro repositório, ele puxa para a trama ou sugere. Com aprovação, `trama puxar` e `trama repo add` feitos por um agente viram uma sugestão na cápsula, e você decide ali.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Repositórios") {
                ForEach(model.repos) { r in
                    LabeledContent {
                        HStack(spacing: 10) {
                            Text(Paths.abbreviate(r.path))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Preparo…") { editingRecipe = r }
                                .help("Arquivos a copiar e comandos a rodar em cada worktree novo")
                            Button("Remover") {
                                Task { await model.removeRepo(r.name) }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                            Text("apelido \(r.alias) · base \(r.base ?? "main")" + (r.provider.map { " · \($0.title)" } ?? "") + (r.recipe.isEmpty && r.services.isEmpty ? "" : " · preparo configurado"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Adicionar repositórios…") {
                    let folders = Terminal.choosePaths(multiple: true, title: "Escolha os repositórios que podem entrar em tramas")
                    Task { await model.addRepos(folders) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 700)
        .onAppear(perform: reload)
        .sheet(item: $editingRecipe) { r in
            RecipeEditor(repo: r)
        }
    }

    func reload() {
        hooksOn = Integration.areHooksInstalled()
        commandOn = Integration.isCommandInstalled()
        defaultBranch = model.state?.repos.first?.base ?? "main"
        if let w = try? Workspace.open() {
            defaultBranch = w.config.defaultBranch
            pullPolicy = w.config.agentPullPolicy
        }
    }

    func toggleHooks() {
        do {
            if hooksOn {
                try Integration.removeHooks()
            } else {
                try Integration.installHooks()
            }
            localError = nil
        } catch {
            localError = errorMessage(error)
        }
        reload()
    }

    func installCommand() {
        do {
            try Integration.installCommand()
            localError = nil
        } catch {
            localError = errorMessage(error)
        }
        reload()
    }

    func refreshTools() {
        Task.detached {
            let result = ToolInstaller.all.map { ($0.id, $0.version) }
            await MainActor.run {
                toolVersions = Dictionary(uniqueKeysWithValues: result.map { ($0.0, $0.1) })
            }
        }
    }

    var canSaveCredential: Bool {
        !credentialBusy
            && !credentialToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !credentialHost.trimmingCharacters(in: .whitespaces).isEmpty
            && (!credentialKind.needsUsername || !credentialUser.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func saveCredential() {
        guard canSaveCredential else { return }
        var host = credentialHost.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        host = host.split(separator: "/").first.map(String.init) ?? host
        var credential = GitCredential(
            kind: credentialKind,
            host: host,
            username: credentialKind.needsUsername ? credentialUser.trimmingCharacters(in: .whitespaces) : nil,
            token: credentialToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let organization = credentialOrganization
        credentialBusy = true
        credentialMessage = nil
        Task {
            do {
                let account = try await GitCredentials.validate(credential, organization: organization)
                if credential.username == nil { credential.username = account.map { "@\($0)" } }
                try GitCredentials.save(credential)
                credentials = GitCredentials.all()
                credentialToken = ""
                if account == nil { credentialMessage = "Token guardado, mas não consegui conferi-lo." }
            } catch {
                credentialMessage = error.localizedDescription
            }
            credentialBusy = false
        }
    }

    func saveDefaultBranch() {
        let b = defaultBranch.trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty else { return }
        Task {
            await model.setDefaultBranch(b)
            reload()
        }
    }
}

private struct OnIndicator: View {
    let on: Bool
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? Theme.ok : Theme.faded)
                .frame(width: 7, height: 7)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}


private struct RecipeEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let repo: RepoConfig
    @State private var copy = ""
    @State private var run = ""
    @State private var services = ""
    @State private var mergeRank = "0"
    @State private var editor = ""
    @State private var provider = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preparo de \(repo.name)")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Copiar da cópia principal")
                    .font(.subheadline)
                TextEditor(text: $copy)
                    .font(Theme.mono(12))
                    .frame(height: 70)
                    .border(Color.secondary.opacity(0.3))
                Text("Um padrão por linha, relativo ao repositório. Ex.: .env*, local.properties")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Rodar no worktree")
                    .font(.subheadline)
                TextEditor(text: $run)
                    .font(Theme.mono(12))
                    .frame(height: 70)
                    .border(Color.secondary.opacity(0.3))
                Text("Um comando por linha, em ordem; para no primeiro que falhar. Ex.: npm ci")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Serviços de desenvolvimento")
                    .font(.subheadline)
                TextEditor(text: $services)
                    .font(Theme.mono(12))
                    .frame(height: 70)
                    .border(Color.secondary.opacity(0.3))
                Text("Um por linha: nome porta comando. Ex.: api 3000 npm run dev. Cada trama sobe na porta + 10 × seu índice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("Editor")
                    .font(.subheadline)
                TextField("automático", text: $editor)
                    .frame(width: 160)
                Text("nome do app, ex.: Xcode, Cursor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("Ordem de merge dos PRs")
                    .font(.subheadline)
                TextField("0", text: $mergeRank)
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                Text("menor primeiro (ex.: API 0, clientes 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Provedor dos PRs")
                        .font(.subheadline)
                    Picker("", selection: $provider) {
                        Text("Automático (pelo remoto)").tag("")
                        ForEach(ProviderKind.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                Text("GitHub usa o gh, Azure DevOps o az e GitLab o glab. Nos outros, a branch sobe e o PR abre pelo link, no navegador.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") {
                    let c = lines(copy)
                    let r = lines(run)
                    let parsed = parseServices(services)
                    let rank = Int(mergeRank.trimmingCharacters(in: .whitespaces)) ?? 0
                    let app = editor
                    let kind = ProviderKind(rawValue: provider)
                    Task {
                        await model.setProvider(repo.name, kind)
                        await model.setEditor(repo.name, app)
                        await model.setMergeRank(repo.name, rank)
                        await model.setRecipe(repo.name, copy: c, run: r)
                        await model.setServices(repo.name, parsed)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            copy = repo.copy.joined(separator: "\n")
            run = repo.run.joined(separator: "\n")
            mergeRank = String(repo.mergeRank)
            editor = repo.editor ?? ""
            provider = repo.provider?.rawValue ?? ""
            services = repo.services.map { "\($0.name) \($0.port) \($0.command)" }.joined(separator: "\n")
        }
    }

    func parseServices(_ text: String) -> [ServiceConfig] {
        lines(text).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 3, let port = Int(parts[1]) else { return ServiceConfig(name: line, command: "", port: 0) }
            return ServiceConfig(name: parts[0], command: parts[2], port: port)
        }
    }

    func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
