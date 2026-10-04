import Foundation
import SwiftUI

enum OnboardingPreference {
    static let seen = "onboardingSeen"
}

struct OnboardingPage: Identifiable {
    let id: Int
    let icon: String
    let tone: Color
    let title: String
    let detail: String
    let points: [String]

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
        )
    ]
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private let pages = OnboardingPage.all
    private var page: OnboardingPage { pages[index] }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                TramaLogo(size: 24)
                Text("Bem-vindo ao trama")
                    .font(Theme.serif(22).italic())
                Spacer()
                if !isLast {
                    Button("Pular", action: finish)
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.faded)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: page.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(page.tone)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(page.tone.opacity(0.13)))
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(Theme.serif(34))
                Text(page.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(page.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Dot(color: page.tone)
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .id(page.id)
            .transition(.opacity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(pages) { p in
                        Capsule()
                            .fill(p.id == index ? Theme.ember : Theme.line2)
                            .frame(width: p.id == index ? 18 : 6, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Passo \(index + 1) de \(pages.count)")
                Spacer()
                if index > 0 {
                    Button("Voltar") { go(index - 1) }
                        .buttonStyle(GhostButton())
                }
                Button {
                    if isLast { finish(createFirst: !model.repos.isEmpty) } else { go(index + 1) }
                } label: {
                    Text(isLast ? "Tecer a primeira trama" : "Continuar")
                }
                .buttonStyle(EmberButton())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(36)
        .frame(width: 600)
        .background(Color(hex: 0x111217))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private func go(_ next: Int) {
        withAnimation(.easeOut(duration: 0.18)) { index = next }
    }

    private func finish() {
        finish(createFirst: false)
    }

    private func finish(createFirst: Bool) {
        UserDefaults.standard.set(true, forKey: OnboardingPreference.seen)
        model.showingOnboarding = false
        dismiss()
        if createFirst { model.showingNewTrama = true }
    }
}
