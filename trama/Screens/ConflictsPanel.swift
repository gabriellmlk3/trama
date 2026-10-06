import Foundation
import SwiftUI

private struct ConflictsKey: Hashable {
    var worktree: String
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
    @State private var advance = false
    @State private var confirmingAbort = false
    @State private var showingAll = false

    private let collapsedLimit = 8

    func reload() async {
        let repo = repo
        let worktree = worktree
        conflicts = try? await Core.run { try $0.conflictState(repo: repo, worktree: worktree) }
        if advance {
            advance = false
            resolving = conflicts?.files.first(where: \.canMerge)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let c = conflicts, c.merging || !c.files.isEmpty {
                card(c)
            }
        }
        .task(id: ConflictsKey(worktree: worktree, version: version)) { await reload() }
        .onRefresh(model.clock) { await reload() }
        .sheet(item: $resolving) { file in
            ConflictResolver(repo: repo, worktree: worktree, file: file, oursName: conflicts?.current ?? "", theirsName: conflicts?.incoming ?? "") {
                advance = true
                version += 1
                onChange()
            }
        }
        .appDialog(
            "Abortar o merge?",
            isPresented: $confirmingAbort,
            message: "Volta o worktree ao estado anterior ao merge. As resoluções feitas até aqui serão descartadas.",
            actions: [
                DialogAction("Abortar merge", role: .destructive) {
                    Task {
                        if await model.abortMerge(repo, worktree: worktree) { version += 1 }
                    }
                },
            ]
        )
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
                    let visible = showingAll ? c.files : Array(c.files.prefix(collapsedLimit))
                    VStack(spacing: 4) {
                        ForEach(visible) { f in
                            row(f)
                        }
                        if c.files.count > collapsedLimit {
                            Button(showingAll ? "Mostrar menos" : "Mostrar todos (\(c.files.count - collapsedLimit) ocultos)") {
                                showingAll.toggle()
                            }
                            .buttonStyle(GhostButton(compact: true))
                            .padding(.top, 4)
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
                if let hint = f.generatedHint {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                        .help(hint)
                }
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

struct ConflictResolver: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let repo: String
    let worktree: String
    let file: ConflictFile
    let oursName: String
    let theirsName: String
    let onApplied: () -> Void

    @State private var document: ConflictDocument?
    @State private var restored: [Int: ConflictResolution] = [:]
    @State private var origins: [Int: ConflictOrigins] = [:]
    @State private var loadError: String?

    var body: some View {
        Group {
            if let document {
                ConflictMergeView(
                    document: document,
                    file: file,
                    oursName: oursName,
                    theirsName: theirsName,
                    busy: model.busy,
                    onCancel: { dismiss() },
                    restored: restored,
                    origins: origins,
                    onDraft: { saveDraft(document, $0) },
                    onSuggest: { hunk in try await suggest(document, hunk) },
                    onApply: { content in
                        Task {
                            if await model.saveResolution(repo, worktree: worktree, file: file.path, content: content) {
                                onApplied()
                                dismiss()
                            }
                        }
                    }
                )
            } else if let loadError {
                VStack(alignment: .leading, spacing: 14) {
                    Text(file.path).font(Theme.mono(13, weight: .medium))
                    Text(loadError).font(.system(size: 12.5)).foregroundStyle(Theme.waitText)
                    Button("Fechar") { dismiss() }.buttonStyle(GhostButton(compact: true))
                }
                .padding(24)
                .frame(minWidth: 520, minHeight: 180, alignment: .topLeading)
                .background(Theme.background)
            } else {
                ProgressView().controlSize(.small)
                    .frame(minWidth: 520, minHeight: 180)
                    .background(Theme.background)
            }
        }
        .task {
            let repo = repo
            let worktree = worktree
            let path = file.path
            do {
                let loaded = try await Core.run { w -> (ConflictDocument, [Int: ConflictResolution]) in
                    let doc = try w.conflictDocument(repo: repo, worktree: worktree, file: path)
                    return (doc, w.loadConflictDraft(worktree: worktree, document: doc))
                }
                restored = loaded.1
                document = loaded.0
                origins = (try? await Core.run { try $0.conflictOrigins(repo: repo, worktree: worktree, file: path, document: loaded.0) }) ?? [:]
            } catch {
                loadError = errorMessage(error)
            }
        }
    }

    func saveDraft(_ document: ConflictDocument, _ resolutions: [Int: ConflictResolution]) {
        let worktree = worktree
        Task { try? await Core.run { $0.saveConflictDraft(worktree: worktree, document: document, resolutions: resolutions) } }
    }

    func suggest(_ document: ConflictDocument, _ hunk: ConflictHunk) async throws -> [String] {
        let repo = repo
        let worktree = worktree
        let path = file.path
        return try await Core.run { try $0.suggestConflictResolution(repo: repo, worktree: worktree, file: path, document: document, hunk: hunk.id) }
    }
}
