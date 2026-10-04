import Foundation

public struct AgentAttachment: Hashable, Identifiable, Sendable {
    public var path: String
    public var name: String

    public var id: String { path }

    public var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"].contains((name as NSString).pathExtension.lowercased())
    }
}

public enum AgentAttachments {
    static let maxBytes: Int64 = 200 * 1024 * 1024

    public static func directory(root: String) -> String {
        Paths.join(root, ".trama", "attachments")
    }

    public static func store(file source: String, in directory: String) throws -> AgentAttachment {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source, isDirectory: &isDirectory) else {
            throw TramaError("não encontrei o arquivo \(Paths.name(source))")
        }
        guard !isDirectory.boolValue else {
            throw TramaError("\(Paths.name(source)) é uma pasta · anexe só arquivos")
        }
        let size = (try? fm.attributesOfItem(atPath: source)[.size] as? Int64) ?? 0
        guard size <= maxBytes else {
            throw TramaError("\(Paths.name(source)) passa de 200 MB")
        }
        let target = try destination(named: Paths.name(source), in: directory)
        try fm.copyItem(atPath: source, toPath: target)
        return AgentAttachment(path: target, name: Paths.name(target))
    }

    public static func store(data: Data, name: String, in directory: String) throws -> AgentAttachment {
        let target = try destination(named: name, in: directory)
        try data.write(to: URL(fileURLWithPath: target), options: .atomic)
        return AgentAttachment(path: target, name: Paths.name(target))
    }

    public static func discard(_ attachment: AgentAttachment) {
        let folder = Paths.parent(attachment.path)
        guard Paths.name(Paths.parent(folder)) == "attachments" else { return }
        try? FileManager.default.removeItem(atPath: folder)
    }

    public static func prompt(text: String, files: [AgentAttachment]) -> String {
        guard !files.isEmpty else { return text }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = body.isEmpty ? "Veja os arquivos anexados." : body
        return lead + "\n\nArquivos anexados (leia cada um com a ferramenta Read):\n" + files.map { "- \($0.path)" }.joined(separator: "\n")
    }

    private static func destination(named name: String, in directory: String) throws -> String {
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let folder = Paths.join(directory, UUID().uuidString.prefix(8).lowercased())
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return Paths.join(folder, clean.isEmpty ? "anexo" : clean)
    }
}
