import Foundation
import SwiftUI

enum SidebarPreference {
    static let expanded = "sidebarExpanded"
    static let width: CGFloat = 264
    static let railWidth: CGFloat = 68
    static let itemInset: CGFloat = railWidth / 2 - 14
    static let iconColumn: CGFloat = 24
    static let rowHeight: CGFloat = 38
    static let tramaRowHeight: CGFloat = 48
    static let logoRowHeight: CGFloat = 34
    static let footerRowHeight: CGFloat = 18
    static let limitsLineHeight: CGFloat = 13
    static let sectionSpacing: CGFloat = 18
}

struct SidebarIcon: View {
    let name: String
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size))
            .frame(width: SidebarPreference.iconColumn)
    }
}

struct SidebarToggle: View {
    @Binding var expanded: Bool

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13))
                .foregroundStyle(Theme.faded)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Reduzir a barra lateral aos ícones (⌃⌘S)" : "Expandir a barra lateral (⌃⌘S)")
        .accessibilityLabel(expanded ? "Reduzir a barra lateral" : "Expandir a barra lateral")
    }
}

extension AppModel {
    var contextName: String {
        guard let c = state?.context, !c.isEmpty else { return "não configurado" }
        return Paths.name(c)
    }

    var hasFailedAutomation: Bool {
        visibleTramas.contains { $0.automation == AutomationRunState.failed }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarPreference.sectionSpacing) {
            Button {
                model.screen = .home
            } label: {
                HStack(spacing: 9) {
                    TramaLogo(size: SidebarPreference.iconColumn)
                    Text("trama")
                        .font(Theme.serif(28).italic())
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .frame(height: SidebarPreference.logoRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .help("Início")

            Button {
                model.showingNewTrama = true
            } label: {
                HStack(spacing: 8) {
                    SidebarIcon(name: "sparkle", size: 12)
                    Text("Tecer nova trama…")
                    Spacer()
                    KeyCap(text: "⌘N")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.faded)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0x262930), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HomeItem()

            ScrollView {
                VStack(alignment: .leading, spacing: SidebarPreference.sectionSpacing) {
                    if !model.pinnedTramas.isEmpty {
                        SidebarSection(title: "Fixadas", tramas: model.pinnedTramas)
                    }
                    SidebarSection(title: "Tecendo agora", tramas: model.active.filter { !$0.pinned })
                    let parked = model.parked.filter { !$0.pinned }
                    if !parked.isEmpty {
                        SidebarSection(title: "Estacionadas", tramas: parked)
                    }
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                RepositoriesItem()
                FindingsItem()
                AutomationsItem()
                ContextItem()
            }

            RateLimitsItem()

            HStack(spacing: 8) {
                SidebarIcon(name: "folder", size: 12)
                    .foregroundStyle(Theme.faded)
                Text(Paths.abbreviate(model.state?.root ?? Workspace.defaultRoot()))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
                Spacer()
                if model.busy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(height: SidebarPreference.footerRowHeight)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }
}

struct RateLimitsItem: View {
    @ObservedObject private var store = RateLimitStore.shared
    var compact = false

    var body: some View {
        if compact {
            VStack(spacing: 6) {
                refreshControl
                    .frame(height: SidebarPreference.limitsLineHeight)
                if let limits = store.limits, !limits.windows.isEmpty {
                    ForEach(limits.windows, id: \.id) { window in
                        RateLimitRow(window: window, blocked: limits.isBlocked, compact: true)
                    }
                }
            }
            .frame(width: 44)
            .foregroundStyle(Theme.faded)
        } else {
            full
        }
    }

    @ViewBuilder
    private var refreshControl: some View {
        if store.refreshing {
            ProgressView().controlSize(.mini)
        } else {
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Ler os limites agora")
        }
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Limites do Claude")
                    .font(Theme.mono(10.5))
                Spacer()
                refreshControl
            }
            .frame(height: SidebarPreference.limitsLineHeight)
            .foregroundStyle(Theme.faded)
            if let limits = store.limits, !limits.windows.isEmpty {
                ForEach(limits.windows, id: \.id) { window in
                    RateLimitRow(window: window, blocked: limits.isBlocked)
                }
            }
        }
        .padding(.horizontal, 8)
        .help(store.limits.map { "Limites do plano do Claude, lidos a cada 15 minutos e a cada resposta de um agent. Última leitura: \($0.updatedAt.formatted(date: .omitted, time: .shortened))." } ?? "Limites do plano do Claude: ainda sem leitura.")
    }
}

struct RateLimitRow: View {
    let window: RateLimitWindow
    let blocked: Bool
    var compact = false

    private var fraction: Double {
        min(1, max(0, window.utilization > 1 ? window.utilization / 100 : window.utilization))
    }

    private var color: Color {
        blocked || fraction > 0.9 ? Theme.waitText : fraction > 0.7 ? Theme.wait : Theme.ember
    }

    private var reset: String {
        guard window.resetsAt > Date() else { return "reiniciou" }
        let sameDay = Calendar.current.isDateInToday(window.resetsAt)
        return "reinicia " + window.resetsAt.formatted(sameDay ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
    }

    private var percent: String {
        "\(Int((fraction * 100).rounded()))%"
    }

    var body: some View {
        if compact {
            VStack(spacing: 3) {
                Text(percent)
                    .font(Theme.mono(9.5))
                    .frame(height: SidebarPreference.limitsLineHeight)
                    .foregroundStyle(blocked || fraction > 0.9 ? Theme.waitText : Theme.faded)
                bar
            }
            .help("Limite do Claude · \(window.label) · \(percent) · \(reset)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Limite do Claude, \(window.label): \(percent), \(reset)")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(window.label) · \(percent)")
                    Spacer()
                    Text(reset)
                }
                .font(Theme.mono(10.5))
                .frame(height: SidebarPreference.limitsLineHeight)
                .foregroundStyle(blocked || fraction > 0.9 ? Theme.waitText : Theme.faded)
                bar
            }
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line2)
                Capsule().fill(color).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 3)
    }
}

struct SidebarSection: View {
    let title: String
    let tramas: [LiveTrama]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: title)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            if tramas.isEmpty {
                Text("Nenhuma por enquanto")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
                    .padding(.horizontal, 8)
            }
            ForEach(tramas) { t in
                TramaItem(trama: t, section: tramas)
            }
        }
    }
}

struct TramaItem: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    var section: [LiveTrama] = []

    var selected: Bool { model.screen == .trama(trama.slug) }

    var body: some View {
        Button {
            model.select(trama.slug)
        } label: {
            HStack(spacing: 10) {
                MarkerThread(highlighted: selected && trama.isActive, dashed: trama.isParked)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trama.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(trama.isParked ? Theme.text3 : (selected ? Theme.text : Theme.text2))
                        .lineLimit(1)
                    Text(model.aliases(trama.repos).joined(separator: " · "))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faded)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if trama.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faded)
                }
                if model.isFocused(trama.slug) {
                    Image(systemName: "scope")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ember)
                        .help("Trama em foco")
                        .accessibilityLabel("Trama em foco")
                }
                TramaIndicator(trama: trama, agents: model.agents(for: trama.slug), docked: model.hasBusyAgent(in: trama.slug), permissions: model.permissionCount(in: trama.slug))
            }
            .padding(.horizontal, 10)
            .frame(height: SidebarPreference.tramaRowHeight)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.surface2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color(hex: 0x2B2E36) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TramaItemActions(trama: trama, section: section))
    }
}

struct TramaItemActions: ViewModifier {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let section: [LiveTrama]

    func body(content: Content) -> some View {
        content
            .draggable(trama.slug)
            .dropDestination(for: String.self) { slugs, _ in
                guard let dragged = slugs.first, section.contains(where: { $0.slug == dragged }) else { return false }
                Task { await model.moveTrama(dragged, to: trama.slug, in: section) }
                return true
            }
            .contextMenu {
                Button(trama.pinned ? "Desafixar" : "Fixar no topo") { Task { await model.setPinned(trama.slug, !trama.pinned) } }
                if section.count > 1 {
                    Button("Mover para cima") { Task { await model.shiftTrama(trama.slug, by: -1, in: section) } }
                        .disabled(section.first?.slug == trama.slug)
                    Button("Mover para baixo") { Task { await model.shiftTrama(trama.slug, by: 1, in: section) } }
                        .disabled(section.last?.slug == trama.slug)
                }
                Divider()
                if model.isFocused(trama.slug) {
                    Button("Tirar o foco") { Task { await model.clearFocus() } }
                } else {
                    Button("Focar") { Task { await model.focus(trama.slug) } }
                }
                if trama.isActive {
                    Button("Abrir agent") { model.openClaudeInAll(trama) }
                    Button("Estacionar") { Task { await model.park(trama.slug) } }
                } else {
                    Button("Retomar…") { model.resuming = trama }
                }
                Button("Mostrar no Finder") { Terminal.reveal(trama.path) }
                Button("Copiar nome da branch") { Terminal.copy(trama.branch) }
            }
    }
}

struct TramaIndicator: View {
    let trama: LiveTrama
    let agents: [Agent]
    var docked = false
    var permissions = 0

    var body: some View {
        let waiting = agents.filter { $0.isWaiting }.count
        let working = agents.filter { $0.isWorking }.count
        HStack(spacing: 5) {
            if trama.isParked {
                Text(relativeTime(trama.parkedAt).replacingOccurrences(of: "há ", with: ""))
                    .foregroundStyle(Theme.faded)
            } else if permissions > 0 {
                Dot(color: Theme.wait, halo: true)
                Text("\(max(permissions, waiting))").foregroundStyle(Theme.wait)
                    .help("Um agent embutido pediu permissão")
            } else if waiting > 0 {
                Dot(color: Theme.wait)
                Text("\(waiting)").foregroundStyle(Theme.wait)
            } else if docked {
                Dot(color: Theme.ember, halo: true)
                    .help("Um agent embutido está respondendo")
            } else if working > 0 {
                Dot(color: Theme.iris, halo: true)
                Text("\(working)").foregroundStyle(Theme.irisText)
            } else if trama.conflicts > 0 {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.waitText)
            } else if !agents.isEmpty {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.okText)
            }
        }
        .font(.system(size: 11.5))
    }
}

struct HomeItem: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let selected = model.screen == .home || model.screen == nil
        Button {
            model.screen = .home
        } label: {
            HStack(spacing: 8) {
                SidebarIcon(name: "house")
                Text("Início")
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
                KeyCap(text: "⌘0")
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

struct RepositoriesItem: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let selected = model.screen == .repositories
        Button {
            model.screen = .repositories
        } label: {
            HStack(spacing: 8) {
                SidebarIcon(name: "arrow.triangle.branch")
                Text("Repositórios")
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
                KeyCap(text: "⇧⌘G")
            }
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .padding(.horizontal, 10)
            .frame(height: SidebarPreference.rowHeight)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color(hex: 0x2B2E36) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Git de todos os repositórios: histórico, branches, stash e commits")
    }
}

struct FindingsItem: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let selected = model.screen == .findings
        Button {
            model.screen = .findings
        } label: {
            HStack(spacing: 8) {
                SidebarIcon(name: "tray")
                Text("Achados & perdidos")
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
                if !model.findings.isEmpty {
                    Text("\(model.findings.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.emberLight)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Theme.ember.opacity(0.16)))
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

struct ContextItem: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button {
            if let c = model.state?.context {
                Terminal.reveal(c)
            }
        } label: {
            HStack(spacing: 8) {
                SidebarIcon(name: "square.stack.3d.up")
                Text("Contexto base")
                    .font(.system(size: 13))
                Spacer()
                Text(model.contextName)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 10)
            .frame(height: SidebarPreference.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.state?.context ?? "Sem repositório de contexto: cada cápsula fica na pasta da própria trama")
    }
}
