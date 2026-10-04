import SwiftUI

struct AgentWindow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let slug = model.agentDialog?.slug {
                TramaAgentDialog(slug: slug)
                    .id(model.agentDialogToken)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Theme.background)
        .onDisappear { model.agentDialog = nil }
    }
}

struct TramaAgentDialog: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let slug: String
    @State private var picking = true
    @State private var scope: String?
    @State private var key: String?
    @State private var past: [ClaudeConversation] = []
    @State private var draft = ""
    @State private var search = ""
    @State private var undo: [TrashedConversation] = []
    @State private var undoTitle = ""
    @State private var searching = false
    @FocusState private var focused: Bool
    @FocusState private var searchFocused: Bool

    private var shortcuts: some View {
        ZStack {
            Button("Nova conversa") { start(resume: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Buscar conversas") {
                picking = true
                searching = true
                DispatchQueue.main.async { searchFocused = true }
            }
            .keyboardShortcut("k", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var filteredPast: [ClaudeConversation] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? past : past.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    private var trama: LiveTrama? { model.state?.tramas.first { $0.slug == slug } }
    private var session: GeneralAgentSession? { model.tramaAgent(key: key) }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .background(shortcuts)
        .task(id: scope) { await loadPast() }
        .onAppear {
            scope = model.agentDialogRepo
            key = model.agentDialogKey
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
        VStack(spacing: 0) {
            pickerList
            if !undo.isEmpty { undoBar }
        }
    }

    private var undoBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(Theme.faded)
            Text("“\(undoTitle)” foi para a Lixeira")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
            Spacer()
            Button("Desfazer", action: restore)
                .buttonStyle(GhostButton(compact: true))
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Theme.surface2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .task(id: undo) {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            undo = []
        }
    }

    private var pickerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let trama, trama.repos.count > 1 { scopeChooser(trama) }
                row(icon: "plus", title: "Nova conversa", subtitle: "Começa do zero, sem contexto anterior · ⇧⌘N") {
                    start(resume: nil)
                }
                let live = model.liveAgents(slug, repo: scope)
                if !live.isEmpty {
                    sectionTitle("Em andamento")
                    ForEach(live, id: \.key) { entry in
                        row(icon: entry.session.running ? "ellipsis.bubble" : "bubble.left",
                            title: current(entry.session),
                            subtitle: ([entry.session.running ? "respondendo agora" : "aberta neste app"] + [entry.session.conversation.usageLabel].compactMap { $0 }).joined(separator: " · "),
                            trailingIcon: "xmark", trailingHelp: "Encerrar esta sessão",
                            onDelete: { close(entry.key) }) {
                            key = entry.key
                            model.rememberAgent(slug: slug, repo: scope, key: entry.key)
                            picking = false
                        }
                    }
                }
                if !past.isEmpty {
                    sectionTitle("Sessões anteriores")
                    if past.count > 5 || searching { searchField }
                    ForEach(filteredPast) { conversation in
                        row(icon: "clock.arrow.circlepath", title: conversation.title,
                            subtitle: "\(scope ?? "raiz da trama") · \(conversation.modifiedAt.formatted(.relative(presentation: .named)))",
                            onDelete: { delete(conversation) }) {
                            start(resume: conversation.id)
                        }
                    }
                    if filteredPast.isEmpty {
                        Text("Nenhuma conversa com “\(search)”.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faded)
                    }
                }
            }
            .padding(18)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
            TextField("Buscar nas conversas · ⌘K", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
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
            key = nil
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
        let first = session.conversation.items.first { $0.kind == .user }?.text ?? "Nova conversa"
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

    private func row(icon: String, title: String, subtitle: String, trailingIcon: String = "trash", trailingHelp: String = "Apagar esta sessão (vai para a Lixeira)", onDelete: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .trailing) {
            rowButton(icon: icon, title: title, subtitle: subtitle, action: action)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(trailingHelp)
                .padding(.trailing, 8)
            }
        }
    }

    private func rowButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
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
        let started = model.startTramaAgent(trama, repo: scope, resume: resume)
        key = started.key
        picking = false
    }

    private func close(_ closing: String) {
        model.closeTramaAgent(key: closing)
        if key == closing { key = nil }
    }

    private func delete(_ conversation: ClaudeConversation) {
        guard let path = scopePath else { return }
        let id = conversation.id
        let title = conversation.title
        Task {
            let trashed = await Task.detached { ClaudeSessions.trash(id: id, at: path) }.value
            if !trashed.isEmpty {
                undoTitle = title.count > 40 ? String(title.prefix(40)) + "…" : title
                undo = trashed
            }
            await loadPast()
        }
    }

    private func restore() {
        let items = undo
        undo = []
        Task {
            _ = await Task.detached { ClaudeSessions.restore(items) }.value
            await loadPast()
        }
    }

    private func loadPast() async {
        guard let path = scopePath else { return }
        search = ""
        past = await Task.detached { ClaudeSessions.conversations(at: path, limit: 50) }.value
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
            AgentStatusLine(session: session)
                .padding(.horizontal, 18)
                .padding(.top, 6)
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
