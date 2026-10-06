import Foundation
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: Automation?
    @State private var editingIsNew = false

    var automations: [Automation] { model.state?.automations ?? [] }
    var commands: [Automation] { automations.filter { $0.kind == .command } }
    var pathRules: [Automation] { automations.filter { $0.kind == .paths } }

    var headline: String {
        let on = automations.filter(\.enabled).count
        return "\(automations.count) \(plural(automations.count, "automação", "automações")) · \(on) \(plural(on, "ligada", "ligadas"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.faded)
                    Text("Automações")
                        .font(Theme.serif(42))
                    Text("O que o Trama faz sozinho quando você troca de trama, cria, estaciona ou retoma. Serve para qualquer stack.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text3)
                }
                Spacer()
                Button {
                    open(Automation(name: "", events: [.focus], scope: .worktrees), isNew: true)
                } label: {
                    Label("Nova automação", systemImage: "plus")
                }
                .buttonStyle(EmberButton())
            }

            FocusBar()

            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if automations.isEmpty {
                            EmptyAutomations()
                        }
                        if !commands.isEmpty {
                            group("Comandos", hint: "rodam em segundo plano nos eventos da trama", commands)
                        }
                        if !pathRules.isEmpty {
                            group("Caminhos", hint: "arquivos que passam a apontar para a trama", pathRules)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)

                VStack(spacing: 0) {
                    if let editing {
                        AutomationForm(automation: editing, isNew: editingIsNew) { saved in
                            if let saved {
                                self.editing = saved
                                editingIsNew = false
                            } else {
                                self.editing = nil
                            }
                        }
                        .id(editing.id)
                    } else {
                        TemplateGallery { template in
                            open(template.instantiate(), isNew: true)
                        }
                    }
                }
                .frame(width: 470)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x111217)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: automations) { _, list in
            if let current = editing, !editingIsNew, !list.contains(where: { $0.id == current.id }) {
                editing = nil
            }
        }
    }

    func open(_ automation: Automation, isNew: Bool) {
        editing = automation
        editingIsNew = isNew
    }

    func group(_ title: String, hint: String, _ list: [Automation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(text: title)
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
            }
            ForEach(list) { a in
                AutomationRow(automation: a, selected: editing?.id == a.id) {
                    open(a, isNew: false)
                }
            }
        }
    }
}

private struct FocusBar: View {
    @EnvironmentObject var model: AppModel

    var focused: LiveTrama? {
        guard let slug = model.state?.focus else { return nil }
        return model.visibleTramas.first { $0.slug == slug }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "scope")
                .font(.system(size: 14))
                .foregroundStyle(focused == nil ? Theme.faded : Theme.ember)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface2))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line2, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                if let focused {
                    HStack(spacing: 8) {
                        Text("Em foco")
                            .foregroundStyle(Theme.faded)
                        Text(focused.title)
                            .font(.system(size: 13.5, weight: .medium))
                        Text(focused.branch)
                            .font(Theme.mono(11.5))
                            .foregroundStyle(Theme.emberLight)
                    }
                } else {
                    Text("Nenhuma trama em foco")
                        .font(.system(size: 13.5, weight: .medium))
                }
                Text("Focar é trocar de trama: dispara as automações “ao focar” e aponta os caminhos das cópias principais. Também pelo cabeçalho da trama, ⌃1–9 na barra de menus ou `trama focar`.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(2)
            }
            .font(.system(size: 13))
            Spacer(minLength: 12)
            AppMenu(width: 300) {
                HStack(spacing: 6) {
                    Text(focused == nil ? "Focar uma trama" : "Trocar o foco")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
                .contentShape(Rectangle())
            } content: {
                if model.active.isEmpty {
                    MenuAction("Nenhuma trama ativa", disabled: true) {}
                }
                model.active.map { t in
                    MenuAction(t.title, checked: t.slug == focused?.slug) {
                        Task { await model.focus(t.slug) }
                    }
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            if focused != nil {
                Button("Tirar o foco") { Task { await model.clearFocus() } }
                    .buttonStyle(GhostButton())
                    .help("As cópias principais voltam a apontar para elas mesmas e as automações “ao sair do foco” rodam")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(focused == nil ? Color(hex: 0x111217) : Color(hex: 0x14110F)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused == nil ? Theme.line : Theme.ember.opacity(0.35), lineWidth: 1))
    }
}

private struct EmptyAutomations: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nenhuma automação ainda.")
                .font(Theme.serif(24))
            Text("Comece por um modelo ao lado ou crie uma do zero. Dois tipos:")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
            kind("terminal", "Rodar comando: instalar dependências, subir containers, gerar código… em cada worktree, na pasta da trama ou na cópia principal.")
            kind("arrow.triangle.branch", "Apontar caminhos: arquivos fora do git (.env, pubspec_overrides.yaml, go.work, local.properties) que referenciam outros repositórios passam a apontar para a trama.")
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.text3)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x111217)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }

    func kind(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.emberLight)
                .frame(width: 18)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AutomationRow: View {
    @EnvironmentObject var model: AppModel
    let automation: Automation
    let selected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: automation.kind == .command ? "terminal" : "arrow.triangle.branch")
                        .font(.system(size: 14))
                        .foregroundStyle(automation.enabled ? Theme.emberLight : Theme.faded)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface2))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line2, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(automation.name)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(automation.enabled ? Theme.text : Theme.text3)
                                .lineLimit(1)
                            ForEach(badges, id: \.self) { badge in
                                Text(badge)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: 0x9A9EA8))
                                    .padding(.horizontal, 7)
                                    .frame(height: 20)
                                    .background(Capsule().fill(Theme.line))
                            }
                        }
                        Text(place)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                        Text(automation.action)
                            .font(Theme.mono(11.5))
                            .foregroundStyle(Theme.faded)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("Ligada", isOn: Binding(
                get: { automation.enabled },
                set: { on in Task { await model.setAutomationEnabled(automation.id, on) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(automation.enabled ? "Desligar" : "Ligar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color(hex: 0x14110F) : Color(hex: 0x111217)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.ember.opacity(0.45) : Theme.line, lineWidth: 1))
        .opacity(automation.enabled ? 1 : 0.75)
    }

    var badges: [String] {
        switch automation.kind {
        case .command: return automation.events.map(\.label)
        case .paths: return [automation.followsFocus ? "segue o foco" : "todas as tramas"]
        }
    }

    var place: String {
        let repos = model.aliases(automation.repos).joined(separator: ", ")
        switch automation.scope {
        case .trama: return "na pasta da trama"
        case .worktrees: return repos.isEmpty ? "em cada worktree" : "nos worktrees de \(repos)"
        case .primaries: return "na cópia principal de \(repos)"
        }
    }
}

private struct TemplateGallery: View {
    let use: (AutomationTemplate) -> Void

    var stacks: [String] {
        var seen: [String] = []
        for t in AutomationTemplate.all where !seen.contains(t.stack) { seen.append(t.stack) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Começar de um modelo")
                        .font(Theme.serif(26))
                    Text("Um ponto de partida para cada stack. Tudo é editável depois.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text3)
                }
                ForEach(stacks, id: \.self) { stack in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: stack)
                        ForEach(AutomationTemplate.all.filter { $0.stack == stack }) { template in
                            TemplateCard(template: template) { use(template) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.never)
    }
}

private struct TemplateCard: View {
    let template: AutomationTemplate
    let use: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: use) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.automation.kind == .command ? "terminal" : "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.emberLight)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface2))
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(template.automation.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text3)
                    Text(template.automation.action)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Usar")
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? Theme.emberText : Theme.faded)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.surface2 : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(hovering ? Theme.ember.opacity(0.35) : Theme.line2, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ChoiceRow<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                ChoiceChip(title: option.label, on: option.value == selection) { selection = option.value }
            }
        }
    }
}

private struct ChoiceChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Theme.emberText : Theme.text3)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.ember.opacity(0.10) : Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.ember.opacity(0.45) : Theme.line2, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

private extension View {
    func automationField(minHeight: CGFloat = 30, alignment: Alignment = .leading) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
    }
}

private struct AutomationForm: View {
    @EnvironmentObject var model: AppModel
    let automation: Automation
    let isNew: Bool
    let finished: (Automation?) -> Void
    @State private var name = ""
    @State private var kind = AutomationKind.command
    @State private var events: Set<AutomationEvent> = []
    @State private var scope = AutomationScope.worktrees
    @State private var repos: Set<String> = []
    @State private var command = ""
    @State private var files = ""
    @State private var problem: String?
    @State private var saving = false
    @State private var confirmingRemoval = false

    static let variables = ["$TRAMA_SLUG", "$TRAMA_DIR", "$TRAMA_BRANCH", "$TRAMA_EVENTO", "$TRAMA_REPOS", "$TRAMA_NOVOS", "$TRAMA_REPO"]
    static let commonFiles = [".env", "local.properties", "pubspec_overrides.yaml", "go.work", "settings.gradle"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Nova automação" : "Editar automação")
                    .font(Theme.serif(26))
                Spacer()
                Button {
                    finished(nil)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Fechar e voltar aos modelos")
                .accessibilityLabel("Fechar")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Nome") {
                        TextField(kind == .command ? "ex.: Instalar dependências" : "ex.: .env segue a trama", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .automationField()
                    }
                    field("O que faz") {
                        ChoiceRow(selection: $kind, options: [("Rodar comando", .command), ("Apontar caminhos", .paths)])
                    }
                    if kind == .command {
                        field("Quando") {
                            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
                                ForEach(AutomationEvent.allCases, id: \.self) { event in
                                    ChoiceChip(title: title(event), on: events.contains(event)) {
                                        if events.contains(event) { events.remove(event) } else { events.insert(event) }
                                    }
                                }
                            }
                        }
                    }
                    field("Onde", hint: scopeHint) {
                        ChoiceRow(selection: $scope, options: scopeOptions)
                    }
                    if scope != .trama {
                        field(scope == .primaries ? "Repositórios" : "Só nestes repositórios",
                              hint: scope == .primaries ? "Obrigatório: em quais cópias principais agir." : "Nenhum marcado = todos os repositórios da trama.") {
                            RepoPicker(selected: $repos)
                        }
                    }
                    if kind == .command {
                        field("Comando", hint: "Roda no zsh, com o seu PATH. $TRAMA_CAMINHO_<REPO> é o worktree, se o repositório está na trama, ou a cópia principal (ex.: $TRAMA_CAMINHO_AILOS_CORE).") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextEditor(text: $command)
                                    .font(Theme.mono(12))
                                    .scrollContentBackground(.hidden)
                                    .frame(height: 96)
                                    .automationField(minHeight: 96, alignment: .topLeading)
                                FlowChips(items: Self.variables) { command += (command.isEmpty || command.hasSuffix(" ") ? "" : " ") + $0 }
                            }
                        }
                    } else {
                        field("Arquivos", hint: "Relativos ao repositório, separados por vírgula; aceita curingas (config/*.env). Todo caminho que aponta para um repositório cadastrado passa a apontar para onde ele está na trama. O resto do arquivo não muda, e arquivos versionados no git não são tocados.") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("ex.: .env, pubspec_overrides.yaml", text: $files)
                                    .textFieldStyle(.plain)
                                    .font(Theme.mono(12.5))
                                    .automationField()
                                FlowChips(items: Self.commonFiles, selected: Set(fileList)) { toggleFile($0) }
                            }
                        }
                    }
                    if let problem {
                        Text(problem)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dangerText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)

            HStack(spacing: 8) {
                if !isNew {
                    Button("Remover", role: .destructive) { confirmingRemoval = true }
                        .buttonStyle(GhostButton())
                    runMenu
                }
                Spacer()
                Button("Cancelar") { finished(isNew ? nil : automation) }
                    .buttonStyle(GhostButton())
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Criar" : "Salvar") { save() }
                    .buttonStyle(EmberButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || !isComplete)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { _, new in
            if new == .paths && scope == .trama { scope = .worktrees }
        }
        .appDialog(
            "Remover “\(automation.name)”?",
            isPresented: $confirmingRemoval,
            message: automation.followsFocus ? "Os arquivos das cópias principais voltam a apontar para elas mesmas." : "A automação deixa de rodar. Nada nos repositórios é apagado.",
            actions: [
                DialogAction("Remover", role: .destructive) {
                    Task {
                        await model.removeAutomation(automation.id)
                        finished(nil)
                    }
                },
            ]
        )
    }

    var runMenu: some View {
        AppMenu(width: 280) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                Text("Rodar agora")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
            .contentShape(Rectangle())
        } content: {
            MenuSection("Rodar em")
            if model.active.isEmpty {
                MenuAction("Nenhuma trama ativa", disabled: true) {}
            }
            model.active.map { t in
                MenuAction(t.title, checked: model.isFocused(t.slug), disabled: automation.followsFocus && !model.isFocused(t.slug)) {
                    Task { await model.runAutomation(automation.id, trama: t.slug) }
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Roda a versão salva desta automação numa trama, sem esperar o evento")
    }

    func field<Content: View>(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: label)
            content()
            if let hint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var scopeOptions: [(label: String, value: AutomationScope)] {
        kind == .command
            ? [("Cada worktree", .worktrees), ("Pasta da trama", .trama), ("Cópia principal", .primaries)]
            : [("Cada worktree", .worktrees), ("Cópia principal", .primaries)]
    }

    var scopeHint: String {
        switch (kind, scope) {
        case (.command, .worktrees): return "Uma vez em cada worktree da trama."
        case (.command, .trama): return "Uma vez, na pasta da trama (~/Tramas/<trama>)."
        case (.command, .primaries): return "Na cópia principal dos repositórios escolhidos, só quando a trama está (ou entra) em foco."
        case (.paths, .primaries): return "Aponta para a trama em foco e volta para as cópias principais quando nenhuma estiver em foco."
        case (.paths, _): return "Nos worktrees de todas as tramas: o que está na trama vira ../repo e o que não está aponta para a cópia principal. Reaplicado ao criar, incluir ou soltar repositórios."
        }
    }

    var fileList: [String] {
        files.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var isComplete: Bool {
        guard scope != .primaries || !repos.isEmpty else { return false }
        switch kind {
        case .command: return !events.isEmpty && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .paths: return !fileList.isEmpty
        }
    }

    func title(_ event: AutomationEvent) -> String {
        let text = event == .focus ? "ao focar (trocar de trama)" : event.label
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    func toggleFile(_ file: String) {
        var list = fileList
        if let i = list.firstIndex(of: file) { list.remove(at: i) } else { list.append(file) }
        files = list.joined(separator: ", ")
    }

    func load() {
        name = automation.name
        kind = automation.kind
        events = Set(automation.events.isEmpty ? [.focus] : automation.events)
        scope = automation.scope
        repos = Set(automation.repos)
        command = automation.command
        files = automation.files.joined(separator: ", ")
    }

    func save() {
        var updated = automation
        updated.name = name
        updated.kind = kind
        updated.events = AutomationEvent.allCases.filter { events.contains($0) }
        updated.scope = scope
        updated.repos = scope == .trama ? [] : model.repos.map(\.name).filter { repos.contains($0) }
        updated.command = kind == .command ? command : ""
        updated.files = kind == .paths ? fileList : []
        saving = true
        problem = nil
        Task {
            let result = await model.saveAutomation(updated)
            saving = false
            problem = result.problem
            if let saved = result.saved { finished(saved) }
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    var selected: Set<String> = []
    let tap: (String) -> Void

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    tap(item)
                } label: {
                    Text(item)
                        .font(Theme.mono(11))
                        .foregroundStyle(on ? Theme.emberText : Theme.text3)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(on ? Theme.ember.opacity(0.12) : Theme.surface))
                        .overlay(Capsule().stroke(on ? Theme.ember.opacity(0.45) : Theme.line2, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

struct AutomationsItem: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let selected = model.screen == .automations
        let count = (model.state?.automations ?? []).filter(\.enabled).count
        Button {
            model.screen = .automations
        } label: {
            HStack(spacing: 8) {
                SidebarIcon(name: "bolt")
                Text("Automações")
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
                if model.hasFailedAutomation {
                    Dot(color: Theme.danger, halo: true)
                        .help("Uma automação falhou · veja o log no cabeçalho da trama")
                }
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faded)
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .padding(.horizontal, 10)
            .frame(height: SidebarPreference.rowHeight)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color(hex: 0x2B2E36) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
