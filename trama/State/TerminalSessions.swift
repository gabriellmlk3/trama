import AppKit
import Foundation
import SwiftTerm

@MainActor
final class TerminalSession: Identifiable {
    let id: String
    let title: String
    let path: String
    let view: LocalProcessTerminalView
    var running = true

    init(id: String, title: String, path: String, view: LocalProcessTerminalView) {
        self.id = id
        self.title = title
        self.path = path
        self.view = view
    }
}

@MainActor
final class TerminalStore: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    @Published var sessions: [TerminalSession] = []
    @Published var selectedID: TerminalSession.ID?
    @Published var expanded = false
    @Published var height: CGFloat = 260

    var selected: TerminalSession? {
        sessions.first { $0.id == selectedID }
    }

    private func key(path: String, command: String?) -> String {
        path + "\0" + (command ?? "")
    }

    func open(path: String, command: String?, title: String) {
        let id = key(path: path, command: command)
        if let existing = sessions.first(where: { $0.id == id }), existing.running {
            selectedID = id
            expanded = true
            return
        }
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = self
        view.startProcess(executable: "/bin/zsh", args: ["-il"], currentDirectory: path)
        if let command, !command.isEmpty {
            view.process.send(data: Array((command + "\n").utf8)[...])
        }
        let session = TerminalSession(id: id, title: title, path: path, view: view)
        sessions.append(session)
        selectedID = id
        expanded = true
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
        session.view.terminate()
        sessions.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = sessions.last?.id
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            guard let view = source as? LocalProcessTerminalView,
                  let session = self.sessions.first(where: { $0.view === view }) else { return }
            session.running = false
            self.objectWillChange.send()
        }
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
