import Foundation

public enum HomeAgent {
    public static func prompt(request: String, executable: String) -> String {
        let trama = AgentSkill.command(executable)
        let text = request.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "Você é o agent geral do Trama, na home do app. Pedido do usuário: \(text) "
            + "Comando: \(trama) (`\(trama) ajuda` lista os comandos; a skill trama, se instalada, descreve o fluxo). "
            + "Passos: 1) rode `\(trama) estado` e compare o pedido com as tramas ativas e estacionadas (título, repositórios, objetivo, decisões e pendências na cápsula). "
            + "2) NÃO altere nada ainda: apresente UMA proposta e espere o 'ok' do usuário. A proposta é um destes caminhos: "
            + "(a) reaproveitar uma trama existente, dizendo qual e por quê, e qual handoff ou pendência você registraria; "
            + "(b) ampliar uma trama existente com `\(trama) puxar <trama> <repo> --motivo`; "
            + "(c) criar uma nova, com título, repositórios (motivo de cada um), branch base e objetivo. "
            + "Prefira (a) ou (b) quando o pedido for continuação do que a trama já faz; se houver dúvida entre reaproveitar e criar, pergunte. "
            + "3) Com o ok: em (a)/(b) rode `\(trama) retomar` se a trama estiver estacionada, registre o trabalho com `\(trama) handoff <repo> \"texto\" --trama <slug>` (ou `pendencia`/`objetivo`) e termine com `\(trama) abrir <trama>`, que faz o app abrir o Claude Code lá. Em (c) rode `\(trama) nova` com --repos e --objetivo e depois `\(trama) abrir <slug>`. "
            + "Não rode `\(trama) pr`, não arquive nem apague tramas."
    }
}
