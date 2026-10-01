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
    @State private var advance = false
    @State private var confirmingAbort = false

    var body: some View {
        Group {
            if let c = conflicts, c.merging || !c.files.isEmpty {
                card(c)
            }
        }
        .task(id: ConflictsKey(worktree: worktree, stamp: model.state?.generatedAt ?? 0, version: version)) {
            let repo = repo
            let worktree = worktree
            conflicts = try? await Core.run { try $0.conflictState(repo: repo, worktree: worktree) }
            if advance {
                advance = false
                resolving = conflicts?.files.first(where: \.canMerge)
            }
        }
        .sheet(item: $resolving) { file in
            ConflictResolver(repo: repo, worktree: worktree, file: file, oursName: conflicts?.current ?? "", theirsName: conflicts?.incoming ?? "") {
                advance = true
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
    @State private var loadError: String?

    var body: some View {
        Group {
            if let document {
                ConflictMergeView(document: document, file: file, oursName: oursName, theirsName: theirsName, busy: model.busy, onCancel: { dismiss() }) { content in
                    Task {
                        if await model.saveResolution(repo, worktree: worktree, file: file.path, content: content) {
                            onApplied()
                            dismiss()
                        }
                    }
                }
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
                document = try await Core.run { try $0.conflictDocument(repo: repo, worktree: worktree, file: path) }
            } catch {
                loadError = errorMessage(error)
            }
        }
    }
}
