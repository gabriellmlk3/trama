import Foundation
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var model: AppModel
    @State private var hooksOn = Integration.areHooksInstalled()
    @State private var commandOn = Integration.isCommandInstalled()
    @State private var localError: String?
    @State private var defaultBranch = ""
    @AppStorage(ClaudeTarget.storageKey) private var claudeTarget = ClaudeTarget.cli.rawValue

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
                            Button("Remover") {
                                Task { await model.removeRepo(r.name) }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                            Text("apelido \(r.alias) · base \(r.base ?? "main")")
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
        .frame(width: 600, height: 620)
        .onAppear(perform: reload)
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
