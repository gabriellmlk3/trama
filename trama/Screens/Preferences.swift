import Foundation
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    @State private var hooksOn = Integration.areHooksInstalled()
    @State private var commandOn = Integration.isCommandInstalled()
    @State private var localError: String?
    @State private var defaultBranch = ""
    @AppStorage(ClaudeTarget.storageKey) private var claudeTarget = ClaudeTarget.cli.rawValue
    @State private var editingRecipe: RepoConfig?
    @AppStorage(NotificationPreference.waiting) private var notifyWaiting = true
    @AppStorage(NotificationPreference.done) private var notifyDone = true

    var body: some View {
        Form {
            Section {
                Picker("Abrir o Claude em", selection: $claudeTarget) {
                    ForEach(ClaudeTarget.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Vale para “Abrir no Claude”, “Revisar” e para abrir agentes ao criar uma trama.")
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
                Text("Os hooks entregam a cápsula a cada sessão aberta dentro de uma trama e mostram aqui o que cada agente está fazendo. Fora das tramas eles não fazem nada.")
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
                            Text("apelido \(r.alias) · base \(r.base ?? "main")" + (r.recipe.isEmpty && r.services.isEmpty ? "" : " · preparo configurado"))
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
                Text("Ordem de merge dos PRs")
                    .font(.subheadline)
                TextField("0", text: $mergeRank)
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                Text("menor primeiro (ex.: API 0, clientes 1)")
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
                    Task {
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
