import Foundation
import SwiftUI

enum Tip: String, CaseIterable {
    case capsule
    case agents
    case findings

    var icon: String {
        switch self {
        case .capsule: "doc.text"
        case .agents: "sparkle"
        case .findings: "magnifyingglass"
        }
    }

    var title: String {
        switch self {
        case .capsule: "A cápsula é a memória da trama"
        case .agents: "Agentes entram pelo botão “Abrir no Claude”"
        case .findings: "Achados & perdidos se atualiza sozinho"
        }
    }

    var text: String {
        switch self {
        case .capsule: "Registre decisões e pendências no painel à direita: quem abrir a trama depois, você ou um agente, já começa sabendo o que foi decidido."
        case .agents: "⌘↩ abre o Claude nos repositórios desta trama. Cada sessão recebe a cápsula e aparece aqui com o status; o Trama avisa quando um agente espera por você."
        case .findings: "Mudanças soltas, commits só locais e branches órfãs aparecem aqui. Use “Varrer agora” para conferir antes de arquivar uma trama."
        }
    }
}

enum TipPreference {
    static func key(_ tip: Tip) -> String {
        "tipDismissed." + tip.rawValue
    }

    static func isDismissed(_ tip: Tip, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(tip))
    }

    static func dismiss(_ tip: Tip, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(tip))
    }

    static func resetAll(defaults: UserDefaults = .standard) {
        for tip in Tip.allCases { defaults.removeObject(forKey: key(tip)) }
    }

    static func next(in tips: [Tip], defaults: UserDefaults = .standard) -> Tip? {
        tips.first { !isDismissed($0, defaults: defaults) }
    }
}

struct TipCard: View {
    let tips: [Tip]
    @State private var revision = 0

    var body: some View {
        let _ = revision
        Group {
            if let tip = TipPreference.next(in: tips) {
                card(tip)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            revision += 1
        }
    }

    private func card(_ tip: Tip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.iris)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.iris.opacity(0.13)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(tip.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(tip.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Entendi") {
                TipPreference.dismiss(tip)
                revision += 1
            }
            .buttonStyle(GhostButton(compact: true))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dica: \(tip.title)")
    }
}
