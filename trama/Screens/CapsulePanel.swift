import Foundation
import SwiftUI

struct CapsulePanel: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama

    var capsule: TramaCapsule? {
        guard let c = model.capsule, c.trama == trama.slug else { return nil }
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CapsuleHeader(trama: trama, capsule: capsule)
                    if let c = capsule {
                        if c.exists {
                            GoalSection(capsule: c, trama: trama)
                            DecisionsSection(items: c.decisions)
                            HandoffsSection(items: c.handoffs, trama: trama)
                            PendingSection(items: c.pending, trama: trama)
                            JournalSection(items: c.journal)
                        } else {
                            Text("A cápsula ainda não existe. Ela é criada junto com a trama; se foi apagada, a próxima anotação cria uma nova.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.faded)
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Theme.iris)
                    .padding(.top, 1)
                Text("Todo agente desta trama recebe a cápsula ao abrir (hook de início de sessão) e registra decisões e handoffs com o comando `trama`.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
        .background(Theme.panel)
    }
}

struct CapsuleHeader: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let capsule: TramaCapsule?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Cápsula")
                    .font(.system(size: 13, weight: .semibold))
                if let c = capsule, c.exists {
                    HStack(spacing: 5) {
                        Dot(color: Theme.ok, size: 6)
                        Text("atualizada \(relativeTime(c.updatedAt))")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.okText)
                }
                Spacer()
                Button {
                    Terminal.openFile(capsule?.path ?? trama.capsule)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Abrir a cápsula no editor")
                .accessibilityLabel("Abrir a cápsula no editor")
                Color.clear.frame(width: 44, height: 28)
            }
            Text(Paths.abbreviate(capsule?.path ?? trama.capsule))
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.faded)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct GoalSection: View {
    @EnvironmentObject var model: AppModel
    let capsule: TramaCapsule
    let trama: LiveTrama
    @State private var editing = false
    @State private var text = ""
    @State private var achieved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(text: "Objetivo")
                Spacer()
                if !capsule.goal.isEmpty {
                    Button("Atingido") {
                        achieved = true
                        text = ""
                        editing = true
                    }
                    .buttonStyle(GhostButton(compact: true))
                    .help("Registra o objetivo como concluído e define o próximo")
                }
                Button(capsule.goal.isEmpty ? "Definir" : "Editar") {
                    achieved = false
                    text = capsule.goal
                    editing = true
                }
                .buttonStyle(GhostButton(compact: true))
            }
            if !capsule.goal.isEmpty {
                Text(capsule.goal)
                    .font(Theme.serif(20))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .onTapGesture(count: 2) {
                        achieved = false
                        text = capsule.goal
                        editing = true
                    }
            } else {
                Text("Sem objetivo definido.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
            }
        }
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 12) {
                Text(achieved ? "Próximo objetivo" : "Objetivo da trama")
                    .font(.system(size: 15, weight: .semibold))
                Text(achieved
                     ? "O objetivo atual será registrado no diário como atingido."
                     : "Os agentes leem o objetivo ao abrir uma sessão nesta trama.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .frame(minHeight: 110)
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
                HStack {
                    Spacer()
                    Button("Cancelar") { editing = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Salvar") {
                        let t = text
                        let previous = capsule.goal
                        let closing = achieved
                        editing = false
                        Task { await model.replaceGoal(t, previous: closing ? previous : nil, trama: trama.slug) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 440)
        }
    }
}

struct DecisionsSection: View {
    let items: [CapsuleItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Decisões · \(items.count)")
            if items.isEmpty {
                Text("Nenhuma ainda. Decisões que afetam mais de um repositório moram aqui.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
            }
            if items.count > 6 {
                Text("+ \(items.count - 6) anteriores na cápsula")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
            }
            ForEach(Array(items.suffix(6))) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        if let author = item.author {
                            AuthorChip(author: author)
                        }
                        Text(relativeTime(item.timestamp))
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
                }
            }
        }
    }
}

struct AuthorChip: View {
    let author: String

    var isAgent: Bool { author.hasPrefix("agente") }

    var body: some View {
        Text(author)
            .font(.system(size: 11.5))
            .foregroundStyle(isAgent ? Theme.irisText : Theme.text2)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(isAgent ? Theme.iris.opacity(0.12) : Theme.line))
    }
}

struct HandoffsSection: View {
    @EnvironmentObject var model: AppModel
    let items: [CapsuleItem]
    let trama: LiveTrama

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Handoffs")
            if items.isEmpty {
                Text("Quando um agente terminar algo que outro repositório precisa usar, o recado aparece aqui.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
            }
            ForEach(Array(items.suffix(5).reversed())) { item in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Text(item.from ?? "?")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.ember)
                        Text(item.to ?? "?")
                    }
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.text3)
                    Text(item.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    HStack {
                        Text([item.author, relativeTime(item.timestamp)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(Theme.faded)
                        Spacer()
                        if item.done {
                            Label("recebido", systemImage: "checkmark")
                                .foregroundStyle(Theme.okText)
                        } else {
                            Button("Marcar recebido") {
                                Task { await model.confirmHandoff(item.index, trama: trama.slug) }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.emberLight)
                        }
                    }
                    .font(.system(size: 11.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x262930), lineWidth: 1))
            }
        }
    }
}

struct PendingSection: View {
    @EnvironmentObject var model: AppModel
    let items: [CapsuleItem]
    let trama: LiveTrama

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Pendências")
            if items.isEmpty {
                Text("Nada pendente.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
            }
            ForEach(items) { item in
                Button {
                    if !item.done {
                        Task { await model.completePending(item.index, trama: trama.slug) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(item.done ? Theme.okText : Color(hex: 0x6B707A))
                        Text(item.text)
                            .font(.system(size: 13))
                            .foregroundStyle(item.done ? Theme.faded : Theme.text2)
                            .strikethrough(item.done, color: Theme.faded)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.done)
                .accessibilityLabel(item.done ? "\(item.text), feita" : "Marcar como feita: \(item.text)")
            }
        }
    }
}

struct JournalSection: View {
    let items: [CapsuleItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Diário")
                ForEach(Array(items.suffix(4).reversed())) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(relativeTime(item.timestamp))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.faded)
                            .frame(width: 70, alignment: .leading)
                        Text(item.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
