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
    @State private var picks: [Int: ConflictPicks] = [:]
    @State private var declined: Set<Int> = []
    @State private var acceptedEmpty: Set<Int> = []
    @State private var editing: HunkEditing?
    @State private var expanded: Set<Int> = []

    private let lineHeight: CGFloat = 18
    private let gutterWidth: CGFloat = 44
    private let numberWidth: CGFloat = 36

    struct Offsets {
        var ours = 1
        var result = 1
        var theirs = 1
    }

    var hunks: [ConflictHunk] { document.hunks }
    var pending: [ConflictHunk] { hunks.filter { resolutions[$0.id] == nil } }
    var oursTitle: String { oursName.isEmpty ? "Sua versão" : "Sua versão · \(oursName)" }
    var theirsTitle: String { theirsName.isEmpty ? "Versão que chegou" : "Chegou de · \(theirsName)" }

    func number(_ h: ConflictHunk) -> Int { (hunks.firstIndex(where: { $0.id == h.id }) ?? 0) + 1 }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(proxy)
                GeometryReader { geo in
                    let pw = max(120, (geo.size.width - gutterWidth * 2) / 3)
                    VStack(spacing: 0) {
                        columnTitles(pw)
                        Divider().overlay(Theme.line)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                let offsets = offsets()
                                ForEach(document.segments) { segment in
                                    switch segment {
                                    case .context(let id, let lines):
                                        contextRows(id, lines, offsets[id] ?? Offsets(), pw)
                                            .id(id)
                                    case .hunk(let h):
                                        hunkRow(h, offsets[h.id] ?? Offsets(), pw)
                                            .id(h.id)
                                    }
                                }
                            }
                        }
                    }
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

    func columnTitles(_ pw: CGFloat) -> some View {
        HStack(spacing: 0) {
            columnTitle(oursTitle, color: Theme.irisText, tint: Theme.iris).frame(width: pw)
            Spacer().frame(width: gutterWidth)
            columnTitle("Resultado", color: Theme.text3, tint: Theme.faded).frame(width: pw)
            Spacer().frame(width: gutterWidth)
            columnTitle(theirsTitle, color: Theme.emberLight, tint: Theme.ember).frame(width: pw)
        }
        .padding(.vertical, 7)
        .background(Theme.surface)
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
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func jump(_ proxy: ScrollViewProxy, forward: Bool) {
        let list = forward ? pending : hunks
        guard !list.isEmpty else { return }
        let target = forward ? list[0] : list[list.count - 1]
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target.id, anchor: .center) }
    }

    func resolveAll(_ r: ConflictResolution) {
        for h in hunks { choose(h, r, picks: nil) }
    }

    func apply() {
        guard let content = try? document.render(resolutions) else { return }
        onApply(content)
    }

    private func offsets() -> [Int: Offsets] {
        var out: [Int: Offsets] = [:]
        var current = Offsets()
        for segment in document.segments {
            out[segment.id] = current
            switch segment {
            case .context(_, let lines):
                current.ours += lines.count
                current.result += lines.count
                current.theirs += lines.count
            case .hunk(let h):
                current.ours += h.ours.count
                current.theirs += h.theirs.count
                current.result += resolutions[h.id]?.lines(for: h).count ?? 0
            }
        }
        return out
    }

    func selection(_ h: ConflictHunk) -> ConflictPicks {
        if let p = picks[h.id] { return p }
        switch resolutions[h.id] {
        case .ours: return .all(h, ours: true, theirs: false)
        case .theirs: return .all(h, ours: false, theirs: true)
        case .both: return .all(h, ours: true, theirs: true)
        default: return ConflictPicks()
        }
    }

    func sideKey(_ h: ConflictHunk, _ ours: Bool) -> Int { h.id * 2 + (ours ? 0 : 1) }

    func choose(_ h: ConflictHunk, _ resolution: ConflictResolution?, picks newPicks: ConflictPicks?) {
        resolutions[h.id] = resolution
        picks[h.id] = newPicks
        editing = nil
        for ours in [true, false] {
            declined.remove(sideKey(h, ours))
            acceptedEmpty.remove(sideKey(h, ours))
        }
        guard newPicks == nil, let resolution else { return }
        let uses: (ours: Bool, theirs: Bool)
        switch resolution {
        case .ours: uses = (true, false)
        case .theirs: uses = (false, true)
        case .both: uses = (true, true)
        case .custom: return
        }
        for (ours, used) in [(true, uses.ours), (false, uses.theirs)] {
            if !used { declined.insert(sideKey(h, ours)) }
            else if (ours ? h.ours : h.theirs).isEmpty { acceptedEmpty.insert(sideKey(h, ours)) }
        }
    }

    func settle(_ h: ConflictHunk, _ s: ConflictPicks) {
        picks[h.id] = s
        if !s.ours.isEmpty { declined.remove(sideKey(h, true)) }
        if !s.theirs.isEmpty { declined.remove(sideKey(h, false)) }
        editing = nil
        func decided(_ ours: Bool) -> Bool {
            declined.contains(sideKey(h, ours)) || acceptedEmpty.contains(sideKey(h, ours)) || !(ours ? s.ours : s.theirs).isEmpty
        }
        guard decided(true), decided(false) else {
            resolutions[h.id] = nil
            return
        }
        if s.isEmpty {
            if acceptedEmpty.contains(sideKey(h, true)) { resolutions[h.id] = .ours }
            else if acceptedEmpty.contains(sideKey(h, false)) { resolutions[h.id] = .theirs }
            else { resolutions[h.id] = .custom([]) }
        } else {
            resolutions[h.id] = s.resolution(for: h)
        }
    }

    func toggle(_ h: ConflictHunk, index: Int, ours: Bool) {
        var s = selection(h)
        if ours {
            if !s.ours.insert(index).inserted { s.ours.remove(index) }
        } else {
            if !s.theirs.insert(index).inserted { s.theirs.remove(index) }
        }
        settle(h, s)
    }

    func includes(_ h: ConflictHunk, ours: Bool) -> Bool {
        let content = ours ? h.ours : h.theirs
        if content.isEmpty { return acceptedEmpty.contains(sideKey(h, ours)) }
        let s = selection(h)
        return (ours ? s.ours : s.theirs) == Set(content.indices)
    }

    func isDeclined(_ h: ConflictHunk, ours: Bool) -> Bool { declined.contains(sideKey(h, ours)) }

    func toggleSide(_ h: ConflictHunk, ours: Bool) {
        let content = ours ? h.ours : h.theirs
        let on = includes(h, ours: ours)
        let key = sideKey(h, ours)
        var s = selection(h)
        if content.isEmpty {
            if on { acceptedEmpty.remove(key) } else {
                acceptedEmpty.insert(key)
                declined.remove(key)
            }
        } else {
            let all = Set(content.indices)
            if ours { s.ours = on ? [] : all } else { s.theirs = on ? [] : all }
        }
        settle(h, s)
    }

    func toggleDecline(_ h: ConflictHunk, ours: Bool) {
        let key = sideKey(h, ours)
        var s = selection(h)
        if declined.contains(key) {
            declined.remove(key)
        } else {
            declined.insert(key)
            acceptedEmpty.remove(key)
            if ours { s.ours = [] } else { s.theirs = [] }
        }
        settle(h, s)
    }

    func startEditing(_ h: ConflictHunk, _ resolution: ConflictResolution?) {
        let base = resolution?.lines(for: h) ?? (h.ours + h.theirs)
        editing = HunkEditing(id: h.id, text: base.joined(separator: "\n"))
    }

    func codeLine(_ number: Int?, _ text: String, tint: Color?, strong: Bool = false, textColor: Color = Theme.text2) -> some View {
        HStack(spacing: 0) {
            Text(number.map(String.init) ?? "")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.faded)
                .frame(width: numberWidth, alignment: .trailing)
                .padding(.trailing, 8)
            Text(text.isEmpty ? " " : text)
                .font(Theme.mono(11.5))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
        }
        .frame(height: lineHeight)
        .background((tint ?? .clear).opacity(strong ? 0.34 : 0.16))
        .clipped()
    }

    func plainPane(_ lines: [String], start: Int, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                codeLine(start + i, l, tint: nil, textColor: Theme.text3)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .clipped()
    }

    func contextRows(_ id: Int, _ block: [String], _ off: Offsets, _ pw: CGFloat) -> some View {
        let collapsible = block.count > 8 && !expanded.contains(id)
        return VStack(alignment: .leading, spacing: 0) {
            if collapsible {
                contextTriple(Array(block.prefix(3)), off, 0, pw)
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
                contextTriple(Array(block.suffix(3)), off, block.count - 3, pw)
            } else {
                contextTriple(block, off, 0, pw)
            }
        }
    }

    func contextTriple(_ lines: [String], _ off: Offsets, _ delta: Int, _ pw: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            plainPane(lines, start: off.ours + delta, width: pw)
            Theme.surface.frame(width: gutterWidth)
            plainPane(lines, start: off.result + delta, width: pw)
            Theme.surface.frame(width: gutterWidth)
            plainPane(lines, start: off.theirs + delta, width: pw)
        }
    }

    func sidePane(_ h: ConflictHunk, ours: Bool, start: Int, width: CGFloat, height: CGFloat) -> some View {
        let tone = ours ? Theme.iris : Theme.ember
        let content = ours ? h.ours : h.theirs
        let selected = ours ? selection(h).ours : selection(h).theirs
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(content.enumerated()), id: \.offset) { index, line in
                let on = selected.contains(index)
                Button {
                    toggle(h, index: index, ours: ours)
                } label: {
                    codeLine(start + index, line, tint: tone, strong: on, textColor: on ? Theme.text : Theme.text2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(on ? "Tirar esta linha do resultado" : "Colocar esta linha no resultado")
            }
            if content.isEmpty {
                Text(ours ? "(removido aqui)" : "(removido lá)")
                    .italic()
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faded)
                    .padding(.leading, numberWidth + 8)
                    .frame(height: lineHeight)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
    }

    func gutter(_ h: ConflictHunk, ours: Bool, leftCount: Int, rightCount: Int, height: CGFloat) -> some View {
        let tone = ours ? Theme.iris : Theme.ember
        let active = includes(h, ours: ours)
        let rejected = isDeclined(h, ours: ours)
        return Canvas { ctx, size in
            let leftH = max(CGFloat(leftCount) * lineHeight, 2)
            let rightH = max(CGFloat(rightCount) * lineHeight, 2)
            var fill = Path()
            fill.move(to: CGPoint(x: 0, y: 0))
            fill.addLine(to: CGPoint(x: size.width, y: 0))
            fill.addLine(to: CGPoint(x: size.width, y: rightH))
            fill.addCurve(to: CGPoint(x: 0, y: leftH), control1: CGPoint(x: size.width / 2, y: rightH), control2: CGPoint(x: size.width / 2, y: leftH))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(tone.opacity(0.2)))
            var bottom = Path()
            bottom.move(to: CGPoint(x: size.width, y: rightH))
            bottom.addCurve(to: CGPoint(x: 0, y: leftH), control1: CGPoint(x: size.width / 2, y: rightH), control2: CGPoint(x: size.width / 2, y: leftH))
            ctx.stroke(bottom, with: .color(tone.opacity(0.6)), lineWidth: 1)
            var top = Path()
            top.move(to: CGPoint(x: 0, y: 0.5))
            top.addLine(to: CGPoint(x: size.width, y: 0.5))
            ctx.stroke(top, with: .color(tone.opacity(0.6)), lineWidth: 1)
        }
        .frame(width: gutterWidth, height: height)
        .background(Theme.surface)
        .overlay(alignment: ours ? .topLeading : .topTrailing) {
            let use = Button {
                toggleSide(h, ours: ours)
            } label: {
                Image(systemName: ours ? "chevron.right.2" : "chevron.left.2")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(active ? Theme.background : tone)
                    .frame(width: 18, height: 16)
                    .background(RoundedRectangle(cornerRadius: 4).fill(active ? tone : Theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(tone.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(ours ? "Usar a sua versão no resultado" : "Usar a versão que chegou no resultado")
            let skip = Button {
                toggleDecline(h, ours: ours)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(rejected ? Theme.background : Theme.dangerText)
                    .frame(width: 18, height: 16)
                    .background(RoundedRectangle(cornerRadius: 4).fill(rejected ? Theme.danger : Theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.danger.opacity(0.7), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(ours ? "Não usar a sua versão" : "Não usar a versão que chegou")
            HStack(spacing: 2) {
                if ours { use; skip } else { skip; use }
            }
            .padding(.horizontal, 2)
            .padding(.top, 1)
        }
    }

    func resultPane(_ h: ConflictHunk, start: Int, width: CGFloat, height: CGFloat) -> some View {
        let resolution = resolutions[h.id]
        let isEditing = editing?.id == h.id
        return Group {
            if isEditing {
                VStack(spacing: 4) {
                    TextEditor(text: Binding(get: { editing?.text ?? "" }, set: { editing?.text = $0 }))
                        .font(Theme.mono(11.5))
                        .scrollContentBackground(.hidden)
                        .padding(2)
                        .background(Theme.field)
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Button("Cancelar") { editing = nil }
                            .buttonStyle(GhostButton(compact: true))
                        Button("Usar este texto") {
                            let text = editing?.text ?? ""
                            choose(h, .custom(text.isEmpty ? [] : text.components(separatedBy: "\n")), picks: nil)
                        }
                        .buttonStyle(EmberButton(compact: true))
                    }
                    .frame(height: 26)
                }
                .padding(4)
            } else if let resolution {
                let lines = resolution.lines(for: h)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                        codeLine(start + i, l, tint: Theme.ok, textColor: Theme.text)
                    }
                    if lines.isEmpty {
                        Text("(nada neste trecho)")
                            .italic()
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.faded)
                            .padding(.leading, numberWidth + 8)
                            .frame(height: lineHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        Button { startEditing(h, resolution) } label: { Image(systemName: "pencil") }
                            .buttonStyle(IconButton(size: 20))
                            .help("Editar o texto deste trecho")
                        Button { choose(h, nil, picks: nil) } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(IconButton(size: 20))
                            .help("Desfazer a escolha")
                    }
                    .padding(2)
                }
            } else {
                VStack(spacing: 6) {
                    Text("Conflito \(number(h)) de \(hunks.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.waitText)
                    Text("em cada lado, use » « ou recuse com ✕")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.faded)
                    HStack(spacing: 6) {
                        Button("Ambas") { choose(h, .both, picks: nil) }
                            .buttonStyle(GhostButton(compact: true))
                            .help("Sua versão seguida da que chegou")
                        Button("Editar") { startEditing(h, nil) }
                            .buttonStyle(GhostButton(compact: true))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.wait.opacity(0.06))
                .overlay(Rectangle().stroke(Theme.wait.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
    }

    func hunkRow(_ h: ConflictHunk, _ off: Offsets, _ pw: CGFloat) -> some View {
        let resolution = resolutions[h.id]
        let resultCount = resolution?.lines(for: h).count ?? 0
        let isEditing = editing?.id == h.id
        let minimum = (resolution == nil ? 4 : 1)
        let rows = max(h.ours.count, h.theirs.count, resultCount, minimum, isEditing ? 7 : 0)
        let height = CGFloat(rows) * lineHeight + (isEditing ? 34 : 0)
        return HStack(alignment: .top, spacing: 0) {
            sidePane(h, ours: true, start: off.ours, width: pw, height: height)
            gutter(h, ours: true, leftCount: h.ours.count, rightCount: resultCount, height: height)
            resultPane(h, start: off.result, width: pw, height: height)
            gutter(h, ours: false, leftCount: resultCount, rightCount: h.theirs.count, height: height)
            sidePane(h, ours: false, start: off.theirs, width: pw, height: height)
        }
        .padding(.vertical, 6)
    }
}
