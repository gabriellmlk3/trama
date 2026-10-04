import AppKit
import Foundation

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id: String
    let title: String
    let path: String
    let engine: TerminalEngine
    let usesBlocks: Bool
    var running = true
    @Published var collapsed: Set<Int> = []

    var mode: TerminalMode { engine.mode }
    var blocks: [TerminalBlock] { engine.blocks }
    var startupOutput: BlockOutput { engine.startupOutput }
    var currentDirectory: String? { engine.currentDirectory ?? path }

    var history: [String] {
        var seen = Set<String>()
        return blocks.reversed().map(\.command).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    init(id: String, title: String, path: String, engine: TerminalEngine, usesBlocks: Bool) {
        self.id = id
        self.title = title
        self.path = path
        self.engine = engine
        self.usesBlocks = usesBlocks
    }

    func output(for block: TerminalBlock) -> BlockOutput? {
        engine.output(for: block.id)
    }

    func toggleCollapsed(_ block: TerminalBlock) {
        if collapsed.contains(block.id) {
            collapsed.remove(block.id)
        } else {
            collapsed.insert(block.id)
        }
    }

    func submit(_ command: String) {
        engine.submit(command)
    }

    func interrupt() {
        engine.interrupt()
    }
}

@MainActor
final class TerminalStore: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var selectedID: TerminalSession.ID?
    @Published var expanded = false
    @Published var height: CGFloat = 340

    var selected: TerminalSession? {
        sessions.first { $0.id == selectedID }
    }

    private func key(path: String, command: String?) -> String {
        path + "\0" + (command ?? "")
    }

    func open(path: String, command: String?, title: String, blocks: Bool = true) {
        let id = key(path: path, command: command)
        if let existing = sessions.first(where: { $0.id == id }), existing.running {
            selectedID = id
            expanded = true
            return
        }
        let engine = SwiftTermEngine(shellIntegration: blocks)
        let session = TerminalSession(id: id, title: title, path: path, engine: engine, usesBlocks: blocks)
        engine.onChange = { [weak session] in
            session?.objectWillChange.send()
        }
        engine.onExit = { [weak self, weak session] _ in
            guard let self, let session else { return }
            session.running = false
            self.objectWillChange.send()
        }
        sessions.append(session)
        selectedID = id
        expanded = true
        engine.start(directory: path, command: command)
    }

    @discardableResult
    func focus(path: String) -> Bool {
        guard let session = sessions.first(where: { $0.path == path && $0.running }) else { return false }
        selectedID = session.id
        expanded = true
        return true
    }

    func close(_ id: TerminalSession.ID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        session.engine.terminate()
        sessions.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = sessions.last?.id
        }
    }
}
