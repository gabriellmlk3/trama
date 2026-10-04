import Foundation

struct AgentModel: Hashable, Identifiable {
    static let storageKey = "agentModel"

    var id: String
    var label: String
    var detail: String

    var argument: String? { id.isEmpty ? nil : id }

    static let standard = AgentModel(id: "", label: "Padrão", detail: "O modelo configurado no Claude Code")

    static let all = [
        standard,
        AgentModel(id: "claude-fable-5-1", label: "Fable 5.1", detail: "O mais capaz"),
        AgentModel(id: "claude-opus-5-5", label: "Opus 5.5", detail: "Tarefas longas e complexas"),
        AgentModel(id: "claude-sonnet-5-5", label: "Sonnet 5.5", detail: "Equilíbrio entre qualidade e velocidade"),
        AgentModel(id: "claude-haiku-4-5-20251001", label: "Haiku 4.5", detail: "O mais rápido e barato"),
    ]

    static func find(_ id: String?) -> AgentModel {
        guard let id, !id.isEmpty else { return standard }
        return all.first { $0.id == id } ?? AgentModel(id: id, label: id, detail: "Definido por você")
    }

    static var saved: AgentModel {
        find(UserDefaults.standard.string(forKey: storageKey))
    }
}
