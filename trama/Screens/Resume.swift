import Foundation
import SwiftUI

struct ResumeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let trama: LiveTrama

    @State private var rebase = true
    @State private var capsule: TramaCapsule?
    @State private var results: [ResumeResult]?
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                    Text("estacionada \(relativeTime(trama.parkedAt))")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(Theme.surface2))
                .overlay(Capsule().stroke(Theme.line2, lineWidth: 1))
                Text(trama.branch)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.faded)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButton())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Fechar")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(trama.title)
                    .font(Theme.serif(44))
                Text(trama.repos.joined(separator: " · "))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.faded)
            }

            WhereYouLeftOff(capsule: capsule)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Enquanto esteve estacionada")
                VStack(spacing: 0) {
                    ForEach(trama.status) { s in
                        ChangeRow(status: s)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x22252B), lineWidth: 1))
            }

            if let results {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Resultado")
                    ForEach(results) { r in
                        HStack(spacing: 8) {
                            Image(systemName: r.situation == "conflito" || r.situation == "erro" ? "exclamationmark.triangle" : "checkmark")
                                .foregroundStyle(r.situation == "conflito" || r.situation == "erro" ? Theme.waitText : Theme.okText)
                            Text(r.repo).font(Theme.mono(12))
                            Text(r.detail ?? r.situation)
                                .foregroundStyle(Theme.text3)
                        }
                        .font(.system(size: 12.5))
                    }
                }
            } else {
                Toggle(isOn: $rebase) {
                    Text("Fazer rebase na base em cada repositório limpo (conflitos são desfeitos e avisados)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text2)
                }
                .toggleStyle(.switch)
                .tint(Theme.ember)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Só abrir a pasta") {
                    Terminal.reveal(trama.path)
                }
                .buttonStyle(GhostButton())
                Spacer()
                if results != nil {
                    Button("Abrir agent") {
                        model.openClaudeInAll(trama)
                        dismiss()
                    }
                    .buttonStyle(GhostButton())
                    Button("Pronto") { dismiss() }
                        .buttonStyle(EmberButton())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        resume()
                    } label: {
                        HStack(spacing: 10) {
                            if sending {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill").font(.system(size: 10))
                            }
                            Text("Retomar trama")
                            KeyCap(text: "↵", dark: true)
                        }
                    }
                    .buttonStyle(EmberButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(sending)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 640, height: 720)
        .background(Color(hex: 0x111217))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .task {
            let slug = trama.slug
            capsule = try? await Core.run { try $0.readCapsule(slug) }
        }
    }

    func resume() {
        sending = true
        let slug = trama.slug
        let withRebase = rebase
        Task {
            let r = await model.resume(slug, rebase: withRebase)
            sending = false
            if let r {
                if r.isEmpty {
                    dismiss()
                } else {
                    results = r
                }
            }
        }
    }
}

struct WhereYouLeftOff: View {
    let capsule: TramaCapsule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Onde você parou", systemImage: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("da cápsula e dos worktrees")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faded)
            }
            if let c = capsule {
                VStack(alignment: .leading, spacing: 9) {
                    if !c.goal.isEmpty {
                        Marker(text: c.goal, color: Theme.faded)
                    }
                    if let last = c.decisions.last {
                        Marker(text: "Última decisão: \(last.text)", color: Theme.faded)
                    }
                    ForEach(c.openHandoffs.prefix(2)) { h in
                        Marker(text: "Handoff em aberto para \(h.to ?? "?"): \(h.text)", color: Theme.ember)
                    }
                    ForEach(c.openSuggestions.prefix(2)) { item in
                        Marker(text: "Agente sugere incluir \(item.to ?? "?"): \(item.text)", color: Theme.iris)
                    }
                    let open = c.openPending
                    if !open.isEmpty {
                        Marker(
                            text: "\(open.count) \(plural(open.count, "pendência", "pendências")): " + open.prefix(3).map { $0.text }.joined(separator: "; "),
                            color: Theme.wait
                        )
                    }
                    if c.decisions.isEmpty && c.handoffs.isEmpty && open.isEmpty && c.goal.isEmpty {
                        Text("A cápsula está vazia, vale anotar o objetivo ao retomar.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.faded)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x16171D)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line2, lineWidth: 1))
    }
}

struct Marker: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .offset(y: -2)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ChangeRow: View {
    let status: RepoStatus

    var body: some View {
        HStack(spacing: 12) {
            Text(status.repo)
                .font(Theme.mono(12))
                .frame(width: 140, alignment: .leading)
            Text(status.behind == 0 ? "em dia com \(status.base)" : "\(status.base) avançou \(status.behind) \(plural(status.behind, "commit", "commits"))")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text3)
            Spacer()
            if status.changed > 0 {
                Text("\(status.changed) não commitado(s) · rebase pulado")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faded)
            } else if status.conflict == "conflito" {
                Label("conflito provável", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.waitText)
            } else if status.behind > 0 {
                Label("rebase limpo", systemImage: "checkmark")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.okText)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0x1D1F25)).frame(height: 1)
        }
    }
}
