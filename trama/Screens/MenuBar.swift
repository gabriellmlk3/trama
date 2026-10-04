import AppKit
import Foundation
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var agents: [Agent] { model.activeAgents }
    var active: Int { agents.filter { $0.isWorking || $0.isWaiting }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                TramaLogo(size: 18)
                Text("trama")
                    .font(Theme.serif(22).italic())
                Spacer()
                if active > 0 {
                    HStack(spacing: 6) {
                        Dot(color: Theme.iris, halo: true)
                        Text("\(active) \(plural(active, "agente ativo", "agentes ativos"))")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.irisText)
                }
            }
            .padding(.horizontal, 4)

            if let t = model.focusedTrama {
                ActiveTramaCard(trama: t) { focusWindow() }
            } else {
                Text("Nenhuma trama ativa.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faded)
            }

            if !agents.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: "Agentes")
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    ForEach(agents.prefix(6)) { a in
                        AgentMenuRow(
                            agent: a,
                            trama: model.visibleTramas.first(where: { $0.slug == a.trama }),
                            openApp: focusWindow
                        )
                    }
                }
            }

            if !model.active.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: "Trocar de trama")
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    ForEach(Array(model.active.prefix(9).enumerated()), id: \.element.id) { i, t in
                        let current = model.focusedTrama?.slug == t.slug
                        Button {
                            model.select(t.slug)
                            focusWindow()
                        } label: {
                            HStack(spacing: 10) {
                                MarkerThread(highlighted: current, dashed: false)
                                    .frame(height: 16)
                                    .clipped()
                                Text(t.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(current ? Theme.text : Theme.text2)
                                    .lineLimit(1)
                                Spacer()
                                Text("⌃\(i + 1)")
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.faded)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(current ? Theme.surface2 : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.control])
                    }
                }
            }

            HStack(spacing: 6) {
                if let t = model.focusedTrama {
                    Button {
                        Task { await model.park(t.slug) }
                    } label: {
                        Label("Estacionar atual", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GhostButton(compact: true))
                }
                Button {
                    model.screen = .findings
                    focusWindow()
                } label: {
                    HStack(spacing: 6) {
                        Text("Achados")
                        if !model.findings.isEmpty {
                            Text("\(model.findings.count)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.emberLight)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Theme.ember.opacity(0.16)))
                        }
                    }
                }
                .buttonStyle(GhostButton(compact: true))
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Sair do Trama")
                .accessibilityLabel("Sair do Trama")
            }
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Color(hex: 0x262930)).frame(height: 1)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Color(hex: 0x15161B))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
    }

    func focusWindow() {
        openWindow(id: "principal")
        NSApp.activate()
    }
}

struct ActiveTramaCard: View {
    @EnvironmentObject var model: AppModel
    let trama: LiveTrama
    let openApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Trama em foco")
            VStack(alignment: .leading, spacing: 2) {
                Text(trama.title)
                    .font(.system(size: 15, weight: .medium))
                Text(trama.branch)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.emberLight)
            }
            HStack(spacing: 6) {
                Button {
                    model.openClaudeInAll(trama)
                    openApp()
                } label: {
                    Label("Abrir no Claude", systemImage: "sparkle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(EmberButton(compact: true))
                Button {
                    model.terminals.open(path: trama.path, command: nil, title: trama.title)
                    openApp()
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Abrir o Terminal na pasta da trama")
                .accessibilityLabel("Abrir o Terminal na pasta da trama")
                Button(action: openApp) {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(IconButton(size: 28))
                .help("Abrir a janela do Trama")
                .accessibilityLabel("Abrir a janela do Trama")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line2, lineWidth: 1))
    }
}

struct AgentMenuRow: View {
    @EnvironmentObject var model: AppModel
    let agent: Agent
    let trama: LiveTrama?
    let openApp: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if agent.isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.okText)
                    .frame(width: 8)
            } else {
                Dot(color: agent.isWaiting ? Theme.wait : (agent.isWorking ? Theme.iris : Theme.faded), halo: agent.isWorking)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.isRoot ? "Agente da trama" : agent.repo)
                    .font(Theme.mono(12))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(agent.isWaiting ? Theme.waitText : Theme.faded)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if agent.isWaiting {
                Button("Revisar") {
                    if let trama {
                        let path = agent.repo.isEmpty ? trama.path : model.worktreePath(trama, agent.repo)
                        let extra = agent.repo.isEmpty ? trama.repos.map { model.worktreePath(trama, $0) } : []
                        model.openClaude(path: path, repo: agent.repo.isEmpty ? trama.title : agent.repo, extraDirs: extra)
                    }
                    openApp()
                }
                .buttonStyle(ToneButton(color: Theme.wait, text: Theme.waitText))
            } else if let tramaTitle = trama?.title {
                Text(tramaTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x9A9EA8))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Theme.line))
                    .frame(maxWidth: 110)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 42)
    }

    var detail: String {
        var parts = [agent.isRoot ? agent.rootStateLabel : agent.stateLabel]
        if let m = agent.message, !m.isEmpty, !agent.isWaiting { parts.append(m) }
        parts.append(relativeTime(agent.updatedAt))
        return parts.joined(separator: " · ")
    }
}
