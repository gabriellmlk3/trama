import Foundation
import SwiftUI

private struct ConflictsKey: Hashable {
    var worktree: String
    var stamp: Int64
    var version: Int
}

struct ConflictsPanel: View {
    @EnvironmentObject var model: AppModel
    let repo: String
    let worktree: String
    var onChange: () -> Void = {}

    @State private var conflicts: ConflictState?
    @State private var version = 0
    @State private var resolving: ConflictFile?
    @State private var confirmingAbort = false

    var body: some View {
        VStack(spacing: 0) {
            if let c = conflicts, c.merging || !c.files.isEmpty {
                card(c)
            }
        }
        .task(id: ConflictsKey(worktree: worktree, stamp: model.state?.generatedAt ?? 0, version: version)) {
            let repo = repo
            let worktree = worktree
            conflicts = try? await Core.run { try $0.conflictState(repo: repo, worktree: worktree) }
        }
        .sheet(item: $resolving) { file in
            ConflictResolver(repo: repo, worktree: worktree, file: file) {
                version += 1
                onChange()
            }
        }
        .alert("Abortar o merge?", isPresented: $confirmingAbort) {
            Button("Abortar merge", role: .destructive) {
                Task {
                    if await model.abortMerge(repo, worktree: worktree) { version += 1 }
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Volta o worktree ao estado anterior ao merge. As resoluções feitas até aqui serão descartadas.")
        }
    }

    func card(_ c: ConflictState) -> some View {
        GitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.wait)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.files.isEmpty ? "Todos os conflitos foram resolvidos" : "\(c.files.count) \(plural(c.files.count, "arquivo em conflito", "arquivos em conflito"))")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(c.incoming.isEmpty ? "merge em andamento" : "merge de \(c.incoming) em andamento")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.faded)
                    }
                    Spacer(minLength: 8)
                    if c.merging {
                        Button("Abortar merge") { confirmingAbort = true }
                            .buttonStyle(ToneButton(color: Theme.danger, text: Theme.dangerText))
                        Button("Concluir merge") {
                            Task {
                                if await model.concludeMerge(repo, worktree: worktree) { version += 1 }
                            }
                        }
                        .buttonStyle(EmberButton(compact: true))
                        .disabled(!c.files.isEmpty || model.busy)
                        .opacity(c.files.isEmpty ? 1 : 0.4)
                    }
                }
                if !c.files.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(c.files) { f in
                            row(f)
                        }
                    }
                }
            }
            .padding(14)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.wait.opacity(0.45), lineWidth: 1))
    }

    func row(_ f: ConflictFile) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.path)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(f.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faded)
            }
            Spacer(minLength: 8)
            Button("Aceitar minha") { accept(f, .ours) }
                .buttonStyle(GhostButton(compact: true))
                .help("Mantém a versão deste worktree")
            Button("Aceitar deles") { accept(f, .theirs) }
                .buttonStyle(GhostButton(compact: true))
                .help("Fica com a versão que veio do merge")
            if f.canMerge {
                Button("Mesclar…") { resolving = f }
                    .buttonStyle(EmberButton(compact: true))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .disabled(model.busy)
    }

    func accept(_ f: ConflictFile, _ side: ConflictSide) {
        Task {
            if await model.acceptSide(repo, worktree: worktree, file: f.path, side: side) { version += 1 }
        }
    }
}

private struct HunkEditing: Equatable {
    var id: Int
    var text: String
}

struct ConflictResolver: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let repo: String
    let worktree: String
    let file: ConflictFile
    let onApplied: () -> Void

    @State private var document: ConflictDocument?
    @State private var loadError: String?
    @State private var resolutions: [Int: ConflictResolution] = [:]
    @State private var editing: HunkEditing?

    var hunks: [ConflictHunk] { document?.hunks ?? [] }
    var pending: Int { hunks.filter { resolutions[$0.id] == nil }.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)
            if let document {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(document.segments) { segment in
                            switch segment {
                            case .context(_, let lines):
                                contextBlock(lines)
                            case .hunk(let h):
                                hunkRow(h, document)
                            }
                        }
                    }
                    .padding(16)
                }
            } else if let loadError {
                Text(loadError)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.waitText)
                    .padding(24)
                Spacer()
            } else {
                ProgressView().controlSize(.small).padding(24)
                Spacer()
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .background(Theme.background)
        .task {
            let repo = repo
            let worktree = worktree
            let path = file.path
            do {
                document = try await Core.run { try $0.conflictDocument(repo: repo, worktree: worktree, file: path) }
            } catch {
                loadError = errorMessage(error)
            }
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path)
                    .font(Theme.mono(13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(hunks.isEmpty ? "lendo…" : (pending == 0 ? "todos os trechos resolvidos" : "\(pending) de \(hunks.count) \(plural(hunks.count, "trecho", "trechos")) por resolver"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(pending == 0 ? Theme.okText : Theme.waitText)
            }
            Spacer(minLength: 8)
            Button("Todas minhas") { resolveAll(.ours) }
                .buttonStyle(GhostButton(compact: true))
            Button("Todas deles") { resolveAll(.theirs) }
                .buttonStyle(GhostButton(compact: true))
            Button("Cancelar") { dismiss() }
                .buttonStyle(GhostButton(compact: true))
                .keyboardShortcut(.cancelAction)
            Button("Aplicar") { apply() }
                .buttonStyle(EmberButton(compact: true))
                .disabled(document == nil || pending > 0 || model.busy)
                .opacity(document != nil && pending == 0 ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    func resolveAll(_ r: ConflictResolution) {
        for h in hunks { resolutions[h.id] = r }
        editing = nil
    }

    func apply() {
        guard let document, let content = try? document.render(resolutions) else { return }
        Task {
            if await model.saveResolution(repo, worktree: worktree, file: file.path, content: content) {
                onApplied()
                dismiss()
            }
        }
    }

    func codeText(_ lines: [String]) -> some View {
        Group {
            if lines.isEmpty {
                Text("(vazio)").italic().foregroundStyle(Theme.faded)
            } else {
                Text(lines.joined(separator: "\n")).foregroundStyle(Theme.text2)
            }
        }
        .font(Theme.mono(11.5))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func contextBlock(_ lines: [String]) -> some View {
        let shown = lines.count > 9 ? Array(lines.prefix(3)) + ["⋯ \(lines.count - 6) linhas iguais ⋯"] + Array(lines.suffix(3)) : lines
        return codeText(shown)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .opacity(0.75)
    }

    func column(title: String, tone: Color, text: Color, lines: [String], arrow: String, help: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if arrow == "arrow.right" {
                    Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(text).lineLimit(1)
                    Spacer(minLength: 4)
                    arrowButton(arrow, help: help, action: action)
                } else {
                    arrowButton(arrow, help: help, action: action)
                    Spacer(minLength: 4)
                    Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(text).lineLimit(1)
                }
            }
            codeText(lines)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(tone.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tone.opacity(0.35), lineWidth: 1))
    }

    func arrowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(IconButton(size: 24))
        .help(help)
        .accessibilityLabel(help)
    }

    func hunkRow(_ h: ConflictHunk, _ doc: ConflictDocument) -> some View {
        let oursName = doc.oursLabel.isEmpty ? "Minha" : "Minha · \(doc.oursLabel)"
        let theirsName = doc.theirsLabel.isEmpty ? "Deles" : "Deles · \(doc.theirsLabel)"
        return HStack(alignment: .top, spacing: 10) {
            column(title: oursName, tone: Theme.iris, text: Theme.irisText, lines: h.ours, arrow: "arrow.right", help: "Usar a minha versão") {
                resolutions[h.id] = .ours
                editing = nil
            }
            result(h)
            column(title: theirsName, tone: Theme.ember, text: Theme.emberLight, lines: h.theirs, arrow: "arrow.left", help: "Usar a versão deles") {
                resolutions[h.id] = .theirs
                editing = nil
            }
        }
    }

    func result(_ h: ConflictHunk) -> some View {
        let resolution = resolutions[h.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Resultado").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text3)
                Spacer(minLength: 4)
                if editing?.id != h.id {
                    Button("Ambas") { resolutions[h.id] = .both }
                        .buttonStyle(GhostButton(compact: true))
                        .help("Minha versão seguida da deles")
                    Button("Editar") {
                        editing = HunkEditing(id: h.id, text: (resolution?.lines(for: h) ?? h.ours + h.theirs).joined(separator: "\n"))
                    }
                    .buttonStyle(GhostButton(compact: true))
                    if resolution != nil {
                        Button {
                            resolutions[h.id] = nil
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(IconButton(size: 28))
                        .help("Desfazer a escolha")
                    }
                }
            }
            if let e = editing, e.id == h.id {
                TextEditor(text: Binding(get: { editing?.text ?? "" }, set: { editing?.text = $0 }))
                    .font(Theme.mono(11.5))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
                HStack {
                    Spacer()
                    Button("Cancelar") { editing = nil }
                        .buttonStyle(GhostButton(compact: true))
                    Button("Usar este texto") {
                        resolutions[h.id] = .custom(e.text.isEmpty ? [] : e.text.components(separatedBy: "\n"))
                        editing = nil
                    }
                    .buttonStyle(EmberButton(compact: true))
                }
            } else if let resolution {
                codeText(resolution.lines(for: h))
            } else {
                Text("conflito · escolha um lado com as setas")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.waitText)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(resolution == nil ? Theme.wait.opacity(0.6) : Theme.ok.opacity(0.4), lineWidth: 1))
    }
}
