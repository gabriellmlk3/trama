import SwiftUI

private func shortPath(_ path: String?) -> String? {
    guard let path else { return nil }
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

private func durationText(_ seconds: TimeInterval) -> String {
    if seconds < 1 { return "\(Int(seconds * 1000)) ms" }
    if seconds < 60 { return String(format: "%.1f s", seconds) }
    let total = Int(seconds)
    if total < 3600 { return "\(total / 60) min \(total % 60) s" }
    return "\(total / 3600) h \(total % 3600 / 60) min"
}

private struct BlockTone {
    let color: Color
    let symbol: String

    init(_ block: TerminalBlock) {
        if block.isRunning {
            color = Theme.ember
            symbol = "circle.dotted"
        } else if block.exitCode == 0 || block.exitCode == nil {
            color = Theme.ok
            symbol = "checkmark.circle.fill"
        } else {
            color = Theme.danger
            symbol = "xmark.circle.fill"
        }
    }
}

struct BlockDuration: View {
    let block: TerminalBlock

    var body: some View {
        if block.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(durationText(max(0, context.date.timeIntervalSince(block.startedAt))))
            }
        } else if let duration = block.duration {
            Text(durationText(duration))
        }
    }
}

struct TerminalSessionView: View {
    @ObservedObject var session: TerminalSession
    let height: CGFloat

    private static let stripHeight: CGFloat = 30

    var body: some View {
        if session.usesBlocks {
            blocksBody
        } else {
            classicBody
        }
    }

    private var classicBody: some View {
        ZStack {
            TerminalHostView(session: session)
            if !session.running {
                VStack {
                    Spacer()
                    Text("sessão encerrada")
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.faded)
                        .padding(.bottom, 10)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .background(Theme.loom)
    }

    @ViewBuilder
    private var blocksBody: some View {
        let mode = session.mode
        let liveHeight = mode == .starting ? height : max(120, (height - Self.stripHeight) * 0.62)
        let liveVisible = mode != .ready
        VStack(spacing: 0) {
            if mode != .starting {
                BlockTimeline(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if mode == .running {
                RunningStrip(session: session)
                    .frame(height: Self.stripHeight)
            }
            TerminalHostView(session: session)
                .frame(height: liveHeight)
                .frame(height: liveVisible ? liveHeight : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(liveVisible)
            if mode == .ready {
                if session.running {
                    TerminalInputBar(session: session)
                } else {
                    Text("sessão encerrada")
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.faded)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Theme.field)
                }
            }
        }
        .frame(height: height)
        .background(Theme.loom)
    }
}

struct RunningStrip: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        let block = session.blocks.last(where: \.isRunning)
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)
            Text((block?.command ?? "").components(separatedBy: "\n").first ?? "")
                .font(Theme.mono(11.5, weight: .medium))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .truncationMode(.tail)
            if let block {
                BlockDuration(block: block)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faded)
            }
            Spacer(minLength: 8)
            Button {
                session.interrupt()
            } label: {
                HStack(spacing: 4) {
                    Text("Interromper")
                    KeyCap(text: "⌃C")
                }
            }
            .buttonStyle(GhostButton())
        }
        .padding(.horizontal, 12)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct BlockTimeline: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !session.startupOutput.isEmpty {
                        StartupCard(session: session)
                    }
                    ForEach(session.blocks) { block in
                        BlockCard(session: session, block: block)
                            .id(block.id)
                    }
                    Color.clear.frame(height: 1).id("fim")
                }
                .padding(10)
            }
            .onAppear { proxy.scrollTo("fim", anchor: .bottom) }
            .onChange(of: session.blocks.count) { _, _ in proxy.scrollTo("fim", anchor: .bottom) }
            .onChange(of: session.mode) { _, _ in proxy.scrollTo("fim", anchor: .bottom) }
        }
    }
}

struct OutputText: View {
    let output: BlockOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(output.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if output.truncated {
                Text("saída truncada nas últimas \(TerminalSnapshot.maxLines) linhas")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.faded)
            }
        }
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct StartupCard: View {
    @ObservedObject var session: TerminalSession
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                    Text("início da sessão")
                        .font(Theme.mono(11.5))
                    Spacer()
                }
                .foregroundStyle(Theme.faded)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                OutputText(output: session.startupOutput)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
    }
}

struct BlockCard: View {
    @ObservedObject var session: TerminalSession
    let block: TerminalBlock
    @State private var hovering = false

    var body: some View {
        let tone = BlockTone(block)
        let output = session.output(for: block)
        let collapsed = session.collapsed.contains(block.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: tone.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(tone.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.command)
                        .font(Theme.mono(12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(collapsed ? 1 : 4)
                        .textSelection(.enabled)
                    if let directory = shortPath(block.directory) {
                        Text(directory)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.faded)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 8)
                if let code = block.exitCode, code != 0 {
                    Text("saiu \(code)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dangerText)
                }
                BlockDuration(block: block)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faded)
                HStack(spacing: 2) {
                    Button { Terminal.copy(block.command) } label: { Image(systemName: "terminal") }
                        .buttonStyle(IconButton(size: 22))
                        .help("Copiar comando")
                    if let output, !output.isEmpty {
                        Button { Terminal.copy(output.plain) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(IconButton(size: 22))
                            .help("Copiar saída")
                        Button { session.toggleCollapsed(block) } label: {
                            Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        }
                        .buttonStyle(IconButton(size: 22))
                        .help(collapsed ? "Mostrar saída" : "Recolher saída")
                    }
                }
                .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if let output, !output.isEmpty, !collapsed {
                Rectangle().fill(Theme.line).frame(height: 1)
                OutputText(output: output)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tone.color.opacity(block.isRunning || block.exitCode == 0 ? 0.0 : 0.9))
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .onHover { hovering = $0 }
    }
}

struct TerminalInputBar: View {
    @ObservedObject var session: TerminalSession
    @State private var text = ""
    @State private var editorHeight: CGFloat = 24
    @State private var focusToken = 0
    @State private var historyIndex: Int?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                Text(shortPath(session.currentDirectory) ?? "")
                    .font(Theme.mono(11))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Text("⏎ executa · ⇧⏎ nova linha")
                    .font(Theme.mono(10.5))
            }
            .foregroundStyle(Theme.faded)
            HStack(alignment: .top, spacing: 8) {
                Text("❯")
                    .font(Theme.mono(12.5, weight: .medium))
                    .foregroundStyle(Theme.ember)
                    .padding(.top, 3)
                CommandEditor(
                    text: $text,
                    height: $editorHeight,
                    focusToken: focusToken,
                    onSubmit: submit,
                    onHistory: navigate,
                    onInterrupt: interrupt
                )
                .frame(height: editorHeight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.field)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
        .onAppear { focusToken += 1 }
    }

    private func submit() {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        session.submit(command)
        text = ""
        historyIndex = nil
    }

    private func interrupt() {
        if text.isEmpty {
            session.interrupt()
        } else {
            text = ""
            historyIndex = nil
        }
    }

    private func navigate(_ direction: Int) {
        let history = session.history
        if direction < 0 {
            guard !history.isEmpty else { return }
            if historyIndex == nil { draft = text }
            let next = min((historyIndex ?? -1) + 1, history.count - 1)
            historyIndex = next
            text = history[next]
        } else if let index = historyIndex {
            if index == 0 {
                historyIndex = nil
                text = draft
            } else {
                historyIndex = index - 1
                text = history[index - 1]
            }
        }
    }
}
