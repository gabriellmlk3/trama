import Foundation
import SwiftUI

struct FindingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter: String?
    @State private var scanning = false

    var groups: [String] { Finding.groups }

    var filtered: [Finding] {
        guard let filter else { return model.findings }
        return model.findings.filter { $0.group == filter }
    }

    var scanLine: String {
        let n = model.repos.count
        var when = "ainda não varrido"
        if let at = model.findingsAt {
            when = "última " + relativeTime(Int64(at.timeIntervalSince1970))
        }
        return "varredura · \(n) \(plural(n, "repositório", "repositórios")) · \(when)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(scanLine)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.faded)
                    Text("Achados & perdidos")
                        .font(Theme.serif(42))
                    Text("O que ficou pelo caminho entre tramas, agentes e repositórios, antes que vire trabalho perdido.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text3)
                }
                Spacer()
                Button {
                    scan()
                } label: {
                    HStack(spacing: 8) {
                        if scanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Varrer agora")
                    }
                }
                .buttonStyle(GhostButton())
                .disabled(scanning)
            }

            TipCard(tips: [.findings])

            HStack(spacing: 8) {
                FilterChip(title: "Tudo", count: model.findings.count, active: filter == nil) { filter = nil }
                ForEach(groups, id: \.self) { g in
                    let n = model.findings.filter { $0.group == g }.count
                    if n > 0 {
                        FilterChip(title: g, count: n, active: filter == g) { filter = g }
                    }
                }
            }

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.okText)
                    Text("Nada perdido por aqui.")
                        .font(Theme.serif(24))
                    Text("Mudanças soltas, commits só locais, branches órfãs e handoffs sem resposta aparecem aqui.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.faded)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { a in
                            FindingRow(finding: a)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.refreshFindings()
        }
    }

    func scan() {
        scanning = true
        Task {
            await model.refreshFindings()
            scanning = false
        }
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                Text("\(count)")
                    .font(Theme.mono(11))
                    .foregroundStyle(active ? Theme.background : Theme.faded)
            }
            .font(.system(size: 12.5, weight: active ? .medium : .regular))
            .foregroundStyle(active ? Theme.background : Theme.text3)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(active ? Theme.text : Color.clear))
            .overlay(Capsule().stroke(active ? Theme.text : Theme.line2, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

struct FindingRow: View {
    @EnvironmentObject var model: AppModel
    let finding: Finding
    @State private var expanded = false

    var highlighted: Bool {
        finding.type == FindingType.editOnBase && finding.resolvable
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            if expanded {
                FindingDiffView(finding: finding)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(highlighted ? Color(hex: 0x14110F) : Color(hex: 0x111217)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlighted ? Theme.ember.opacity(0.35) : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var summary: some View {
        HStack(spacing: 18) {
            Image(systemName: finding.symbol)
                .font(.system(size: 14))
                .foregroundStyle(highlighted ? Theme.emberLight : Theme.text3)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface2))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line2, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(finding.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)
                    Text(finding.typeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0x9A9EA8))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(Theme.line))
                }
                Text(detailLine)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if let s = finding.suggestion, !s.isEmpty {
                    Text(s)
                }
                if let items = finding.items, !items.isEmpty {
                    Text(items.joined(separator: ", "))
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text3)
            .frame(width: 320, alignment: .leading)

            HStack(spacing: 8) {
                actions
                if finding.hasDiff {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .buttonStyle(IconButton(size: 28))
                    .help(expanded ? "Ocultar as diferenças" : "Ver as diferenças")
                    .accessibilityLabel(expanded ? "Ocultar as diferenças" : "Ver as diferenças")
                }
            }
            .frame(width: 290, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    var detailLine: String {
        var parts = [finding.detail]
        if let q = finding.timestamp, q > 0 { parts.append(relativeTime(q)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder var actions: some View {
        switch finding.type {
        case FindingType.editOnBase, FindingType.forgottenChange:
            if finding.resolvable {
                Button("Mover para a trama") {
                    Task { await model.resolve(finding) }
                }
                .buttonStyle(EmberButton(compact: true))
            }
            if let c = finding.path {
                Button("Abrir") {
                    model.terminals.open(path: c, command: nil, title: finding.repo ?? finding.title)
                }
                .buttonStyle(GhostButton(compact: true))
            }
        case FindingType.merged:
            if finding.resolvable {
                Button("Limpar \(finding.count ?? 0)") {
                    Task { await model.resolve(finding) }
                }
                .buttonStyle(GhostButton(compact: true))
            }
        case FindingType.staleParked:
            if let slug = finding.trama, let t = model.visibleTramas.first(where: { $0.slug == slug }) {
                Button("Retomar…") { model.resuming = t }
                    .buttonStyle(GhostButton(compact: true))
            }
        case FindingType.pendingHandoff:
            if let slug = finding.trama {
                Button("Ver na trama") { model.select(slug) }
                    .buttonStyle(GhostButton(compact: true))
            }
        default:
            if let repo = finding.repo, let r = model.repo(repo) {
                Button("Abrir no Terminal") {
                    model.terminals.open(path: finding.path ?? r.path, command: nil, title: repo)
                }
                .buttonStyle(GhostButton(compact: true))
            }
        }
        if let cmd = finding.command, !finding.resolvable, !cmd.hasPrefix("trama retomar") {
            Button {
                Terminal.copy(cmd)
                model.showNotice("Comando copiado")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(IconButton(size: 28))
            .help("Copiar: \(cmd)")
            .accessibilityLabel("Copiar comando")
        }
    }
}

struct FindingDiffView: View {
    let finding: Finding
    @State private var result: FindingChanges?
    @State private var error: String?
    @State private var selectedFile: String?
    @State private var diff: [DiffLine] = []
    @State private var diffFile: String?

    var selected: FileChange? { result?.changes.first(where: { $0.id == selectedFile }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let r = result {
                if !r.commits.isEmpty {
                    CommitsPane(commits: Array(r.commits.prefix(6)), total: r.commitCount, tint: Theme.emberLight, empty: "")
                }
                if r.changes.isEmpty {
                    Text("Nenhuma diferença de arquivo.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.faded)
                } else {
                    WidthSwitch {
                        HStack(alignment: .top, spacing: 14) {
                            FileList(changes: r.changes, selectedFile: $selectedFile)
                                .frame(width: 252)
                            DiffPane(change: selected, lines: diff, path: finding.path ?? "")
                        }
                    } narrow: {
                        VStack(spacing: 14) {
                            FileList(changes: r.changes, selectedFile: $selectedFile)
                            DiffPane(change: selected, lines: diff, path: finding.path ?? "")
                        }
                    }
                }
            } else if let error {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.waitText)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("lendo o Git…").font(.system(size: 12.5)).foregroundStyle(Theme.faded)
                }
            }
        }
        .task {
            do {
                let f = finding
                let loaded = try await Core.run { try $0.findingChanges(f) }
                withAnimation(.easeOut(duration: 0.25)) {
                    result = loaded
                    selectedFile = loaded.changes.first?.id
                }
            } catch {
                self.error = errorMessage(error)
            }
        }
        .task(id: selectedFile) {
            guard let change = selected else { return }
            let f = finding
            if let lines = try? await Core.run({ try $0.findingFileDiff(f, change: change) }), change.id == selectedFile {
                withAnimation(.easeOut(duration: 0.2)) {
                    diff = lines
                    diffFile = change.id
                }
            }
        }
    }
}
