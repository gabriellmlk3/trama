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
    var restored: [Int: ConflictResolution] = [:]
    var origins: [Int: ConflictOrigins] = [:]
    var onDraft: ([Int: ConflictResolution]) -> Void = { _ in }
    var onSuggest: ((ConflictHunk) async throws -> [String])?
    let onApply: (String) -> Void

    @State private var resolutions: [Int: ConflictResolution] = [:]
    @State private var picks: [Int: ConflictPicks] = [:]
    @State private var declined: Set<Int> = []
    @State private var acceptedEmpty: Set<Int> = []
    @State private var editing: HunkEditing?
    @State private var expanded: Set<Int> = []
    @State private var horizontalOffset: CGFloat = 0
    @State private var longestLine = 0
    @State private var current: Int?
    @State private var scrollRequest = ScrollRequest(id: 0, token: 0)
    @State private var undoStack: [Snapshot] = []
    @State private var redoStack: [Snapshot] = []
    @State private var generated: Set<Int> = []
    @State private var suggesting: Set<Int> = []
    @State private var baseShown: Int?
    @State private var note: String?
    @State private var problem: String?
    @State private var warningText = ""
    @State private var confirmingWarnings = false
    @State private var loadedDraft = false

    private let lineHeight: CGFloat = 18
    private let gutterWidth: CGFloat = 44
    private let numberWidth: CGFloat = 36
    private let characterWidth: CGFloat = 7
    private let pendingRows = 8

    struct ScrollRequest: Equatable {
        var id: Int
        var token: Int
    }

    struct Snapshot {
        var resolutions: [Int: ConflictResolution]
        var picks: [Int: ConflictPicks]
        var declined: Set<Int>
        var acceptedEmpty: Set<Int>
        var generated: Set<Int>
    }

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

    var currentHunk: ConflictHunk? {
        hunks.first { $0.id == current } ?? pending.first ?? hunks.first
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    let pw = max(120, (geo.size.width - gutterWidth * 2) / 3)
                    let limit = maxScroll(pw)
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
                        .background(HorizontalScrollMonitor { dx in
                            horizontalOffset = min(max(0, horizontalOffset + dx), maxScroll(pw))
                        })
                        if limit > 0 {
                            scroller(limit)
                        }
                    }
                }
            }
            .onChange(of: scrollRequest) { _, request in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(request.id, anchor: .center) }
            }
        }
        .frame(minWidth: 1020, minHeight: 640)
        .background(Theme.background)
        .background(shortcuts)
        .onAppear(perform: start)
        .onChange(of: resolutions) { _, value in onDraft(value) }
        .appDialog(
            "Conferir antes de aplicar",
            isPresented: $confirmingWarnings,
            message: warningText,
            actions: [DialogAction("Aplicar mesmo assim") { commit() }]
        )
    }

    func start() {
        longestLine = document.segments.reduce(0) { best, segment in
            switch segment {
            case .context(_, let lines): return max(best, lines.map(\.count).max() ?? 0)
            case .hunk(let h): return max(best, (h.ours + h.theirs).map(\.count).max() ?? 0)
            }
        }
        guard !loadedDraft else { return }
        loadedDraft = true
        current = pending.first?.id
        let valid = restored.filter { entry in hunks.contains { $0.id == entry.key } }
        guard !valid.isEmpty else { return }
        for h in hunks {
            if let r = valid[h.id] { applyChoice(h, r, picks: nil) }
        }
        note = "\(valid.count) \(plural(valid.count, "escolha restaurada", "escolhas restauradas")) do rascunho"
    }

    func maxScroll(_ pw: CGFloat) -> CGFloat {
        let textWidth = max(0, pw - numberWidth - 8)
        return max(0, CGFloat(longestLine) * characterWidth + 16 - textWidth)
    }

    func scroller(_ limit: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faded)
            Slider(value: Binding(get: { min(horizontalOffset, limit) }, set: { horizontalOffset = $0 }), in: 0...limit)
                .controlSize(.mini)
            Text("linhas longas · role com ⇧ + roda ou arraste")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.faded)
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Theme.surface)
    }

    var shortcuts: some View {
        Group {
            Button("Desfazer", action: undo)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoStack.isEmpty || editing != nil)
            Button("Refazer", action: redo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(redoStack.isEmpty || editing != nil)
            Button("Próximo conflito") { move(forward: true) }
                .keyboardShortcut(.downArrow, modifiers: .option)
            Button("Conflito anterior") { move(forward: false) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("Usar a minha") { chooseCurrent(.ours) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(editing != nil)
            Button("Usar a dele") { chooseCurrent(.theirs) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(editing != nil)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var header: some View {
        let done = hunks.count - pending.count
        let position = currentHunk.map(number)
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                        .font(Theme.mono(13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(done: done, position: position))
                        .font(.system(size: 11.5))
                        .foregroundStyle(problem != nil ? Theme.dangerText : (pending.isEmpty ? Theme.okText : Theme.waitText))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Desfazer (⌘Z)")
                .disabled(undoStack.isEmpty)
                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Refazer (⇧⌘Z)")
                .disabled(redoStack.isEmpty)
                Divider().frame(height: 18).overlay(Theme.line2)
                Button {
                    move(forward: false)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Conflito anterior (⌥↑)")
                .disabled(hunks.count < 2)
                Button {
                    move(forward: true)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Próximo conflito (⌥↓)")
                .disabled(hunks.count < 2)
                Divider().frame(height: 18).overlay(Theme.line2)
                batchMenu
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
            if let hint = file.generatedHint {
                Label(hint, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faded)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    func subtitle(done: Int, position: Int?) -> String {
        if let problem { return problem }
        if let note, pending.isEmpty == false { return note }
        if pending.isEmpty {
            let summary = document.summary(resolutions)
            return "tudo resolvido\(summary.isEmpty ? "" : " (\(summary))") · aplique para gravar o arquivo"
        }
        let base = "\(done) de \(hunks.count) \(plural(hunks.count, "conflito resolvido", "conflitos resolvidos"))"
        guard let position, hunks.count > 1 else { return base }
        return "\(base) · em foco: conflito \(position) de \(hunks.count)"
    }

    func focus(_ h: ConflictHunk) {
        current = h.id
        scrollRequest = ScrollRequest(id: h.id, token: scrollRequest.token + 1)
    }

    func move(forward: Bool) {
        guard !hunks.isEmpty else { return }
        let index = currentHunk.flatMap { h in hunks.firstIndex { $0.id == h.id } } ?? 0
        if forward {
            let ordered = Array(hunks[(index + 1)...]) + Array(hunks[..<(index + 1)])
            focus(ordered.first { resolutions[$0.id] == nil } ?? ordered[0])
        } else {
            focus(hunks[(index - 1 + hunks.count) % hunks.count])
        }
    }

    func chooseCurrent(_ r: ConflictResolution) {
        guard let h = currentHunk else { return }
        choose(h, r, picks: nil)
        if let next = pending.first(where: { $0.id != h.id }) { focus(next) }
    }

    func snapshot() -> Snapshot {
        Snapshot(resolutions: resolutions, picks: picks, declined: declined, acceptedEmpty: acceptedEmpty, generated: generated)
    }

    func record() {
        undoStack.append(snapshot())
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        note = nil
        problem = nil
    }

    func restore(_ s: Snapshot) {
        resolutions = s.resolutions
        picks = s.picks
        declined = s.declined
        acceptedEmpty = s.acceptedEmpty
        generated = s.generated
        editing = nil
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(s)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(s)
    }

    func resolveAll(_ r: ConflictResolution) {
        record()
        for h in hunks { applyChoice(h, r, picks: nil) }
    }

    func hintCount(_ kinds: Set<ConflictHint.Kind>) -> Int {
        pending.filter { h in h.hint.map { kinds.contains($0.kind) } ?? false }.count
    }

    func applyHints(_ kinds: Set<ConflictHint.Kind>) {
        record()
        for h in pending {
            if let hint = h.hint, kinds.contains(hint.kind) { applyChoice(h, hint.resolution, picks: nil) }
        }
        if let next = pending.first { focus(next) }
    }

    var batchMenu: some View {
        let all: Set<ConflictHint.Kind> = [.identical, .spacing, .oursOnly, .theirsOnly, .bothAdded]
        return Menu {
            Button("Aplicar todas as sugestões (\(hintCount(all)))") { applyHints(all) }
                .disabled(hintCount(all) == 0)
            Divider()
            Button("Lados iguais ou só de espaços (\(hintCount([.identical, .spacing])))") { applyHints([.identical, .spacing]) }
                .disabled(hintCount([.identical, .spacing]) == 0)
            Button("Só um lado mudou desde a base (\(hintCount([.oursOnly, .theirsOnly])))") { applyHints([.oursOnly, .theirsOnly]) }
                .disabled(hintCount([.oursOnly, .theirsOnly]) == 0)
            Button("Os dois acrescentaram linhas: manter as duas (\(hintCount([.bothAdded])))") { applyHints([.bothAdded]) }
                .disabled(hintCount([.bothAdded]) == 0)
            if onSuggest != nil {
                Divider()
                Button("Pedir ao Claude para resolver os pendentes (\(pending.count))") { suggestAll() }
                    .disabled(pending.isEmpty || !suggesting.isEmpty)
            }
        } label: {
            Label("Resolver em lote", systemImage: "wand.and.stars")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Aplica de uma vez as sugestões que dispensam julgamento")
    }

    func suggest(_ h: ConflictHunk) {
        guard let onSuggest, suggesting.insert(h.id).inserted else { return }
        Task {
            defer { suggesting.remove(h.id) }
            do {
                let lines = try await onSuggest(h)
                choose(h, .custom(lines), picks: nil)
                generated.insert(h.id)
            } catch {
                problem = errorMessage(error)
            }
        }
    }

    func suggestAll() {
        for h in pending { suggest(h) }
    }

    func apply() {
        guard pending.isEmpty else { return }
        let found = document.warnings(resolutions)
        if found.isEmpty {
            commit()
        } else {
            warningText = found.map { "• " + $0 }.joined(separator: "\n")
            confirmingWarnings = true
        }
    }

    func commit() {
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
        case .both, .bothReversed: return .all(h, ours: true, theirs: true)
        default: return ConflictPicks()
        }
    }

    func sideKey(_ h: ConflictHunk, _ ours: Bool) -> Int { h.id * 2 + (ours ? 0 : 1) }

    func choose(_ h: ConflictHunk, _ resolution: ConflictResolution?, picks newPicks: ConflictPicks?) {
        record()
        applyChoice(h, resolution, picks: newPicks)
    }

    func applyChoice(_ h: ConflictHunk, _ resolution: ConflictResolution?, picks newPicks: ConflictPicks?) {
        resolutions[h.id] = resolution
        picks[h.id] = newPicks
        generated.remove(h.id)
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
        case .both, .bothReversed: uses = (true, true)
        case .custom: return
        }
        for (ours, used) in [(true, uses.ours), (false, uses.theirs)] {
            if !used { declined.insert(sideKey(h, ours)) }
            else if (ours ? h.ours : h.theirs).isEmpty { acceptedEmpty.insert(sideKey(h, ours)) }
        }
    }

    func settle(_ h: ConflictHunk, _ s: ConflictPicks) {
        picks[h.id] = s
        generated.remove(h.id)
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
        record()
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
        record()
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
        record()
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

    func lineText(_ line: String, changed: Range<Int>?, spacing: Bool, tint: Color?) -> Text {
        var attributed = AttributedString(line.isEmpty ? " " : line)
        if let changed, let tint, !line.isEmpty {
            let chars = attributed.characters
            if changed.lowerBound < changed.upperBound, changed.upperBound <= chars.count {
                let from = chars.index(chars.startIndex, offsetBy: changed.lowerBound)
                let to = chars.index(chars.startIndex, offsetBy: changed.upperBound)
                attributed[from..<to].backgroundColor = tint.opacity(0.45)
            }
        }
        if spacing {
            var tag = AttributedString("  só espaço")
            tag.foregroundColor = Theme.faded
            tag.font = .system(size: 10, design: .monospaced).italic()
            attributed.append(tag)
        }
        return Text(attributed)
    }

    func codeColumns(_ lines: [String], start: Int, width: CGFloat, tint: Color?, strong: @escaping (Int) -> Bool = { _ in false }, textColor: @escaping (Int) -> Color = { _ in Theme.text2 }, changes: [Int: Range<Int>] = [:], spacing: Set<Int> = [], help: @escaping (Int) -> String = { _ in "" }, action: ((Int) -> Void)? = nil) -> some View {
        let textWidth = max(0, width - numberWidth - 8)
        func cell<C: View>(_ i: Int, _ content: C) -> some View {
            Group {
                if let action {
                    Button { action(i) } label: { content.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .help(help(i))
                } else {
                    content
                }
            }
        }
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(lines.indices, id: \.self) { i in
                    cell(i, Text(String(start + i))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.faded)
                        .frame(width: numberWidth, alignment: .trailing)
                        .padding(.trailing, 8)
                        .frame(height: lineHeight)
                        .background((tint ?? .clear).opacity(strong(i) ? 0.34 : 0.16)))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { i in
                    cell(i, ZStack(alignment: .leading) {
                        (tint ?? .clear).opacity(strong(i) ? 0.34 : 0.16)
                        lineText(lines[i], changed: changes[i], spacing: spacing.contains(i), tint: tint)
                            .font(Theme.mono(11.5))
                            .foregroundStyle(textColor(i))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(x: -horizontalOffset)
                    }
                    .frame(width: textWidth, height: lineHeight, alignment: .leading)
                    .clipped())
                }
            }
            .frame(width: textWidth)
        }
    }

    func plainPane(_ lines: [String], start: Int, width: CGFloat) -> some View {
        codeColumns(lines, start: start, width: width, tint: nil, textColor: { _ in Theme.text3 })
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

    func sidePane(_ h: ConflictHunk, ours: Bool, start: Int, width: CGFloat, height: CGFloat, inline: InlineChanges) -> some View {
        let tone = ours ? Theme.iris : Theme.ember
        let content = ours ? h.ours : h.theirs
        let selected = ours ? selection(h).ours : selection(h).theirs
        return VStack(alignment: .leading, spacing: 0) {
            codeColumns(content, start: start, width: width, tint: tone,
                        strong: { selected.contains($0) },
                        textColor: { selected.contains($0) ? Theme.text : Theme.text2 },
                        changes: ours ? inline.ours : inline.theirs,
                        spacing: ours ? inline.spacingOurs : inline.spacingTheirs,
                        help: { selected.contains($0) ? "Tirar esta linha do resultado" : "Colocar esta linha no resultado" },
                        action: { toggle(h, index: $0, ours: ours) })
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

    func originLine(_ title: String, _ origin: ConflictOrigin?, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(origin.map { "\(title): \($0.hash) · \($0.subject)" } ?? "\(title): —")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faded)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(origin?.label ?? "")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func pendingPane(_ h: ConflictHunk) -> some View {
        let hint = h.hint
        let origin = origins[h.id]
        return VStack(spacing: 5) {
            Text("Conflito \(number(h)) de \(hunks.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.waitText)
            if let hint {
                Text("Sugestão: \(hint.action) — \(hint.reason)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text("em cada lado, use » « ou recuse com ✕")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faded)
            }
            if let origin {
                VStack(spacing: 1) {
                    originLine("sua", origin.ours, tint: Theme.iris)
                    originLine("deles", origin.theirs, tint: Theme.ember)
                }
                .padding(.horizontal, 8)
            }
            HStack(spacing: 6) {
                if let hint {
                    Button("Aceitar sugestão") { choose(h, hint.resolution, picks: nil) }
                        .buttonStyle(EmberButton(compact: true))
                }
                Menu {
                    Button("Minha, depois a deles") { choose(h, .both, picks: nil) }
                    Button("Deles, depois a minha") { choose(h, .bothReversed, picks: nil) }
                } label: {
                    Text("Ambas")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Mantém as duas versões; escolha qual vem primeiro")
                Button("Editar") { startEditing(h, nil) }
                    .buttonStyle(GhostButton(compact: true))
            }
            HStack(spacing: 6) {
                if let base = h.base {
                    Button("Base") { baseShown = h.id }
                        .buttonStyle(GhostButton(compact: true))
                        .help("Mostra o ancestral comum deste trecho")
                        .popover(isPresented: Binding(get: { baseShown == h.id }, set: { if !$0 { baseShown = nil } }), arrowEdge: .bottom) {
                            basePopover(base)
                        }
                }
                if onSuggest != nil {
                    Button {
                        suggest(h)
                    } label: {
                        if suggesting.contains(h.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Claude", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(GhostButton(compact: true))
                    .disabled(suggesting.contains(h.id))
                    .help("Pede ao Claude uma resolução para revisar")
                }
            }
        }
    }

    func basePopover(_ base: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Base · ancestral comum", systemImage: "arrow.triangle.branch")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.text2)
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    if base.isEmpty {
                        Text("(nada aqui: os dois lados acrescentaram este trecho)")
                            .italic()
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.faded)
                    }
                    ForEach(base.indices, id: \.self) { i in
                        Text(base[i].isEmpty ? " " : base[i])
                            .font(Theme.mono(11.5))
                            .foregroundStyle(Theme.text)
                            .fixedSize()
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 480, height: min(CGFloat(max(base.count, 1)) * lineHeight + 20, 280))
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
        }
        .padding(12)
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
                    codeColumns(lines, start: start, width: width, tint: Theme.ok, textColor: { _ in Theme.text })
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
                .overlay(alignment: .bottomTrailing) {
                    if generated.contains(h.id) {
                        Label("sugerido pelo Claude · revise", systemImage: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.waitText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.surface2))
                            .padding(4)
                    }
                }
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
                pendingPane(h)
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
        let minimum = (resolution == nil ? pendingRows : 1)
        let rows = max(h.ours.count, h.theirs.count, resultCount, minimum, isEditing ? 7 : 0)
        let height = CGFloat(rows) * lineHeight + (isEditing ? 34 : 0)
        let inline = InlineDiff.changes(ours: h.ours, theirs: h.theirs)
        return HStack(alignment: .top, spacing: 0) {
            sidePane(h, ours: true, start: off.ours, width: pw, height: height, inline: inline)
            gutter(h, ours: true, leftCount: h.ours.count, rightCount: resultCount, height: height)
            resultPane(h, start: off.result, width: pw, height: height)
            gutter(h, ours: false, leftCount: resultCount, rightCount: h.theirs.count, height: height)
            sidePane(h, ours: false, start: off.theirs, width: pw, height: height, inline: inline)
        }
        .padding(.vertical, 6)
        .overlay {
            if current == h.id, hunks.count > 1 {
                Rectangle()
                    .stroke(Theme.ember.opacity(0.55), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { current = h.id }
    }
}
