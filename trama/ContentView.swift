import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.needsSetup {
                SetupView()
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Sidebar()
                            .frame(width: 264)
                        Rectangle().fill(Theme.line).frame(width: 1)
                        DetailView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                    TerminalDrawer(store: model.terminals)
                }
            }
        }
        .frame(minWidth: 1180, minHeight: 700)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showingNewTrama) {
            NewTramaView()
                .environmentObject(model)
        }
        .onChange(of: model.agentDialogToken) { _, _ in
            openWindow(id: "agente")
        }
        .sheet(isPresented: $model.showingOnboarding) {
            OnboardingView()
                .environmentObject(model)
        }
        .sheet(item: $model.resuming) { t in
            ResumeView(trama: t)
                .environmentObject(model)
        }
        .overlay(alignment: .bottom) {
            Banners()
        }
        .onAppear { model.start() }
    }
}

struct DetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.screen {
        case .home?, nil:
            HomeView()
        case .findings?:
            FindingsView()
        case .trama?:
            if let t = model.selectedTrama {
                TramaDetailView(trama: t)
            } else {
                HomeView()
            }
        case .home?, nil:
            HomeView()
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeneralAgentView(session: model.homeAgent) {
            EmptyStateHero()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }
}

struct EmptyStateHero: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            TramaLogo(size: 56)
            Text("Pare de trocar de branch.")
                .font(Theme.serif(38))
            Text("Crie uma trama: a mesma branch em vários repositórios, cada um no seu worktree, com uma cápsula de contexto que os agentes leem e escrevem. Ou peça ao agent geral abaixo.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button {
                model.showingNewTrama = true
            } label: {
                HStack(spacing: 8) {
                    Text("Tecer a primeira trama")
                    KeyCap(text: "⌘N", dark: true)
                }
            }
            .buttonStyle(EmberButton())
            .disabled(model.repos.isEmpty)
            if let proposal = model.proposal {
                HomeProposalCard(proposal: proposal)
            }
            if model.repos.isEmpty {
                Button("Cadastrar repositórios…") {
                    let folders = Terminal.choosePaths(multiple: true, title: "Escolha os repositórios que podem entrar em tramas")
                    Task { await model.addRepos(folders) }
                }
                .buttonStyle(GhostButton())
            }
        }
    }
}

struct Banners: View {
    @EnvironmentObject var model: AppModel
    @State private var expiredPermission: String?

    var permissionKey: String? {
        model.permissionRequest.map { "\($0.trama.slug)/\($0.repo ?? "")/\($0.summary)" }
    }

    var body: some View {
        VStack(spacing: 8) {
            if model.agentDialog == nil, let request = model.permissionRequest, permissionKey != expiredPermission {
                Button {
                    model.openAgent(request.trama, repo: request.repo)
                } label: {
                    HStack(spacing: 8) {
                        Dot(color: Theme.wait, halo: true)
                        Text("\(request.trama.title)\(request.repo.map { " · \($0)" } ?? ""): o agent pediu permissão — \(request.summary)")
                            .foregroundStyle(Theme.text2)
                            .lineLimit(2)
                        Text("Abrir").foregroundStyle(Theme.waitText)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 620, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1C1812)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.wait.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .task(id: permissionKey) {
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled else { return }
                    expiredPermission = permissionKey
                }
            }
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").foregroundStyle(Theme.okText)
                    Text(notice).foregroundStyle(Theme.text2)
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2, lineWidth: 1))
            }
            if let error = model.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.waitText)
                    Text(error)
                        .foregroundStyle(Theme.text2)
                        .textSelection(.enabled)
                        .frame(maxWidth: 560, alignment: .leading)
                    Button {
                        model.error = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.faded)
                    .accessibilityLabel("Fechar aviso")
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1C1812)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.wait.opacity(0.45), lineWidth: 1))
            }
        }
        .padding(.bottom, 18)
        .animation(.easeOut(duration: 0.2), value: expiredPermission)
        .animation(.easeOut(duration: 0.2), value: model.notice)
        .animation(.easeOut(duration: 0.2), value: model.error)
    }
}
