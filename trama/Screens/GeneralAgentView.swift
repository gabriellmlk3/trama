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
        AgentInputBar(draft: $draft, running: session.running, focused: $focused, onSend: send, onStop: { session.stop() }, onReset: items.isEmpty ? nil : { session.reset() })
    }

    private func send() {
        let text = draft
        draft = ""
        session.send(text)
    }
}

struct AgentConversationList: View {
    @ObservedObject var session: GeneralAgentSession

    private var items: [AgentItem] { session.conversation.items }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        AgentItemRow(item: item)
                            .id(item.id)
                    }
                    if session.running { AgentWorking() }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 40)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: items.last) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
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

private struct AgentInputBar: View {
    @Binding var draft: String
    let running: Bool
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    let onReset: (() -> Void)?

    private var canSend: Bool {
        !running && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Pergunte ou peça algo sobre suas tramas…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...6)
                .focused(focused)
                .onSubmit { if canSend { onSend() } }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2, lineWidth: 1))
            if running {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(IconButton(size: 38))
                .help("Interromper")
                .accessibilityLabel("Interromper")
            } else {
                Button(action: onSend) {
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
            Text(item.text)
                .font(.system(size: 13.5))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
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
