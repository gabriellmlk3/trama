import Foundation
import SwiftUI

private struct HunkEditing: Equatable {
    var id: Int
    var text: String
}

struct ConflictMergeView: View {
    let document: ConflictDocument
    let file: ConflictFile
    let oursName: String
    let theirsName: String
    let busy: Bool
    let onCancel: () -> Void
    let onApply: (String) -> Void

    @State private var resolutions: [Int: ConflictResolution] = [:]
    @State private var editing: HunkEditing?
    @State private var expanded: Set<Int> = []

    var hunks: [ConflictHunk] { document.hunks }
    var pending: [ConflictHunk] { hunks.filter { resolutions[$0.id] == nil } }
    var oursTitle: String { oursName.isEmpty ? "Sua versão" : "Sua versão · \(oursName)" }
    var theirsTitle: String { theirsName.isEmpty ? "Versão que chegou" : "Chegou de · \(theirsName)" }

    func number(_ h: ConflictHunk) -> Int { (hunks.firstIndex(where: { $0.id == h.id }) ?? 0) + 1 }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(proxy)
                columnTitles
                Divider().overlay(Theme.line)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(document.segments) { segment in
                            switch segment {
                            case .context(let id, let lines):
                                contextBlock(id, lines)
                            case .hunk(let h):
                                hunkRow(h, proxy)
                                    .id(h.id)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 1020, minHeight: 640)
        .background(Theme.background)
    }

    func header(_ proxy: ScrollViewProxy) -> some View {
        let done = hunks.count - pending.count
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                        .font(Theme.mono(13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(pending.isEmpty ? "tudo resolvido · aplique para gravar o arquivo" : "\(done) de \(hunks.count) \(plural(hunks.count, "conflito resolvido", "conflitos resolvidos"))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(pending.isEmpty ? Theme.okText : Theme.waitText)
                }
                Spacer(minLength: 8)
                Button {
                    jump(proxy, forward: false)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Conflito anterior")
                .disabled(hunks.count < 2)
                Button {
                    jump(proxy, forward: true)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Próximo conflito pendente")
                .disabled(pending.isEmpty)
                Divider().frame(height: 18).overlay(Theme.line2)
                Button("Todas minhas") { resolveAll(.ours) }
                    .buttonStyle(GhostButton(compact: true))
                Button("Todas deles") { resolveAll(.theirs) }
                    .buttonStyle(GhostButton(compact: true))
                Button("Cancelar", action: onCancel)
                    .buttonStyle(GhostButton(compact: true))
                    .keyboardShortcut(.cancelAction)
                Button("Aplicar") { apply() }
                    .buttonStyle(EmberButton(compact: true))
                    .disabled(!pending.isEmpty || busy)
                    .opacity(pending.isEmpty ? 1 : 0.4)
                    .keyboardShortcut(.defaultAction)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(pending.isEmpty ? Theme.ok : Theme.wait)
                        .frame(width: hunks.isEmpty ? 0 : geo.size.width * CGFloat(done) / CGFloat(hunks.count))
                        .animation(.easeOut(duration: 0.25), value: done)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    var columnTitles: some View {
        HStack(spacing: 12) {
            columnTitle(oursTitle, color: Theme.irisText, tint: Theme.iris)
            columnTitle("Resultado", color: Theme.text3, tint: Theme.faded)
            columnTitle(theirsTitle, color: Theme.emberLight, tint: Theme.ember)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    func columnTitle(_ text: String, color: Color, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func jump(_ proxy: ScrollViewProxy, forward: Bool) {
        let list = forward ? pending : hunks
        guard !list.isEmpty else { return }
        let target = forward ? list[0] : list[hunks.count - 1]
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target.id, anchor: .top) }
    }

    func resolveAll(_ r: ConflictResolution) {
        for h in hunks { resolutions[h.id] = r }
        editing = nil
    }

    func apply() {
        guard let content = try? document.render(resolutions) else { return }
        onApply(content)
    }

    func lines(_ lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty {
                Text("(vazio)")
                    .italic()
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.faded)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.1))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func contextBlock(_ id: Int, _ block: [String]) -> some View {
        let collapsible = block.count > 8 && !expanded.contains(id)
        let shown = collapsible ? Array(block.prefix(3)) + Array(block.suffix(3)) : block
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.prefix(collapsible ? 3 : shown.count).enumerated()), id: \.offset) { _, l in
                contextLine(l)
            }
            if collapsible {
                Button {
                    expanded.insert(id)
                } label: {
                    Label("\(block.count - 6) linhas iguais · mostrar", systemImage: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faded)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(Theme.surface)
                }
                .buttonStyle(.plain)
                ForEach(Array(shown.suffix(3).enumerated()), id: \.offset) { _, l in
                    contextLine(l)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func contextLine(_ l: String) -> some View {
        Text(l.isEmpty ? " " : l)
            .font(Theme.mono(11.5))
            .foregroundStyle(Theme.faded)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
    }

    func sideColumn(_ content: [String], tone: Color, label: String, icon: String, help: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            lines(content, tint: tone)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button(action: action) {
                Label(label, systemImage: icon)
            }
            .buttonStyle(ToneButton(color: tone, text: tone == Theme.iris ? Theme.irisText : Theme.emberLight))
            .help(help)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9).fill(tone.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tone.opacity(0.3), lineWidth: 1))
    }

    func hunkRow(_ h: ConflictHunk, _ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conflito \(number(h)) de \(hunks.count)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.faded)
                .textCase(.uppercase)
                .padding(.leading, 2)
            HStack(alignment: .top, spacing: 12) {
                sideColumn(h.ours, tone: Theme.iris, label: "Usar a minha", icon: "arrow.right", help: "Resolve com a sua versão") {
                    resolutions[h.id] = .ours
                    editing = nil
                }
                result(h)
                sideColumn(h.theirs, tone: Theme.ember, label: "Usar a deles", icon: "arrow.left", help: "Resolve com a versão que chegou") {
                    resolutions[h.id] = .theirs
                    editing = nil
                }
            }
        }
    }

    func resolutionName(_ r: ConflictResolution) -> String {
        switch r {
        case .ours: return "minha"
        case .theirs: return "deles"
        case .both: return "ambas"
        case .custom: return "editado"
        }
    }

    func result(_ h: ConflictHunk) -> some View {
        let resolution = resolutions[h.id]
        let isEditing = editing?.id == h.id
        return VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextEditor(text: Binding(get: { editing?.text ?? "" }, set: { editing?.text = $0 }))
                    .font(Theme.mono(11.5))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
                HStack(spacing: 8) {
                    Button("Cancelar") { editing = nil }
                        .buttonStyle(GhostButton(compact: true))
                    Button("Usar este texto") {
                        let text = editing?.text ?? ""
                        resolutions[h.id] = .custom(text.isEmpty ? [] : text.components(separatedBy: "\n"))
                        editing = nil
                    }
                    .buttonStyle(EmberButton(compact: true))
                }
            } else if let resolution {
                lines(resolution.lines(for: h), tint: Theme.ok)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 8) {
                    Chip(text: resolutionName(resolution), color: Theme.okText, background: Theme.ok.opacity(0.12))
                    Spacer(minLength: 4)
                    Button("Ambas") { resolutions[h.id] = .both }
                        .buttonStyle(GhostButton(compact: true))
                        .help("Sua versão seguida da que chegou")
                    Button("Editar") { startEditing(h, resolution) }
                        .buttonStyle(GhostButton(compact: true))
                    Button {
                        resolutions[h.id] = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(IconButton(size: 28))
                    .help("Desfazer a escolha")
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.waitText)
                    Text("Escolha um lado")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.waitText)
                    HStack(spacing: 8) {
                        Button("Ambas") { resolutions[h.id] = .both }
                            .buttonStyle(GhostButton(compact: true))
                            .help("Sua versão seguida da que chegou")
                        Button("Editar") { startEditing(h, nil) }
                            .buttonStyle(GhostButton(compact: true))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(resolution == nil ? Theme.wait.opacity(0.55) : Theme.ok.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: resolution == nil ? [4, 3] : []))
        )
    }

    func startEditing(_ h: ConflictHunk, _ resolution: ConflictResolution?) {
        let base = resolution?.lines(for: h) ?? (h.ours + h.theirs)
        editing = HunkEditing(id: h.id, text: base.joined(separator: "\n"))
    }
}
