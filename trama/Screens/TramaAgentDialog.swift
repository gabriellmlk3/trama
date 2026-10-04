import SwiftUI

struct TramaAgentDialog: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let slug: String
    @State private var picking = true
    @State private var scope: String?
    @State private var past: [ClaudeConversation] = []
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var trama: LiveTrama? { model.state?.tramas.first { $0.slug == slug } }
    private var session: GeneralAgentSession? { model.tramaAgent(for: slug, repo: scope) }
    private var scopePath: String? { trama.map { model.agentPath($0, repo: scope) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            if picking || session == nil {
                picker
            } else if let session {
                chat(session)
            }
        }
        .frame(width: 760, height: 640)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .task(id: scope) { await loadPast() }
        .onAppear {
            scope = model.agentDialogRepo
            picking = !model.agentDialogDirect
            model.agentDialogDirect = false
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .foregroundStyle(Theme.ember)
            VStack(alignment: .leading, spacing: 1) {
                Text(trama?.title ?? slug)
                    .font(.system(size: 14, weight: .medium))
                Text(scope.map { "Agent de \($0) · só o worktree deste repositório" } ?? "Agent da trama · raiz com todos os repositórios")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
            }
            Spacer()
            if session != nil, !picking {
                Button("Sessões") { picking = true }
                    .buttonStyle(GhostButton(compact: true))
            }
            if let trama {
                Button("Abrir no console") {
                    let id = picking ? nil : session?.conversation.sessionID
                    model.openTramaInConsole(trama, repo: scope, resume: id.map(ClaudeResume.conversation) ?? .fresh)
                    dismiss()
                }
                .buttonStyle(GhostButton(compact: true))
                .help("Abre o Claude Code no terminal embutido, com permissões interativas")
            }
            Button("Fechar") { dismiss() }
                .buttonStyle(GhostButton(compact: true))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let trama, trama.repos.count > 1 { scopeChooser(trama) }
                row(icon: "plus", title: "Nova conversa", subtitle: "Começa do zero, sem contexto anterior") {
                    start(resume: nil)
                }
                if let session, !session.conversation.items.isEmpty {
                    sectionTitle("Em andamento")
                    row(icon: session.running ? "ellipsis.bubble" : "bubble.left",
                        title: current(session),
                        subtitle: session.running ? "respondendo agora" : "aberta neste app") {
                        model.rememberAgent(slug: slug, repo: scope)
                        picking = false
                    }
                }
                if !past.isEmpty {
                    sectionTitle("Sessões anteriores")
                    ForEach(past) { conversation in
                        row(icon: "clock.arrow.circlepath", title: conversation.title,
                            subtitle: conversation.modifiedAt.formatted(.relative(presentation: .named))) {
                            start(resume: conversation.id)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func scopeChooser(_ trama: LiveTrama) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Agent de")
            HStack(spacing: 6) {
                scopeButton(title: "Trama inteira", repo: nil, busy: model.isAgentBusy(slug))
                ForEach(trama.repos, id: \.self) { repo in
                    scopeButton(title: repo, repo: repo, busy: model.isAgentBusy(slug, repo: repo))
                }
            }
        }
    }

    private func scopeButton(title: String, repo: String?, busy: Bool) -> some View {
        let selected = scope == repo
        return Button {
            scope = repo
        } label: {
            HStack(spacing: 5) {
                Text(title)
                if busy { Dot(color: Theme.iris, halo: true) }
            }
            .font(.system(size: 12, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Theme.text : Theme.text3)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(selected ? Theme.surface2 : Theme.surface))
            .overlay(Capsule().stroke(selected ? Theme.ember.opacity(0.6) : Theme.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func current(_ session: GeneralAgentSession) -> String {
        let first = session.conversation.items.first { $0.kind == .user }?.text ?? "Conversa atual"
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        return line.count > 70 ? String(line.prefix(70)) + "…" : line
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.mono(10.5))
            .tracking(1.2)
            .foregroundStyle(Theme.faded)
            .padding(.top, 10)
    }

    private func row(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.emberText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line2, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func chat(_ session: GeneralAgentSession) -> some View {
        ChatBody(session: session, draft: $draft, focused: $focused)
            .onAppear { focused = true }
    }

    private func start(resume: String?) {
        guard let trama else { return }
        model.startTramaAgent(trama, repo: scope, resume: resume)
        picking = false
    }

    private func loadPast() async {
        guard let path = scopePath else { return }
        past = await Task.detached { ClaudeSessions.conversations(at: path, limit: 20) }.value
    }
}

private struct ChatBody: View {
    @ObservedObject var session: GeneralAgentSession
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            if session.conversation.items.isEmpty {
                Text("Peça algo para esta trama: ler a cápsula, revisar as mudanças, registrar uma decisão…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faded)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AgentConversationList(session: session)
            }
            AgentInputBar(draft: $draft, running: session.running, focused: focused, attachmentsDir: session.attachmentsDir, onSend: send, onStop: { session.stop() }, onReset: nil)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
    }

    private func send(_ attachments: [AgentAttachment]) {
        let text = draft
        draft = ""
        session.send(text, attachments: attachments)
    }
}
