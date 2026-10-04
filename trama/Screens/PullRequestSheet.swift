import Foundation
import SwiftUI

struct PullRequestSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planner = PullRequestPlanner()
    @State private var pickingForAll = false
    @State private var sending = false
    @State private var confirmingMerge = false
    @State private var titleText = ""
    @State private var summaryText = ""
    @State private var generatingText = false
    let trama: LiveTrama

    init(trama: LiveTrama, mode: PullRequestPlanner.Mode) {
        self.trama = trama
        let planner = PullRequestPlanner()
        planner.mode = mode
        _planner = StateObject(wrappedValue: planner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            if planner.mode == .pullRequest, planner.loaded { textBlock }
            content
            footer
        }
        .frame(width: 980)
        .background(Theme.field)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .task { await planner.start(slug: trama.slug, repoCount: trama.trama.repos.count) }
    }

    var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.pull")
                    Text(trama.branch).foregroundStyle(Theme.emberLight)
                    Text("·")
                    Text(trama.title)
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.faded)
                Text(planner.mode == .merge ? "Mesclar direto" : "Abrir PRs")
                    .font(Theme.serif(32))
            }
            Spacer()
            if planner.mode == .pullRequest {
            HStack(spacing: 10) {
                Text("Abrir como rascunho")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                Toggle("Abrir como rascunho", isOn: $planner.draft)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }

    var textBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Título e descrição")
                Spacer()
                Button {
                    generateText()
                } label: {
                    if generatingText {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("Gerar com o Claude", systemImage: "sparkles")
                            .font(.system(size: 11.5))
                    }
                }
                .buttonStyle(GhostButton(compact: true))
                .disabled(generatingText || planner.selection.isEmpty)
                .help("Resume os commits à frente do destino em um título e uma descrição")
            }
            TextField(trama.title, text: $titleText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            if !summaryText.isEmpty || !titleText.isEmpty {
                TextField("Descrição (opcional)", text: $summaryText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(2...8)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    func generateText() {
        guard !generatingText else { return }
        generatingText = true
        let targets = planner.runTargets
        let only = planner.runOnly
        Task {
            if let text = await model.suggestPullRequestText(trama.slug, targets: targets, only: only) {
                titleText = text.title
                summaryText = text.summary
            }
            generatingText = false
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar
            if let failure = planner.failure {
                Text(failure)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.waitText)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if planner.loaded {
                table
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            footnote
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    var toolbar: some View {
        HStack(spacing: 14) {
            Text("Todos para")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text3)
            TargetButton(name: planner.shownForAll ?? "…", open: pickingForAll) { pickingForAll.toggle() }
                .frame(width: 188)
                .popover(isPresented: $pickingForAll, arrowEdge: .bottom) {
                    BranchPicker(
                        options: planner.options,
                        selected: planner.shownForAll,
                        totalRepos: planner.repoCount,
                        scopedRepo: nil,
                        defaultNames: planner.defaultNames,
                        planner: planner
                    ) { name in
                        planner.chooseForAll(name)
                        pickingForAll = false
                    }
                }
            if let all = planner.shownForAll {
                Chip(text: "existe em \(planner.coverage(of: all)) de \(planner.repoCount) \(plural(planner.repoCount, "repo", "repos"))")
            }
            if planner.missingCount > 0 {
                Button {
                    Task {
                        for (name, repos) in planner.missingByBranch {
                            await planner.createMissing(name, repos: repos)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if !planner.creatingBranches.isEmpty {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        }
                        Text("Criar nos \(planner.missingCount) \(plural(planner.missingCount, "repo", "repos")) sem a branch")
                    }
                }
                .buttonStyle(GhostButton(compact: true))
                .disabled(!planner.creatingBranches.isEmpty)
            }
            if let failure = planner.creationFailure {
                Text(failure)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.waitText)
                    .lineLimit(1)
                    .help(failure)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("branch de origem")
                Text(trama.base ?? planner.originLabel)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.text3)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.faded)
            Rectangle().fill(Theme.line2).frame(width: 1, height: 18)
            Text(refreshText)
                .font(.system(size: 12))
                .foregroundStyle(planner.refreshFailures.isEmpty ? Theme.faded : Theme.waitText)
                .help(planner.refreshFailures.joined(separator: "\n"))
            Button {
                Task { await planner.refresh() }
            } label: {
                if planner.refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(IconButton(size: 30))
            .disabled(planner.refreshing)
            .help("Atualizar as branches do remoto")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }

    var refreshText: String {
        if planner.refreshing { return "atualizando o remoto…" }
        if !planner.refreshFailures.isEmpty { return "remoto não atualizado" }
        guard let at = planner.refreshedAt else { return "" }
        let ago = relativeTime(Int64(at.timeIntervalSince1970))
        return ago == "agora" ? "remoto atualizado agora" : "remoto atualizado \(ago)"
    }

    var table: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Column.gap) {
                Color.clear.frame(width: Column.check, height: 1)
                SectionLabel(text: "Repositório").frame(width: Column.repo, alignment: .leading)
                SectionLabel(text: planner.mode == .merge ? "Mesclar em" : "Destino do PR").frame(width: Column.target, alignment: .leading)
                SectionLabel(text: "Commits").frame(width: Column.commits, alignment: .leading)
                SectionLabel(text: "Conflito previsto").frame(width: Column.conflict, alignment: .leading)
                SectionLabel(text: "Situação").frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(planner.rows) { row in
                        PullRequestRowView(row: row, planner: planner)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }

    var footnote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 13))
                .foregroundStyle(Theme.iris)
                .padding(.top, 1)
            Text(planner.mode == .merge
                ? "A branch da trama é mesclada direto no destino e enviada ao remoto" + orderText + ", sem PR e sem revisão. Repositórios com conflito previsto ficam de fora: traga o destino para a trama e resolva antes."
                : "Os PRs recebem links cruzados na ordem de merge" + orderText + ". Commits e conflitos são calculados contra o destino de cada linha." + manualText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    var manualText: String {
        planner.manual > 0 ? " Onde o provedor não tem automação (ou falta o gh, az ou glab), a branch sobe e o PR abre pelo link, no navegador." : ""
    }

    var orderText: String {
        let names = planner.selection.map { $0.repo }
        return names.count > 1 ? ": " + names.joined(separator: " → ") : ""
    }

    var footer: some View {
        HStack(spacing: 18) {
            summary
            Spacer()
            Button("Cancelar") { dismiss() }
                .buttonStyle(GhostButton())
                .keyboardShortcut(.cancelAction)
            Button(action: { planner.mode == .merge ? (confirmingMerge = true) : submit() }) {
                HStack(spacing: 10) {
                    if sending {
                        ProgressView().controlSize(.small)
                    }
                    Text(planner.buttonTitle)
                    KeyCap(text: "⌘↵", dark: true)
                }
            }
            .buttonStyle(EmberButton())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!planner.canSubmit || sending)
            .opacity(planner.canSubmit && !sending ? 1 : 0.5)
        }
        .appDialog(
            "Mesclar direto, sem PR?",
            isPresented: $confirmingMerge,
            message: planner.selection.map { "\($0.repo) → \($0.target)" }.joined(separator: "\n"),
            actions: [DialogAction("Mesclar e enviar ao remoto", role: .destructive, handler: submit)]
        )
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Theme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    var summary: some View {
        HStack(spacing: 18) {
            let pushes = planner.selection.count
            if pushes == 0 {
                Text("Nada para enviar")
            } else if planner.mode == .merge {
                SummaryStat(value: pushes, text: pushes == 1 ? "branch recebe a mescla" : "branches recebem a mescla", color: Theme.emberLight)
            } else {
                SummaryStat(value: pushes, text: pushes == 1 ? "branch vai para o remoto" : "branches vão para o remoto", color: Theme.text)
                if planner.creating > 0 {
                    SummaryStat(value: planner.creating, text: plural(planner.creating, "PR novo", "PRs novos"), color: Theme.emberLight)
                }
                if planner.retargeting > 0 {
                    SummaryStat(value: planner.retargeting, text: plural(planner.retargeting, "redirecionado", "redirecionados"), color: Theme.irisText)
                }
                if planner.updating > 0 {
                    SummaryStat(value: planner.updating, text: plural(planner.updating, "atualizado", "atualizados"), color: Theme.okText)
                }
                if planner.manual > 0 {
                    SummaryStat(value: planner.manual, text: plural(planner.manual, "abre no navegador", "abrem no navegador"), color: Theme.text2)
                }
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.faded)
    }

    func submit() {
        guard planner.canSubmit, !sending else { return }
        sending = true
        let targets = planner.runTargets
        let only = planner.runOnly
        let draft = planner.draft
        let merging = planner.mode == .merge
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if merging {
                let ok = await model.mergeIntoBranches(trama.slug, targets: targets, only: only)
                sending = false
                if ok { dismiss() }
                return
            }
            let ok = await model.openPullRequests(trama.slug, draft: draft, targets: targets, only: only, title: title.isEmpty ? nil : title, summary: summary)
            sending = false
            if ok { dismiss() }
        }
    }
}
