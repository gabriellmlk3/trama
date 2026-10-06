import Foundation
import SwiftUI

struct SidebarRail: View {
    @EnvironmentObject var model: AppModel

    var sections: [[LiveTrama]] {
        let pinned = model.pinnedTramas
        let active = model.active.filter { !$0.pinned }
        let parked = model.parked.filter { !$0.pinned }
        return [pinned, active, parked].enumerated().filter { $0.offset == 1 || !$0.element.isEmpty }.map(\.element)
    }

    var body: some View {
        VStack(spacing: SidebarPreference.sectionSpacing) {
            Button {
                model.screen = .home
            } label: {
                TramaLogo(size: SidebarPreference.iconColumn)
                    .frame(width: 44, height: SidebarPreference.logoRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Início")

            Button {
                model.showingNewTrama = true
            } label: {
                Image(systemName: "sparkle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faded)
                    .frame(width: 44, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line2, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tecer nova trama… (⌘N)")
            .accessibilityLabel("Tecer nova trama")

            RailButton(icon: "house", title: "Início (⌘0)", selected: model.screen == .home || model.screen == nil) {
                model.screen = .home
            }

            ScrollView {
                VStack(spacing: SidebarPreference.sectionSpacing) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        VStack(spacing: 4) {
                            ZStack {
                                SectionLabel(text: "x").hidden()
                                if index > 0 {
                                    Rectangle().fill(Theme.line2).frame(width: 20, height: 1)
                                }
                            }
                            .padding(.bottom, 4)
                            if section.isEmpty {
                                Color.clear.frame(width: 44, height: 15)
                            }
                            ForEach(section) { t in
                                RailTramaItem(trama: t, section: section)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                RailButton(icon: "arrow.triangle.branch", title: "Repositórios (⇧⌘G)", selected: model.screen == .repositories) {
                    model.screen = .repositories
                }
                RailButton(
                    icon: "tray",
                    title: "Achados & perdidos",
                    selected: model.screen == .findings,
                    badge: model.findings.isEmpty ? nil : "\(model.findings.count)"
                ) {
                    model.screen = .findings
                }
                RailButton(
                    icon: "bolt",
                    title: model.hasFailedAutomation ? "Automações · uma automação falhou" : "Automações",
                    selected: model.screen == .automations,
                    signal: model.hasFailedAutomation ? Theme.danger : nil
                ) {
                    model.screen = .automations
                }
                RailButton(icon: "square.stack.3d.up", title: "Contexto base · \(model.contextName)") {
                    if let c = model.state?.context {
                        Terminal.reveal(c)
                    }
                }
            }

            RateLimitsItem(compact: true)

            Group {
                if model.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faded)
                }
            }
            .frame(width: 44, height: SidebarPreference.footerRowHeight)
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .help(Paths.abbreviate(model.state?.root ?? Workspace.defaultRoot()))
        }
        .padding(.top, 40)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }
}

struct RailButton: View {
    let icon: String
    let title: String
    var selected = false
    var badge: String?
    var signal: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(selected ? Theme.text : Theme.text2)
                .frame(width: 44, height: SidebarPreference.rowHeight)
                .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.surface2 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Theme.line2 : Color.clear, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.emberLight)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(Theme.ember.opacity(0.16)))
                            .background(Capsule().fill(Theme.panel))
                            .offset(x: 3, y: -3)
                    } else if let signal {
                        Dot(color: signal, size: 6, halo: true)
                            .padding(5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(badge.map { "\(title), \($0)" } ?? title)
    }
}

struct RailTramaItem: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    var section: [LiveTrama] = []

    var selected: Bool { model.screen == .trama(trama.slug) }

    var monogram: String {
        let source = trama.title.isEmpty ? trama.slug : trama.title
        let words = source.split { $0 == " " || $0 == "-" || $0 == "_" }
        if words.count >= 2 {
            return words.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        return String(source.prefix(2)).capitalized
    }

    var signal: Color? {
        guard trama.isActive else { return nil }
        let agents = model.agents(for: trama.slug)
        if model.permissionCount(in: trama.slug) > 0 || agents.contains(where: { $0.isWaiting }) { return Theme.wait }
        if model.hasBusyAgent(in: trama.slug) { return Theme.ember }
        if agents.contains(where: { $0.isWorking }) { return Theme.iris }
        if trama.conflicts > 0 { return Theme.waitText }
        return nil
    }

    var body: some View {
        Button {
            model.select(trama.slug)
        } label: {
            HStack(spacing: 6) {
                MarkerThread(highlighted: selected && trama.isActive, dashed: trama.isParked)
                Text(monogram)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(trama.isParked ? Theme.text3 : (selected ? Theme.text : Theme.text2))
                    .lineLimit(1)
                    .frame(width: SidebarPreference.iconColumn)
            }
            .padding(.leading, 10)
            .frame(width: 44, height: SidebarPreference.tramaRowHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.surface2 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.line2 : Color.clear, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if let signal {
                    Dot(color: signal, size: 6, halo: true)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if model.isFocused(trama.slug) {
                    Image(systemName: "scope")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.ember)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(trama.title) · \(model.aliases(trama.repos).joined(separator: " · "))")
        .accessibilityLabel(trama.title)
        .modifier(TramaItemActions(trama: trama, section: section))
    }
}
