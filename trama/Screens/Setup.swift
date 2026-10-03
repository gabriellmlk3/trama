import Foundation
import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var context = ""
    @State private var repos: [String] = []
    @State private var installHooks = true
    @State private var installCommand = true
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                TramaLogo(size: 34)
                Text("trama")
                    .font(Theme.serif(34).italic())
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Vamos tecer.")
                    .font(Theme.serif(44))
                Text("Três passos e você nunca mais troca de branch à mão. As tramas ficam em ~/Tramas; nada nos seus repositórios muda além de branches e worktrees novos.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Step(number: 1, title: "Repositório de contexto", detail: "Onde as cápsulas das tramas ficam versionadas (ex.: rebocs-context). Opcional: sem ele, cada cápsula fica na pasta da trama.") {
                HStack(spacing: 10) {
                    Text(context.isEmpty ? "nenhum" : Paths.abbreviate(context))
                        .font(Theme.mono(12))
                        .foregroundStyle(context.isEmpty ? Theme.faded : Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Escolher…") {
                        if let p = Terminal.choosePaths(multiple: false, title: "Escolha o repositório de contexto").first {
                            context = p
                        }
                    }
                    .buttonStyle(GhostButton(compact: true))
                }
            }

            Step(number: 2, title: "Repositórios das tramas", detail: "Os repositórios que podem entrar em tramas. Dá para escolher vários de uma vez.") {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(repos, id: \.self) { r in
                                HStack {
                                    Text(URL(fileURLWithPath: r).lastPathComponent)
                                        .font(Theme.mono(12.5))
                                    Text(Paths.abbreviate(r))
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.faded)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        repos.removeAll { $0 == r }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.faded)
                                    .accessibilityLabel("Remover \(r)")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .fixedSize(horizontal: false, vertical: repos.count <= 7)
                    Button("Adicionar repositórios…") {
                        for p in Terminal.choosePaths(multiple: true, title: "Escolha os repositórios") where !repos.contains(p) && p != context {
                            repos.append(p)
                        }
                    }
                    .buttonStyle(GhostButton(compact: true))
                }
            }

            Step(number: 3, title: "Integração com o Claude Code", detail: "Instala hooks em ~/.claude/settings.json (com cópia do original): cada sessão dentro de uma trama recebe a cápsula e aparece aqui com seu status.") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $installHooks) {
                        Text("Instalar os hooks do Trama")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                    }
                    Toggle(isOn: $installCommand) {
                        Text("Deixar o comando `trama` no Terminal (~/.local/bin)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.ember)
            }

            HStack {
                Spacer()
                Button {
                    start()
                } label: {
                    HStack(spacing: 10) {
                        if sending { ProgressView().controlSize(.small) }
                        Text("Começar")
                    }
                }
                .buttonStyle(EmberButton())
                .keyboardShortcut(.defaultAction)
                .disabled(sending)
            }
        }
        .padding(40)
        .frame(width: 680)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x111217)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line2, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func start() {
        sending = true
        let c = context
        let r = repos
        let h = installHooks
        let cmd = installCommand
        Task {
            _ = await model.setup(context: c.isEmpty ? nil : c, repos: r, hooks: h, command: cmd)
            sending = false
        }
    }
}

struct Step<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(Theme.serif(22))
                .foregroundStyle(Theme.ember)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.faded)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
        }
    }
}
