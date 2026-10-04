import Foundation

extension Workspace {
    private var openRequestPath: String { Paths.join(stateDir, "abrir") }

    public func requestOpen(_ slug: String) throws {
        let t = try trama(slug)
        try File.write(t.slug, to: openRequestPath)
    }

    public func takeOpenRequest() -> String? {
        guard let slug = ((try? File.read(openRequestPath)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        try? FileManager.default.removeItem(atPath: openRequestPath)
        return slug.isEmpty ? nil : slug
    }
}
