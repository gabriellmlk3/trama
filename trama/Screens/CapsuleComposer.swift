import Foundation
import SwiftUI

struct CapsuleComposer: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    @State private var text = ""
    @State private var kind = NoteType.decision

    enum NoteType: String, CaseIterable, Identifiable {
        case decision = "Decisão"
        case pending = "Pendência"
        case note = "Nota no diário"
        var id: String { rawValue }

        var noteKind: AppModel.NoteKind {
            switch self {
            case .decision: return .decision
            case .pending: return .pending
            case .note: return .note
            }
        }
    }

    var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .foregroundStyle(Theme.iris)
            AppPicker(selection: $kind, options: NoteType.allCases.map { ($0.rawValue, $0) }, width: 170)
            TextField("Escreva na cápsula · os agentes leem ao começar", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.emberDark)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(empty ? Theme.ember.opacity(0.4) : Theme.ember))
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .accessibilityLabel("Registrar na cápsula")
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x262930), lineWidth: 1))
    }

    func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let noteKind = kind.noteKind
        let slug = trama.slug
        text = ""
        Task { await model.annotate(noteKind, t, trama: slug) }
    }
}


struct ClaudeMenu: View {
    @EnvironmentObject var model: AppModel
    let path: String
    let repo: String
    @State private var conversations: [ClaudeConversation] = []

    var body: some View {
        AppMenu(width: 320, primaryAction: { open(.latest) }) {
            Image(systemName: "sparkle")
        } content: {
            MenuAction("Nova conversa") { open(.fresh) }
            if !conversations.isEmpty {
                MenuDivider()
                MenuSection("Retomar")
                conversations.map { conversation in
                    MenuAction("\(conversation.title) · \(conversation.modifiedAt.formatted(.relative(presentation: .named)))") {
                        open(.conversation(conversation.id))
                    }
                }
            }
        }
        .buttonStyle(IconButton())
        .help(conversations.isEmpty ? "Abrir o Claude Code em \(repo)" : "Continuar a última conversa do Claude Code em \(repo) · segure para escolher outra ou começar uma nova")
        .accessibilityLabel("Abrir o Claude Code em \(repo)")
        .task(id: model.terminals.sessions.count) {
            let target = path
            conversations = await Task.detached { ClaudeSessions.conversations(at: target) }.value
        }
    }

    private func open(_ resume: ClaudeResume) {
        model.openClaude(path: path, title: "\(repo) · claude", resume: resume)
    }
}
