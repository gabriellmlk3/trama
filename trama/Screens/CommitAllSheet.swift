import SwiftUI

struct CommitAllSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let trama: LiveTrama
    @State private var messages: [String: String] = [:]
    @State private var generating: Set<String> = []

    var dirty: [RepoStatus] {
        trama.status.filter { $0.exists && $0.changed > 0 && $0.conflict == nil }
    }

    var ready: [String: String] {
        messages.compactMapValues { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.filter { key, _ in dirty.contains(where: { $0.repo == key }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Commitar todos os repositórios")
                    .font(.system(size: 17, weight: .semibold))
                Text("Cada repositório leva todas as suas mudanças, com a mensagem escrita abaixo. Repositórios sem mensagem ficam de fora.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
            }
            if dirty.isEmpty {
                Text("Nenhum repositório com mudanças para commitar.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faded)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(dirty) { status in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(status.repo)
                                        .font(Theme.mono(12.5))
                                    Spacer()
                                    generateButton(status.repo)
                                    Text("\(status.changed) \(plural(status.changed, "alterado", "alterados"))")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.faded)
                                }
                                TextField("Mensagem do commit", text: binding(status.repo), axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5))
                                    .lineLimit(1...4)
                                    .padding(9)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            HStack {
                Button {
                    for status in dirty where (messages[status.repo] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        generate(status.repo)
                    }
                } label: {
                    Label("Gerar mensagens", systemImage: "sparkles")
                }
                .buttonStyle(GhostButton(compact: true))
                .disabled(dirty.isEmpty || !generating.isEmpty)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(GhostButton(compact: true))
                Button {
                    let batch = ready
                    Task {
                        if await model.commitAll(trama.slug, messages: batch) { dismiss() }
                    }
                } label: {
                    Text("Commitar \(ready.count) \(plural(ready.count, "repositório", "repositórios"))")
                }
                .buttonStyle(EmberButton(compact: true))
                .disabled(model.busy || ready.isEmpty)
                .opacity(model.busy || ready.isEmpty ? 0.45 : 1)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    func generateButton(_ repo: String) -> some View {
        Button {
            generate(repo)
        } label: {
            if generating.contains(repo) {
                ProgressView().controlSize(.mini)
            } else {
                Label("Gerar", systemImage: "sparkles")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.text3)
        .disabled(generating.contains(repo))
        .help("Gerar a mensagem com o Claude")
    }

    func generate(_ repo: String) {
        guard !generating.contains(repo) else { return }
        generating.insert(repo)
        Task {
            if let message = await model.suggestCommitMessage(trama.slug, repo: repo) {
                messages[repo] = message
            }
            generating.remove(repo)
        }
    }

    func binding(_ repo: String) -> Binding<String> {
        Binding(get: { messages[repo] ?? "" }, set: { messages[repo] = $0 })
    }
}
