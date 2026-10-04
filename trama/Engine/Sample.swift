import Foundation

extension Workspace {
    public static let sampleSlug = "trama-de-exemplo"
    static let sampleRepoName = "trama-exemplo"

    private static let sampleIdentity = ["-c", "user.name=Trama", "-c", "user.email=trama@localhost", "-c", "commit.gpgsign=false"]

    private func prepareSampleRepo() throws -> String {
        let dir = Paths.join(root, ".exemplo", Self.sampleRepoName)
        if !Paths.isDirectory(dir + "/.git") {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try Git.run(dir, "init", "-q", "-b", "main")
            try File.write("# trama-exemplo\n\nRepositório criado pelo Trama só para você explorar o app.\n", to: dir + "/README.md")
            try File.write("Escreva aqui o que quiser: este repositório pode ser descartado.\n", to: dir + "/notas.md")
            try Git.run(dir, ["add", "-A"])
            try Git.run(dir, Self.sampleIdentity + ["commit", "-q", "-m", "Primeiro commit"])
        }
        return dir
    }

    public func createSampleTrama() throws -> (trama: Trama, warnings: [Warning]) {
        let dir = try prepareSampleRepo()
        if !config.repos.contains(where: { $0.name == Self.sampleRepoName }) {
            try addRepo(dir)
        }
        let result = try newTrama(NewTramaOptions(
            title: "Trama de exemplo",
            repos: [Self.sampleRepoName],
            slug: Self.sampleSlug,
            goal: "Conhecer o Trama sem mexer em nenhum repositório seu.",
            noFetch: true
        ))
        let slug = result.trama.slug
        try addDecision(slug, author: "Trama", "Esta trama é um exemplo: o repositório trama-exemplo foi criado só para isso e pode ser descartado.")
        try addPending(slug, "Abrir o Claude nesta trama (⌘↩) e pedir uma mudança no README")
        try addPending(slug, "Registrar uma decisão ou uma pendência pelo campo logo abaixo do tear")
        try addPending(slug, "Remover esta trama pelo menu ⋯ quando terminar de explorar")
        return result
    }
}
