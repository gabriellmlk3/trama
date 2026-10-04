import AppKit
import Foundation

@MainActor
enum Terminal {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func open(_ path: String, withApp app: String) throws {
        try EditorDetection.launch(path, app: app)
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func choosePaths(multiple: Bool, title: String) -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = multiple
        panel.prompt = "Escolher"
        panel.message = title
        return panel.runModal() == .OK ? panel.urls.map { $0.path } : []
    }
}
