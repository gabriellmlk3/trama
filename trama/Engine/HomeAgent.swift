import Foundation

public enum HomeAgent {
    public static func command(prompt: String, stateDir: String) throws -> String {
        let file = Paths.join(stateDir, "prompts", UUID().uuidString + ".md")
        try File.write(prompt, to: file)
        let quoted = "'" + file.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "claude \"$(cat \(quoted); rm -f \(quoted))\""
    }

    public static let terminalTitle = "agent geral · claude"

    public static func prompt(request: String, executable: String) -> String {
        let trama = AgentSkill.command(executable)
        let text = request.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "Você é o agent geral do Trama, na home do app. Pedido do usuário: \(text) "
            + "Comando: \(trama) (`\(trama) ajuda` lista os comandos; a skill trama, se instalada, descreve o fluxo). "
            + "Passos: 1) rode `\(trama) estado` e compare o pedido com as tramas ativas e estacionadas (título, repositórios, objetivo, decisões e pendências na cápsula). "
            + "2) NÃO crie nem altere nada: envie UMA proposta ao app, que a mostra na home para o usuário aprovar, ajustar ou descartar. Escolha o caminho: "
            + "(a) reaproveitar uma trama existente: `\(trama) propor existente <trama> --para <repo> --handoff \"o que fazer\" --motivo \"por quê\"`; "
            + "(b) ampliar uma existente com repositórios novos: o mesmo comando com `--repos a,b`; "
            + "(c) criar uma nova: `\(trama) propor nova \"Título\" --repos a,b --objetivo \"...\" --motivo \"por que cada repositório\"` (opcionais --base e --tarefa). "
            + "Prefira (a) ou (b) quando o pedido for continuação do que a trama já faz; se houver dúvida entre reaproveitar e criar, pergunte no chat antes de propor. "
            + "3) Depois de propor, diga em uma frase o que propôs e espere: o app executa a aprovação (retoma, puxa repositórios, registra o handoff ou tece a trama, e abre o Claude). Se o usuário pedir ajuste, envie outra proposta com `propor`, que substitui a anterior. "
            + "Não rode `\(trama) nova`, `\(trama) puxar`, `\(trama) pr`, nem arquive ou apague tramas."
    }

    public static func followUp(request: String) -> String {
        let text = request.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "Novo pedido do usuário, mesmas regras de antes (proponha com `propor`, não crie direto): \(text)"
    }
}
