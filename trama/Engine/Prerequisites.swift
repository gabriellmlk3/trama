import Foundation

struct Prerequisite: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let purpose: String
    let required: Bool
    let installed: Bool
    let hint: String

    static func check() -> [Prerequisite] {
        var list = [
            Prerequisite(
                id: "git",
                title: "Git",
                purpose: "worktrees e branches",
                required: true,
                installed: FileManager.default.isExecutableFile(atPath: Git.executable),
                hint: "rode `xcode-select --install` no Terminal"
            ),
            Prerequisite(
                id: CLITool.claude.name,
                title: "Claude Code",
                purpose: "agentes dentro das tramas",
                required: true,
                installed: CLITool.claude.executable != nil,
                hint: CLITool.claude.installHint
            )
        ]
        list += ToolInstaller.all.map { tool in
            Prerequisite(
                id: tool.id,
                title: tool.title,
                purpose: tool.purpose,
                required: false,
                installed: tool.isInstalled,
                hint: "instale com `brew install \(tool.formula)`"
            )
        }
        return list
    }
}
