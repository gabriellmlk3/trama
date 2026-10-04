import Foundation
import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                model.screen = .home
            } label: {
                HStack(spacing: 9) {
                    TramaLogo(size: 22)
                    Text("trama")
                        .font(Theme.serif(28).italic())
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .help("Início")

            Button {
                model.showingNewTrama = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
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
                VStack(alignment: .leading, spacing: 18) {
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
                FindingsItem()
                ContextItem()
            }

            RateLimitsItem()

            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
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
            .padding(.horizontal, 8)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Limites do Claude")
                    .font(Theme.mono(10.5))
                Spacer()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(window.label) · \(Int((fraction * 100).rounded()))%")
                Spacer()
                Text(reset)
            }
            .font(Theme.mono(10.5))
            .foregroundStyle(blocked || fraction > 0.9 ? Theme.waitText : Theme.faded)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line2)
                    Capsule().fill(color).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
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
                TramaIndicator(trama: trama, agents: model.agents(for: trama.slug), docked: model.hasBusyAgent(in: trama.slug), permissions: model.permissionCount(in: trama.slug))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.surface2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color(hex: 0x2B2E36) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 10) {
                Image(systemName: "house")
                    .font(.system(size: 13))
                Text("Início")
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                Spacer()
                KeyCap(text: "⌘0")
            }
            .foregroundStyle(selected ? Theme.text : Theme.text2)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color(hex: 0x2B2E36) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FindingsItem: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let selected = model.screen == .findings
        Button {
            model.screen = .findings
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 13))
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
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color(hex: 0x2B2E36) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ContextItem: View {
    @EnvironmentObject var model: AppModel

    var contextName: String {
        guard let c = model.state?.context, !c.isEmpty else { return "não configurado" }
        return Paths.name(c)
    }

    var body: some View {
        Button {
            if let c = model.state?.context {
                Terminal.reveal(c)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13))
                Text("Contexto base")
                    .font(.system(size: 13))
                Spacer()
                Text(contextName)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faded)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.state?.context ?? "Sem repositório de contexto: cada cápsula fica na pasta da própria trama")
    }
}
