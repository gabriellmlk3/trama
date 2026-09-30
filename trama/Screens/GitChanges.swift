import Foundation
import SwiftUI

struct ChangesPane: View {
    let changes: [FileChange]
    @Binding var selectedFile: String?
    let diff: [DiffLine]
    let path: String
    let status: RepoStatus

    var selected: FileChange? { changes.first(where: { $0.id == selectedFile }) }

    var body: some View {
        if changes.isEmpty {
            VStack(spacing: 14) {
                GitCard {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.okText)
                        Text("Worktree limpo · nada para commitar.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.text3)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                AgentCard(status: status)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        FileList(changes: changes, selectedFile: $selectedFile)
                        AgentCard(status: status)
                    }
                    .frame(width: 252)
                    DiffPane(change: selected, lines: diff, path: path)
                }
                VStack(spacing: 14) {
                    FileList(changes: changes, selectedFile: $selectedFile)
                    DiffPane(change: selected, lines: diff, path: path)
                    AgentCard(status: status)
                }
            }
        }
    }
}

struct FileBadge: View {
    let code: String

    var color: Color {
        switch code {
        case "N": return Theme.ok
        case "D": return Theme.danger
        case "R": return Theme.iris
        default: return Theme.wait
        }
    }

    var body: some View {
        Text(code)
            .font(Theme.mono(10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.16)))
    }
}

struct Delta: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: 5) {
            Text("+\(added)").foregroundStyle(Theme.okText)
            if removed > 0 { Text("−\(removed)").foregroundStyle(Theme.dangerText) }
        }
        .font(Theme.mono(11))
        .contentTransition(.numericText())
    }
}

struct FileList: View {
    @Binding var selectedFile: String?
    let changes: [FileChange]

    init(changes: [FileChange], selectedFile: Binding<String?>) {
        self.changes = changes
        self._selectedFile = selectedFile
    }

    var body: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(changes.count) \(plural(changes.count, "arquivo", "arquivos"))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    Delta(added: changes.reduce(0) { $0 + $1.added }, removed: changes.reduce(0) { $0 + $1.removed })
                }
                .padding(.horizontal, 6)
                VStack(spacing: 3) {
                    ForEach(changes) { c in
                        FileRow(change: c, selected: c.id == selectedFile) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedFile = c.id }
                        }
                        .transition(.opacity.combined(with: .offset(x: -8)))
                    }
                }
            }
            .padding(10)
        }
        .animation(.easeOut(duration: 0.25), value: changes.map(\.id))
    }
}

struct FileRow: View {
    let change: FileChange
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                FileBadge(code: change.code)
                VStack(alignment: .leading, spacing: 3) {
                    Text(change.name)
                        .font(Theme.mono(12.5))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !change.directory.isEmpty {
                        Text(change.directory)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.faded)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 4)
                Delta(added: change.added, removed: change.removed)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : (hovering ? Theme.surface : Color.clear)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Theme.line2 : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

struct DiffPane: View {
    @EnvironmentObject var model: AppModel
    let change: FileChange?
    let lines: [DiffLine]
    let path: String

    var body: some View {
        GitCard {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if let c = change {
                        Text(c.directory)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.faded)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Text(c.name)
                            .font(Theme.mono(12.5, weight: .medium))
                            .lineLimit(1)
                        Delta(added: c.added, removed: c.removed)
                    } else {
                        Text("Escolha um arquivo")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faded)
                    }
                    Spacer(minLength: 6)
                    if let c = change {
                        Button {
                            Terminal.copy(c.path)
                            model.showNotice("Caminho copiado")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(IconButton(size: 26))
                        .help("Copiar caminho do arquivo")
                        .accessibilityLabel("Copiar caminho do arquivo")
                        Button {
                            Terminal.openFile(path + "/" + c.path)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(IconButton(size: 26))
                        .help("Abrir no editor")
                        .accessibilityLabel("Abrir no editor")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                if lines.isEmpty {
                    Text(change == nil ? "" : "Sem diferenças de texto para mostrar.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    GeometryReader { geo in
                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(lines) { l in
                                    DiffRow(line: l)
                                }
                            }
                            .frame(minWidth: geo.size.width, alignment: .topLeading)
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.automatic)
                    }
                    .frame(height: min(420, CGFloat(lines.count) * 20 + 12))
                    .id(change?.id)
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DiffRow: View {
    let line: DiffLine

    var background: Color {
        switch line.kind {
        case .added: return Theme.ok.opacity(0.11)
        case .removed: return Theme.danger.opacity(0.11)
        case .hunk: return Theme.iris.opacity(0.06)
        case .context: return .clear
        }
    }

    var sign: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        default: return ""
        }
    }

    var signColor: Color {
        line.kind == .added ? Theme.okText : Theme.dangerText
    }

    var body: some View {
        HStack(spacing: 0) {
            if line.kind == .hunk {
                Text(line.text)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.irisText)
                    .padding(.leading, 12)
                    .lineLimit(1)
            } else {
                Text(line.oldNumber.map(String.init) ?? "")
                    .frame(width: 34, alignment: .trailing)
                    .foregroundStyle(Theme.faded)
                Text(line.newNumber.map(String.init) ?? "")
                    .frame(width: 34, alignment: .trailing)
                    .foregroundStyle(Theme.faded)
                Text(sign)
                    .frame(width: 22)
                    .foregroundStyle(signColor)
                Text(line.text.isEmpty ? " " : line.text)
                    .foregroundStyle(line.kind == .context ? Theme.text3 : Theme.text)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 16)
            }
            Spacer(minLength: 0)
        }
        .font(Theme.mono(12))
        .frame(height: 20)
        .background(background)
    }
}

struct CommitsPane: View {
    let commits: [Commit]
    let total: Int
    let tint: Color
    let empty: String

    var body: some View {
        GitCard {
            VStack(spacing: 0) {
                if commits.isEmpty {
                    Text(empty)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.faded)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(commits.enumerated()), id: \.element.hash) { i, c in
                        HStack(spacing: 12) {
                            Circle().fill(tint).frame(width: 7, height: 7)
                            Text(c.hash)
                                .font(Theme.mono(12))
                                .foregroundStyle(tint)
                            Text(c.subject)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text2)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(relativeTime(c.timestamp))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.faded)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .overlay(alignment: .bottom) {
                            if i < commits.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                        .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    if total > commits.count {
                        Text("+ \(total - commits.count) mais antigos")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.faded)
                            .padding(12)
                    }
                }
            }
        }
    }
}

struct AgentCard: View {
    let status: RepoStatus

    var body: some View {
        if let ag = status.primaryAgent {
            GitCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        AgentBadge(agent: ag)
                        Text("Agente neste worktree")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    if let m = ag.message, !m.isEmpty {
                        Text(m)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.irisText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        row("estado", ag.stateLabel)
                        row("pasta", Paths.abbreviate(ag.cwd))
                        row("atualizado", relativeTime(ag.updatedAt))
                    }
                }
                .padding(14)
            }
        }
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.faded)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
