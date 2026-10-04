import SwiftUI

struct GeneralAgentView<Hero: View>: View {
    @ObservedObject var session: GeneralAgentSession
    @ViewBuilder var hero: () -> Hero
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var items: [AgentItem] { session.conversation.items }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                hero()
                inputBar
                    .frame(maxWidth: 640)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { focused = true }
        } else {
            VStack(spacing: 0) {
                AgentConversationList(session: session)
                inputBar
                    .frame(maxWidth: 820)
                    .padding(.vertical, 14)
            }
            .onAppear { focused = true }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            AgentStatusLine(session: session)
            AgentInputBar(draft: $draft, running: session.running, focused: $focused, attachmentsDir: session.attachmentsDir, onSend: send, onStop: { session.stop() }, onReset: items.isEmpty ? nil : { session.reset() })
        }
    }

    private func send(_ attachments: [AgentAttachment]) {
        let text = draft
        draft = ""
        session.send(text, attachments: attachments)
    }
}

struct AgentConversationList: View {
    @ObservedObject var session: GeneralAgentSession
    @State private var scrollPending = false

    private var items: [AgentItem] { session.conversation.items }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(rows) { row in
                        switch row {
                        case .item(let item):
                            AgentItemRow(item: item)
                        case .tools(let tools):
                            AgentToolGroup(tools: tools)
                        }
                    }
                    if session.running { AgentWorking() }
                    if !session.running {
                        ForEach(session.pendingPermissions, id: \.self) { denial in
                            AgentPermissionCard(
                                denial: denial,
                                onAllow: { session.allow(denial, forSession: $0) },
                                onAlways: session.canRemember ? { session.allowAlways(denial) } : nil,
                                onDeny: { session.deny(denial) }
                            )
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 40)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: scrollSignature) { _, _ in scheduleScroll(proxy) }
            .onChange(of: session.pendingPermissions) { _, _ in scheduleScroll(proxy) }
        }
    }

    private var rows: [AgentChatRow] { AgentChatRow.group(items) }

    private var scrollSignature: Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        hasher.combine(items.last?.id)
        hasher.combine(items.last?.text.count)
        return hasher.finalize()
    }

    private func scheduleScroll(_ proxy: ScrollViewProxy) {
        guard !scrollPending else { return }
        scrollPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollPending = false
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

private struct AgentPermissionCard: View {
    let denial: AgentDenial
    let onAllow: (_ forSession: Bool) -> Void
    let onAlways: (() -> Void)?
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("O agent pediu permissão", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.waitText)
            Text(denial.summary)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.text3)
                .lineLimit(3)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if let directory = denial.directory {
                    Button("Liberar a pasta \(Paths.name(directory))") { onAllow(true) }
                        .buttonStyle(ToneButton(color: Theme.wait, text: Theme.waitText))
                        .help("Dá acesso a \(directory) até o fim desta sessão")
                } else {
                    Button("Permitir uma vez") { onAllow(false) }
                        .buttonStyle(ToneButton(color: Theme.wait, text: Theme.waitText))
                    if let rule = denial.sessionRule {
                        Button("Nesta sessão") { onAllow(true) }
                            .buttonStyle(GhostButton(compact: true))
                            .help("Libera \(rule) até o fim desta sessão")
                    }
                }
                if let onAlways {
                    Button("Sempre nesta trama", action: onAlways)
                        .buttonStyle(GhostButton(compact: true))
                        .help(denial.directory.map { "Libera \($0) em todas as sessões desta trama · revogue em Ajustes" } ?? "Libera \(denial.onceRule ?? denial.tool) em todas as sessões desta trama · revogue em Ajustes")
                }
                Button("Negar", action: onDeny)
                    .buttonStyle(GhostButton(compact: true))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.wait.opacity(0.45), lineWidth: 1))
    }
}

private struct AgentWorking: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("trabalhando…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
        }
    }
}

struct AgentStatusLine: View {
    @ObservedObject var session: GeneralAgentSession

    var body: some View {
        let fraction = session.conversation.contextFraction
        HStack(spacing: 8) {
            Menu {
                ForEach(AgentModel.all) { option in
                    Button {
                        session.model = option
                    } label: {
                        if option == session.model {
                            Label("\(option.label) · \(option.detail)", systemImage: "checkmark")
                        } else {
                            Text("\(option.label) · \(option.detail)")
                        }
                    }
                }
            } label: {
                Label(session.model.label, systemImage: "cpu")
                    .font(Theme.mono(10.5))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Modelo desta conversa. A troca vale a partir da próxima mensagem.")
            Spacer()
            if let usage = session.conversation.usageLabel {
                Text(usage)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(fraction > 0.8 ? Theme.waitText : Theme.faded)
                ZStack {
                    Circle().stroke(Theme.line2, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(fraction > 0.8 ? Theme.wait : Theme.ember, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                .help("Quanto da janela de contexto a conversa já ocupa. Perto de 100% o Claude compacta o histórico.")
                if fraction > 0.6 {
                    Button("Compactar") { session.compact() }
                        .buttonStyle(.plain)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(fraction > 0.8 ? Theme.waitText : Theme.text3)
                        .disabled(!session.canCompact)
                        .help("Resume o histórico para liberar a janela de contexto (/compact)")
                }
            }
        }
        .foregroundStyle(Theme.faded)
    }
}

struct AgentInputBar: View {
    @Binding var draft: String
    let running: Bool
    var focused: FocusState<Bool>.Binding
    var attachmentsDir: String?
    let onSend: ([AgentAttachment]) -> Void
    let onStop: () -> Void
    let onReset: (() -> Void)?
    @State private var attachments: [AgentAttachment] = []
    @EnvironmentObject private var model: AppModel

    private var canSend: Bool {
        !running && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    private func send() {
        guard canSend else { return }
        let files = attachments
        attachments = []
        onSend(files)
    }

    private func attachFromPanel() {
        guard let attachmentsDir else { return }
        let result = AgentPasteboard.store(AgentPasteboard.chooseFiles(), into: attachmentsDir)
        attachments.append(contentsOf: result.attachments)
        if !result.errors.isEmpty { model.showError(result.errors.joined(separator: "\n")) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                AttachmentChips(items: attachments) { item in
                    attachments.removeAll { $0 == item }
                    AgentAttachments.discard(item)
                }
            }
            inputRow
        }
        .agentAttachmentInput($attachments, focused: focused, directory: attachmentsDir)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Pergunte ou peça algo · cole ou arraste imagens, PDFs e arquivos", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...6)
                .focused(focused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2, lineWidth: 1))
            if attachmentsDir != nil {
                Button(action: attachFromPanel) {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(IconButton(size: 38))
                .help("Anexar arquivos · também dá para colar (⌘V) ou arrastar")
                .accessibilityLabel("Anexar arquivos")
            }
            if running {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(IconButton(size: 38))
                .help("Interromper")
                .accessibilityLabel("Interromper")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(canSend ? Theme.emberDark : Theme.faded)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(canSend ? Theme.ember : Theme.surface))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Enviar")
            }
            if let onReset {
                Button(action: onReset) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(IconButton(size: 38))
                .help("Limpar a tela e começar outra conversa")
                .accessibilityLabel("Nova conversa")
            }
        }
    }
}

struct AgentItemRow: View {
    let item: AgentItem

    var body: some View {
        switch item.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if !item.text.isEmpty {
                    Text(item.text)
                        .font(.system(size: 13.5))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
                }
                if !item.attachments.isEmpty {
                    Label(item.attachments.joined(separator: ", "), systemImage: "paperclip")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 80)
        case .assistant:
            Text(markdown(item.text))
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            AgentToolCard(item: item)
        case .notice:
            Label(item.text, systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.waitText)
        case .error:
            Label(item.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dangerText)
                .textSelection(.enabled)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

enum AgentChatRow: Identifiable {
    case item(AgentItem)
    case tools([AgentItem])

    var id: Int {
        switch self {
        case .item(let item): return item.id
        case .tools(let tools): return tools[0].id
        }
    }

    static func group(_ items: [AgentItem]) -> [AgentChatRow] {
        var rows: [AgentChatRow] = []
        var run: [AgentItem] = []
        func flush() {
            guard !run.isEmpty else { return }
            rows.append(run.count == 1 ? .item(run[0]) : .tools(run))
            run = []
        }
        for item in items {
            if item.kind == .tool {
                run.append(item)
            } else {
                flush()
                rows.append(.item(item))
            }
        }
        flush()
        return rows
    }
}

private struct AgentToolGroup: View {
    let tools: [AgentItem]
    @State private var open = false

    private var current: AgentItem? { tools.last(where: { $0.result == nil }) }
    private var failures: Int { tools.filter(\.resultIsError).count }

    private var title: String {
        if let current {
            let isFile = ["Read", "Edit", "Write", "NotebookEdit"].contains(current.toolName)
            return "\(current.toolName ?? "ferramenta") \(isFile ? Paths.name(current.text) : current.text)"
        }
        var counts: [String: Int] = [:]
        for tool in tools { counts[tool.toolName ?? "ferramenta", default: 0] += 1 }
        let parts = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3).map { "\($0.value) \($0.key)" }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .frame(width: 14)
                    Text("\(tools.count) ações")
                        .font(.system(size: 12, weight: .medium))
                    Text(title)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if failures > 0 {
                        Text("\(failures) com erro")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dangerText)
                    }
                    if current != nil { ProgressView().controlSize(.mini) }
                }
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(failures > 0 ? Theme.danger.opacity(0.5) : Theme.line2, lineWidth: 1))
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tools) { AgentToolCard(item: $0) }
                }
                .padding(.leading, 14)
            }
        }
    }
}

private struct AgentToolCard: View {
    let item: AgentItem
    @State private var open = false

    private var symbol: String {
        switch item.toolName {
        case "Read": return "doc.text"
        case "Edit", "Write", "NotebookEdit": return "pencil"
        case "Bash": return "terminal"
        case "Grep", "Glob": return "magnifyingglass"
        default: return "wrench.and.screwdriver"
        }
    }

    private var accent: Color {
        item.resultIsError ? Theme.dangerText : Theme.text3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if item.result != nil { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .frame(width: 14)
                    Text(item.toolName ?? "ferramenta")
                        .font(.system(size: 12, weight: .medium))
                    Text(item.text)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if item.result == nil {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: open ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open, let result = item.result {
                Rectangle().fill(Theme.line).frame(height: 1)
                ScrollView {
                    Text(result.isEmpty ? "(sem saída)" : String(result.prefix(6000)))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.text3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 220)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.resultIsError ? Theme.danger.opacity(0.5) : Theme.line2, lineWidth: 1))
    }
}
