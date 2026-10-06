import Foundation
import SwiftUI

enum DiscardRequest: Identifiable {
    case files([FileChange])
    case lines(FileChange, Set<Int>)

    var id: String {
        switch self {
        case .files(let list): return "files:" + list.map(\.path).joined(separator: "|")
        case .lines(let c, let ids): return "lines:\(c.path):" + ids.sorted().map(String.init).joined(separator: ",")
        }
    }

    var title: String {
        switch self {
        case .files(let list):
            if list.count == 1 { return "Descartar mudanças de “\(list[0].name)”?" }
            return "Descartar as mudanças de \(list.count) arquivos?"
        case .lines(_, let ids):
            return "Descartar \(ids.count) \(plural(ids.count, "linha", "linhas"))?"
        }
    }

    var message: String {
        switch self {
        case .files(let list):
            let fresh = list.filter { $0.code == "N" }.count
            let tail = fresh > 0 ? " Arquivos novos vão para a Lixeira." : ""
            return "O conteúdo volta ao último commit e o que foi escrito se perde.\(tail)"
        case .lines:
            return "As linhas escolhidas voltam ao último commit e o que foi escrito se perde."
        }
    }
}

struct ChangesPane: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let repo: String
    let merging: Bool
    let changes: [FileChange]
    @Binding var selectedFile: String?
    let diff: [DiffLine]
    let path: String
    let status: RepoStatus

    @State private var unchecked: Set<String> = []
    @State private var discarding: DiscardRequest?

    var selected: FileChange? { changes.first(where: { $0.id == selectedFile }) }

    var commitPanel: some View {
        CommitPanel(trama: trama, repo: repo, merging: merging, changes: changes, unchecked: $unchecked)
    }

    var fileList: some View {
        FileList(changes: changes, selectedFile: $selectedFile, unchecked: $unchecked, onDiscard: merging ? nil : { discarding = .files([$0]) }, onDiscardAll: merging ? nil : { discarding = .files(changes) })
    }

    var diffPane: some View {
        DiffPane(change: selected, lines: diff, path: path, onDiscardFile: merging ? nil : { discarding = .files([$0]) }, onDiscardLines: merging ? nil : { c, ids in discarding = .lines(c, ids) })
    }

    func confirm(_ request: DiscardRequest) {
        Task {
            switch request {
            case .files(let list):
                if await model.discard(trama.slug, repo: repo, paths: list.map(\.path)) {
                    unchecked.subtract(list.map(\.path))
                }
            case .lines(let change, let ids):
                _ = await model.discardLines(trama.slug, repo: repo, change: change, lines: ids)
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            AgentCard(status: status)
            content
        }
    }

    @ViewBuilder
    var content: some View {
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
            }
        } else {
            WidthSwitch {
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        fileList
                            .frame(width: 252)
                        diffPane
                    }
                    commitPanel
                }
            } narrow: {
                VStack(spacing: 14) {
                    fileList
                    commitPanel
                    diffPane
                }
            }
            .appDialog(
                { $0.title },
                item: $discarding,
                message: { $0.message },
                actions: { request in [DialogAction("Descartar", role: .destructive) { confirm(request) }] }
            )
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
    }
}

struct FileList: View {
    @EnvironmentObject var model: AppModel
    @Binding var selectedFile: String?
    let unchecked: Binding<Set<String>>?
    let changes: [FileChange]
    let onDiscard: ((FileChange) -> Void)?
    let onDiscardAll: (() -> Void)?

    init(changes: [FileChange], selectedFile: Binding<String?>, unchecked: Binding<Set<String>>? = nil, onDiscard: ((FileChange) -> Void)? = nil, onDiscardAll: (() -> Void)? = nil) {
        self.changes = changes
        self._selectedFile = selectedFile
        self.unchecked = unchecked
        self.onDiscard = onDiscard
        self.onDiscardAll = onDiscardAll
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
                if let unchecked {
                    let allChosen = !changes.contains { unchecked.wrappedValue.contains($0.id) }
                    HStack {
                        Button(allChosen ? "Desmarcar tudo" : "Marcar tudo") {
                            unchecked.wrappedValue = allChosen ? Set(changes.map(\.id)) : []
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.faded)
                        Spacer()
                        if let onDiscardAll {
                            Button("Descartar tudo", action: onDiscardAll)
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.dangerText)
                                .disabled(model.busy)
                        }
                    }
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 6)
                }
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(changes) { c in
                            FileRow(change: c, selected: c.id == selectedFile, checked: unchecked.map { !$0.wrappedValue.contains(c.id) }, discard: onDiscard.map { f in { f(c) } }, toggle: {
                                guard let unchecked else { return }
                                if unchecked.wrappedValue.contains(c.id) { unchecked.wrappedValue.remove(c.id) } else { unchecked.wrappedValue.insert(c.id) }
                            }) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedFile = c.id }
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(height: min(CGFloat(changes.count) * 47, 380))
            }
            .padding(10)
        }
    }
}

struct FileRow: View {
    let change: FileChange
    let selected: Bool
    let checked: Bool?
    let discard: (() -> Void)?
    let toggle: () -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let checked {
                    Button(action: toggle) {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(checked ? Theme.emberLight : Theme.faded)
                    }
                    .buttonStyle(.plain)
                    .help(checked ? "Fora do próximo commit" : "Incluir no próximo commit")
                    .accessibilityLabel(checked ? "Excluir do commit" : "Incluir no commit")
                }
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
                if let discard {
                    Button(action: discard) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dangerText)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                    .help("Descartar mudanças deste arquivo")
                    .accessibilityLabel("Descartar mudanças do arquivo")
                }
                Delta(added: change.added, removed: change.removed)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : (hovering ? Theme.surface : Color.clear)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Theme.line2 : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if let discard {
                Button("Descartar mudanças…", role: .destructive, action: discard)
            }
        }
    }
}

struct DiffPane: View {
    @EnvironmentObject var model: AppModel
    let change: FileChange?
    let lines: [DiffLine]
    let path: String
    var onDiscardFile: ((FileChange) -> Void)?
    var onDiscardLines: ((FileChange, Set<Int>) -> Void)?
    @State private var picked: Set<Int> = []
    @State private var dragAnchor: Int?
    @State private var dragBase: Set<Int> = []
    @State private var dragAdds = true

    var canPickLines: Bool { onDiscardLines != nil && change?.untracked == false }

    func hunkLines(startingAt index: Int) -> Set<Int> {
        var ids: Set<Int> = []
        for l in lines[(index + 1)...] {
            if l.kind == .hunk { break }
            if l.kind == .added || l.kind == .removed { ids.insert(l.id) }
        }
        return ids
    }

    func toggle(_ id: Int) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    func lineIndex(atY y: CGFloat) -> Int {
        min(max(Int(y / 20), 0), lines.count - 1)
    }

    func drag(_ value: DragGesture.Value) {
        guard canPickLines else { return }
        if dragAnchor == nil {
            let start = lineIndex(atY: value.startLocation.y)
            guard lines[start].kind == .added || lines[start].kind == .removed else { return }
            dragAnchor = start
            dragBase = picked
            dragAdds = !picked.contains(lines[start].id)
        }
        guard let anchor = dragAnchor else { return }
        let current = lineIndex(atY: value.location.y)
        let range = min(anchor, current)...max(anchor, current)
        let covered = Set(lines[range].filter { $0.kind == .added || $0.kind == .removed }.map(\.id))
        picked = dragAdds ? dragBase.union(covered) : dragBase.subtracting(covered)
    }

    var contentWidth: CGFloat {
        let longest = lines.reduce(0) { max($0, $1.text.utf16.count) }
        return 34 + 34 + 22 + CGFloat(longest) * 7.4 + 16
    }

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
                        if let onDiscardFile {
                            Button {
                                onDiscardFile(c)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundStyle(Theme.dangerText)
                            }
                            .buttonStyle(IconButton(size: 26))
                            .help("Descartar todas as mudanças deste arquivo")
                            .accessibilityLabel("Descartar mudanças do arquivo")
                        }
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
                                ForEach(Array(lines.enumerated()), id: \.element.id) { index, l in
                                    DiffRow(
                                        line: l,
                                        picked: picked.contains(l.id),
                                        onPick: canPickLines && (l.kind == .added || l.kind == .removed) ? { toggle(l.id) } : nil,
                                        onDiscardHunk: canPickLines && l.kind == .hunk ? {
                                            if let c = change { onDiscardLines?(c, hunkLines(startingAt: index)) }
                                        } : nil
                                    )
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 4)
                                    .onChanged(drag)
                                    .onEnded { _ in dragAnchor = nil }
                            )
                            .frame(minWidth: max(geo.size.width, contentWidth), alignment: .topLeading)
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.automatic)
                    }
                    .frame(height: min(420, CGFloat(lines.count) * 20 + 12))
                    .id(change?.id)
                    .transition(.opacity)
                    if !picked.isEmpty, let c = change {
                        HStack(spacing: 10) {
                            Text("\(picked.count) \(plural(picked.count, "linha escolhida", "linhas escolhidas"))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text3)
                            Spacer()
                            Button("Limpar") { picked = [] }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.faded)
                            Button {
                                onDiscardLines?(c, picked)
                            } label: {
                                Label("Descartar linhas", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(GhostButton(compact: true))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: picked.isEmpty)
        .onChange(of: change?.id) { _, _ in picked = [] }
        .onChange(of: lines) { _, _ in picked = [] }
    }
}

struct DiffRow: View {
    let line: DiffLine
    var picked = false
    var onPick: (() -> Void)?
    var onDiscardHunk: (() -> Void)?

    var background: Color {
        switch line.kind {
        case .added: return Theme.ok.opacity(picked ? 0.28 : 0.11)
        case .removed: return Theme.danger.opacity(picked ? 0.28 : 0.11)
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
                if let onDiscardHunk {
                    Button(action: onDiscardHunk) {
                        Label("Descartar bloco", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dangerText)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                    .help("Descartar todas as linhas alteradas deste bloco")
                }
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
        .overlay(alignment: .leading) {
            if picked { Rectangle().fill(Theme.ember).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { onPick?() }
        .help(onPick == nil ? "" : "Clique ou arraste para escolher linhas")
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        AgentBadge(agent: ag)
                        Text("·").foregroundStyle(Theme.faded)
                        Text(Paths.abbreviate(ag.cwd))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(relativeTime(ag.updatedAt))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faded)
                    }
                    if let m = ag.message, !m.isEmpty {
                        Text(m)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.irisText)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help("Agente neste worktree")
        }
    }
}

struct CommitPanel: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let repo: String
    let merging: Bool
    let changes: [FileChange]
    @Binding var unchecked: Set<String>
    private var message: String { model.commitDraft(trama.slug, repo).wrappedValue }
    private var generating: Bool { model.isGeneratingCommit(trama.slug, repo) }

    var chosen: [String] { changes.map(\.id).filter { !unchecked.contains($0) } }
    var canCommit: Bool {
        !model.busy && !chosen.isEmpty && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!merging || chosen.count == changes.count)
    }

    var body: some View {
        GitCard {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Mensagem do commit", text: model.commitDraft(trama.slug, repo), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(1...5)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                if merging && chosen.count != changes.count {
                    Text("Merge em andamento: o commit precisa incluir todos os arquivos.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.waitText)
                }
                HStack {
                    Button {
                        generate()
                    } label: {
                        if generating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Label("Gerar mensagem", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(GhostButton(compact: true))
                    .disabled(generating || chosen.isEmpty)
                    .help("Gerar a mensagem com o Claude a partir dos arquivos marcados")
                    Spacer()
                    Button {
                        let paths = chosen
                        let text = message
                        Task {
                            if await model.commit(trama.slug, repo: repo, paths: paths, message: text) {
                                model.commitDraft(trama.slug, repo).wrappedValue = ""
                                unchecked = []
                            }
                        }
                    } label: {
                        Text("Commitar \(chosen.count) \(plural(chosen.count, "arquivo", "arquivos"))")
                    }
                    .buttonStyle(EmberButton(compact: true))
                    .disabled(!canCommit)
                    .opacity(canCommit ? 1 : 0.45)
                }
            }
            .padding(12)
        }
    }

    func generate() {
        guard !generating else { return }
        let paths = chosen
        let slug = trama.slug
        let repo = repo
        Task { await model.generateCommitMessage(slug, repo: repo, paths: paths) }
    }
}
