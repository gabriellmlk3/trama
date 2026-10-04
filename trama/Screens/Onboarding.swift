import Foundation
import SwiftUI

enum OnboardingPreference {
    static let seen = "onboardingSeen"
    static let version = "onboardingVersion"

    static func seenVersion(_ defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: version)
        if stored > 0 { return stored }
        return defaults.bool(forKey: seen) ? 1 : 0
    }

    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(OnboardingPage.currentVersion, forKey: version)
        defaults.set(true, forKey: seen)
    }

    static func pages(seenVersion: Int) -> [OnboardingPage] {
        guard seenVersion > 0 else { return OnboardingPage.all }
        return OnboardingPage.all.filter { $0.since > seenVersion }
    }
}

struct OnboardingPage: Identifiable {
    enum Extra {
        case none
        case prerequisites
    }

    static let currentVersion = 1

    let id: Int
    let icon: String
    let tone: Color
    let title: String
    let detail: String
    let points: [String]
    var since = 1
    var extra = Extra.none

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            icon: "point.3.connected.trianglepath.dotted",
            tone: Theme.ember,
            title: "Uma trama, vários repositórios",
            detail: "Uma trama é a mesma branch em vários repositórios ao mesmo tempo. Cada repositório ganha o seu worktree, então você nunca mais troca de branch à mão.",
            points: [
                "Crie com ⌘N e escolha os repositórios envolvidos",
                "As tramas ficam em ~/Tramas, longe dos seus clones",
                "Estacione uma trama e retome quando quiser"
            ]
        ),
        OnboardingPage(
            id: 1,
            icon: "doc.text",
            tone: Theme.iris,
            title: "A cápsula guarda o contexto",
            detail: "Cada trama tem uma cápsula em markdown: objetivo, decisões, handoffs entre repositórios e pendências. Você e os agentes leem e escrevem nela.",
            points: [
                "Registre decisões e pendências direto no painel da cápsula",
                "Handoffs passam trabalho de um repositório para outro",
                "Quem chega depois começa já sabendo o que foi decidido"
            ]
        ),
        OnboardingPage(
            id: 2,
            icon: "sparkle",
            tone: Theme.wait,
            title: "Agentes trabalhando junto",
            detail: "Abra o Claude em cada repositório da trama. Cada sessão recebe a cápsula e aparece aqui com seu status; quando um agente precisar de você, o Trama avisa.",
            points: [
                "⌘↩ abre o Claude em todos os repositórios da trama",
                "Notificações dizem quando um agente espera ou termina",
                "Descreva o que precisa no agent geral e ele propõe a trama"
            ]
        ),
        OnboardingPage(
            id: 3,
            icon: "arrow.triangle.pull",
            tone: Theme.ok,
            title: "Do código ao pull request",
            detail: "Acompanhe alterações, commits à frente e atrás e conflitos de todos os repositórios num só lugar, e abra os pull requests da trama de uma vez.",
            points: [
                "A tela inicial mostra o que pede atenção primeiro",
                "⇧⌘L abre Achados & perdidos: branches e worktrees soltos",
                "Dá para rever esta introdução em Trama › Introdução"
            ]
        ),
        OnboardingPage(
            id: 4,
            icon: "checklist",
            tone: Theme.ember,
            title: "Antes de começar",
            detail: "O Trama usa algumas ferramentas do seu Mac. Git e Claude Code são necessários; as CLIs de provedor só importam para quem abre PRs por elas.",
            points: [],
            extra: .prerequisites
        )
    ]
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var prerequisites: [Prerequisite] = []
    @State private var creatingSample = false
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var detailSize: CGFloat = 14
    @ScaledMetric(relativeTo: .callout) private var pointSize: CGFloat = 13

    private var pages: [OnboardingPage] { model.onboardingPages }
    private var page: OnboardingPage { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { index >= pages.count - 1 }
    private var hasRepos: Bool { !model.repos.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                TramaLogo(size: 24)
                Text("Bem-vindo ao trama")
                    .font(Theme.serif(22).italic())
                Spacer()
                Button(isLast ? "Fechar" : "Pular", action: finish)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.faded)
            }

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: page.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(page.tone)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(page.tone.opacity(0.13)))
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(Theme.serif(titleSize))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(page.detail)
                    .font(.system(size: detailSize))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                if !page.points.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(page.points, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Dot(color: page.tone)
                                Text(point)
                                    .font(.system(size: pointSize))
                                    .foregroundStyle(Theme.text2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                if page.extra == .prerequisites {
                    prerequisiteList
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .id(page.id)
            .transition(.opacity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Theme.ember : Theme.line2)
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Passo \(index + 1) de \(pages.count)")
                Spacer()
                if index > 0 {
                    Button("Voltar") { go(index - 1) }
                        .buttonStyle(GhostButton())
                }
                if isLast {
                    Button {
                        startSample()
                    } label: {
                        HStack(spacing: 8) {
                            if creatingSample { ProgressView().controlSize(.small) }
                            Text("Explorar com um exemplo")
                        }
                    }
                    .buttonStyle(GhostButton())
                    .disabled(creatingSample)
                    .help("Cria uma trama de exemplo, com um repositório descartável, para você explorar sem risco")
                }
                Button {
                    if isLast { startFirstTrama() } else { go(index + 1) }
                } label: {
                    Text(isLast ? (hasRepos ? "Tecer a primeira trama" : "Cadastrar repositórios") : "Continuar")
                }
                .buttonStyle(EmberButton())
                .keyboardShortcut(.defaultAction)
                .disabled(creatingSample)
            }
        }
        .padding(36)
        .frame(minWidth: 560, idealWidth: 600, maxWidth: 760)
        .background(Color(hex: 0x111217))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear { prerequisites = Prerequisite.check() }
        .onDisappear { OnboardingPreference.markSeen() }
    }

    private var prerequisiteList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(prerequisites) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Dot(color: item.installed ? Theme.ok : (item.required ? Theme.wait : Theme.faded))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(item.title)
                                .font(.system(size: pointSize, weight: .medium))
                                .foregroundStyle(Theme.text2)
                            Text(item.installed ? "instalado" : (item.required ? "não encontrado" : "opcional"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(item.installed ? Theme.okText : Theme.faded)
                        }
                        Text(item.installed ? item.purpose : "\(item.purpose) · \(item.hint)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faded)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button("Verificar de novo") { prerequisites = Prerequisite.check() }
                .buttonStyle(GhostButton(compact: true))
        }
        .padding(.top, 4)
    }

    private func go(_ next: Int) {
        withAnimation(.easeOut(duration: 0.18)) { index = next }
    }

    private func finish() {
        OnboardingPreference.markSeen()
        model.showingOnboarding = false
        dismiss()
    }

    private func startFirstTrama() {
        if hasRepos {
            finish()
            model.showingNewTrama = true
            return
        }
        let folders = Terminal.choosePaths(multiple: true, title: "Escolha os repositórios que podem entrar em tramas")
        guard !folders.isEmpty else { return }
        finish()
        Task {
            await model.addRepos(folders)
            if !model.repos.isEmpty { model.showingNewTrama = true }
        }
    }

    private func startSample() {
        creatingSample = true
        Task {
            let created = await model.createSampleTrama()
            creatingSample = false
            if created { finish() }
        }
    }
}
