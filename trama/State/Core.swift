import Foundation

enum Core {
    static func run<T: Sendable>(_ work: @escaping @Sendable (Workspace) throws -> T) async throws -> T {
        try await inBackground {
            let w = try Workspace.open()
            if let exe = Integration.embeddedCommand {
                w.executable = exe
            }
            return try work(w)
        }
    }

    static func inBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum Integration {
    static var embeddedCommand: String? {
        guard let path = Bundle.main.executablePath else { return nil }
        return Paths.real(path)
    }

    static var terminalLink: String {
        Paths.home + "/.local/bin/trama"
    }

    static var linkDestination: String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: terminalLink)
    }

    static func isCommandInstalled() -> Bool {
        guard let exe = embeddedCommand else { return false }
        return linkDestination == exe
    }

    static func installCommand() throws {
        guard let exe = embeddedCommand else {
            throw TramaError("não encontrei o executável do app")
        }
        let fm = FileManager.default
        try fm.createDirectory(atPath: Paths.parent(terminalLink), withIntermediateDirectories: true)
        if linkDestination != nil || fm.fileExists(atPath: terminalLink) {
            try fm.removeItem(atPath: terminalLink)
        }
        try fm.createSymbolicLink(atPath: terminalLink, withDestinationPath: exe)
    }

    static func areHooksInstalled() -> Bool {
        ((try? Hooks.status()) ?? [:]).values.contains(true)
    }

    static func installHooks() throws {
        guard let exe = embeddedCommand else {
            throw TramaError("não encontrei o executável do app")
        }
        try Hooks.install(executable: exe)
    }

    static func removeHooks() throws {
        try Hooks.remove()
    }

    static func sync() {
        guard let exe = embeddedCommand else { return }
        Hooks.repointIfNeeded(executable: exe)
        if let destination = linkDestination, destination != exe, destination.contains("Trama.app") {
            try? installCommand()
        }
    }
}
