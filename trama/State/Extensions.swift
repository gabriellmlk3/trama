import Foundation

extension Agent {
    var stateLabel: String {
        switch state {
        case AgentState.working: return "trabalhando"
        case AgentState.waiting: return "aguardando você"
        case AgentState.done: return "concluiu · sua vez"
        default: return "aberto"
        }
    }
}

extension Finding {
    var typeLabel: String {
        switch type {
        case FindingType.editOnBase, FindingType.forgottenChange: return "mudança esquecida"
        case FindingType.pendingHandoff: return "handoff"
        case FindingType.unpushed: return "não enviado"
        case FindingType.noRemote, FindingType.merged: return "branch órfã"
        case FindingType.looseWorktree: return "worktree"
        case FindingType.staleParked: return "estacionada"
        default: return type
        }
    }

    var group: String {
        switch type {
        case FindingType.editOnBase, FindingType.forgottenChange: return "Mudanças esquecidas"
        case FindingType.unpushed: return "Não enviados"
        case FindingType.noRemote, FindingType.merged: return "Branches órfãs"
        case FindingType.looseWorktree, FindingType.staleParked: return "Worktrees parados"
        case FindingType.pendingHandoff: return "Handoffs sem resposta"
        default: return "Outros"
        }
    }

    static let groups = ["Mudanças esquecidas", "Não enviados", "Branches órfãs", "Worktrees parados", "Handoffs sem resposta"]

    var symbol: String {
        switch type {
        case FindingType.editOnBase, FindingType.forgottenChange: return "pencil"
        case FindingType.unpushed: return "arrow.up"
        case FindingType.noRemote, FindingType.merged: return "arrow.triangle.branch"
        case FindingType.looseWorktree, FindingType.staleParked: return "folder"
        case FindingType.pendingHandoff: return "bubble.left"
        default: return "questionmark"
        }
    }

    var resolvable: Bool {
        switch type {
        case FindingType.editOnBase, FindingType.forgottenChange: return suggestedTrama != nil
        case FindingType.merged: return repo != nil
        default: return false
        }
    }
}
