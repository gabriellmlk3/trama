import Foundation
import SwiftUI

struct NewTramaView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selected: Set<String> = []
    @State private var base = ""
    @State private var task = ""
    @State private var goal = ""
    @State private var context: String?
    @State private var openAgents = true
    @State private var sending = false

    var slug: String { slugify(title) }
    var chosen: [RepoConfig] { model.repos.filter { selected.contains($0.name) } }
    var contextLabel: String {
        if let context { return Paths.abbreviate(context) }
        if let global = model.state?.context { return "padrão · \(Paths.name(global))" }
        return "nenhum · a cápsula fica na pasta da trama"
    }
    var canWeave: Bool { !slug.isEmpty && !chosen.isEmpty && !sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ember)
                TextField("Nome da trama · ex.: Surcharge noturno", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .onSubmit(weave)
                KeyCap(text: "esc")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(hex: 0x22252B)).frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 18) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        label("Branch")
                        HStack(spacing: 10) {
                            Text(slug.isEmpty ? "trama/…" : "trama/\(slug)")
                                .font(Theme.mono(12.5))
                                .foregroundStyle(Theme.emberText)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2, lineWidth: 1))
                            Text("igual em todos, a partir de")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.faded)
                            TextField("base de cada repo", text: $base)
                                .textFieldStyle(.plain)
                                .font(Theme.mono(12))
                                .frame(width: 130)
                        }
                    }
                    GridRow(alignment: .top) {
                        label("Repositórios")
                            .padding(.top, 6)
                        RepoPicker(selected: $selected)
                    }
                    GridRow {
                        label("Tarefa")
                        TextField("opcional · ex.: CU-482", text: $task)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    GridRow(alignment: .top) {
                        label("Objetivo")
                            .padding(.top, 1)
                        TextField("opcional · vai para a cápsula que os agentes leem", text: $goal, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineLimit(1...3)
                    }
                    GridRow {
                        label("Contexto")
                        HStack(spacing: 10) {
                            Text(contextLabel)
                                .font(Theme.mono(12))
                                .foregroundStyle(context == nil ? Theme.faded : Theme.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Escolher…") {
                                if let folder = Terminal.choosePaths(multiple: false, title: "Repositório de contexto desta trama").first {
                                    context = folder
                                }
                            }
                            .buttonStyle(GhostButton(compact: true))
                            if context != nil {
                                Button("Usar padrão") { context = nil }
                                    .buttonStyle(GhostButton(compact: true))
                            }
                        }
                    }
                    GridRow {
                        label("Agentes")
                        Toggle(isOn: $openAgents) {
                            Text(openAgents ? "Abrir o Claude Code na trama, já com a cápsula (conforme Ajustes)" : "Só preparar os worktrees, você chama os agentes depois")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.text2)
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.ember)
                    }
                }

                HStack(spacing: 8) {
                    StatNumber(value: chosen.count, label: plural(chosen.count, "worktree", "worktrees"))
                    StatNumber(value: chosen.count, label: plural(chosen.count, "branch", "branches"))
                    StatNumber(value: 1, label: "cápsula")
                    StatNumber(value: openAgents ? chosen.count : 0, label: plural(openAgents ? chosen.count : 0, "agente", "agentes"), color: Theme.irisText)
                }
            }
            .padding(18)

            HStack {
                HStack(spacing: 6) {
                    KeyCap(text: "⇥")
                    Text("próximo campo")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(GhostButton())
                    .keyboardShortcut(.cancelAction)
                Button(action: weave) {
                    HStack(spacing: 10) {
                        if sending {
                            ProgressView().controlSize(.small)
                        }
                        Text("Tecer trama")
                        KeyCap(text: "↵", dark: true)
                    }
                }
                .buttonStyle(EmberButton())
                .keyboardShortcut(.defaultAction)
                .disabled(!canWeave)
                .opacity(canWeave ? 1 : 0.5)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.panel)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(hex: 0x22252B)).frame(height: 1)
            }
        }
        .frame(width: 700)
        .background(Theme.field)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.faded)
            .frame(width: 96, alignment: .leading)
    }

    func weave() {
        guard canWeave else { return }
        sending = true
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let repos = chosen.map { $0.name }
        let b = base.trimmingCharacters(in: .whitespaces)
        let t = task.trimmingCharacters(in: .whitespaces)
        let o = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let agents = openAgents
        Task {
            let options = NewTramaOptions(title: name, repos: repos, base: b, task: t, goal: o, context: context)
            let ok = await model.newTrama(options, openAgents: agents)
            sending = false
            if ok { dismiss() }
        }
    }
}

struct RepoPicker: View {
    @EnvironmentObject var model: AppModel
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(model.repos) { r in
                let on = selected.contains(r.name)
                Button {
                    if on {
                        selected.remove(r.name)
                    } else {
                        selected.insert(r.name)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(r.name)
                            .lineLimit(1)
                    }
                    .font(Theme.mono(12))
                    .foregroundStyle(on ? Theme.emberText : Color(hex: 0x9A9EA8))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Capsule().fill(on ? Theme.ember.opacity(0.14) : Theme.surface))
                    .overlay(Capsule().stroke(on ? Theme.ember.opacity(0.55) : Theme.line2, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }
            Button {
                let paths = Terminal.choosePaths(multiple: true, title: "Cadastrar mais repositórios")
                Task { await model.addRepos(paths) }
            } label: {
                Label("cadastrar", systemImage: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .overlay(Capsule().stroke(Theme.thread, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct StatNumber: View {
    let value: Int
    let label: String
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(Theme.serif(30))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.faded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line, lineWidth: 1))
    }
}
