import AppKit
import Foundation
import SwiftTerm
import SwiftUI

private enum QueueItem {
    case stream(StreamEvent, Date)
    case exited(Int32?, Date)

    var byteCount: Int {
        if case .stream(.output(let bytes), _) = self { return bytes.count }
        return 0
    }
}

private final class EventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [QueueItem] = []

    func append(_ new: [QueueItem]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasEmpty = items.isEmpty
        items.append(contentsOf: new)
        return wasEmpty
    }

    func take(byteLimit: Int) -> (items: [QueueItem], more: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var taken = 0
        var count = 0
        while count < items.count, taken < byteLimit {
            taken += items[count].byteCount
            count += 1
        }
        let batch = Array(items[0..<count])
        items.removeFirst(count)
        return (batch, !items.isEmpty)
    }
}

@MainActor
final class SwiftTermEngine: NSObject, TerminalEngine, TerminalViewDelegate {
    private static let outputCapacity = 600

    private let terminalView = TerminalView(frame: .zero)
    private let queue = EventQueue()
    private let router = StreamRouter()
    private let homeDirectory: String?
    private let shellIntegration: Bool
    private var tracker = BlockTracker()
    private var outputs: [Int: BlockOutput] = [:]
    private var pty: PTY?

    private(set) var mode = TerminalMode.starting
    private(set) var startupOutput = BlockOutput.empty
    var onChange: (() -> Void)?
    var onExit: ((Int32?) -> Void)?

    var view: NSView { terminalView }
    var blocks: [TerminalBlock] { tracker.blocks }
    var currentDirectory: String? { tracker.directory }

    init(homeDirectory: String? = nil, shellIntegration: Bool = true) {
        self.homeDirectory = homeDirectory
        self.shellIntegration = shellIntegration
        super.init()
        terminalView.terminalDelegate = self
        terminalView.font = NSFont.monospacedSystemFont(ofSize: TerminalSnapshot.fontSize, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(Theme.loom)
        terminalView.nativeForegroundColor = NSColor(Theme.text2)
        terminalView.installColors(Theme.ansi.map { hex in
            SwiftTerm.Color(
                red: UInt16((hex >> 16) & 0xFF) * 257,
                green: UInt16((hex >> 8) & 0xFF) * 257,
                blue: UInt16(hex & 0xFF) * 257
            )
        })
    }

    func output(for blockID: Int) -> BlockOutput? {
        outputs[blockID]
    }

    func start(directory: String, command: String?) {
        let terminal = terminalView.getTerminal()
        let queue = queue
        let router = router
        do {
            pty = try PTY(
                executable: "/bin/zsh",
                arguments: ["-il"],
                environment: environment(),
                directory: directory,
                columns: terminal.cols,
                rows: terminal.rows,
                onOutput: { [weak self] chunk in
                    let events = router.feed(chunk)
                    guard !events.isEmpty else { return }
                    let now = Date()
                    if queue.append(events.map { .stream($0, now) }) {
                        DispatchQueue.main.async { self?.drain() }
                    }
                },
                onExit: { [weak self] code in
                    if queue.append([.exited(code, Date())]) {
                        DispatchQueue.main.async { self?.drain() }
                    }
                }
            )
        } catch {
            terminalView.feed(text: "\(errorMessage(error))\r\n")
            onExit?(nil)
            return
        }
        if let command, !command.isEmpty {
            submit(command)
        }
    }

    func send(_ text: String) {
        pty?.write(Array(text.utf8))
    }

    func submit(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .newlines)
        if trimmed.contains("\n") {
            send("\u{1b}[200~" + trimmed + "\u{1b}[201~\n")
        } else {
            send(trimmed + "\n")
        }
    }

    func interrupt() {
        pty?.write([0x03])
    }

    func terminate() {
        onExit = nil
        onChange = nil
        pty?.terminate()
    }

    private func environment() -> [String] {
        var values: [String: String] = [:]
        for entry in PTY.defaultEnvironment() + (shellIntegration ? shellEnvironment() : []) {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            values[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        if let homeDirectory {
            values["HOME"] = homeDirectory
        }
        return values.map { "\($0.key)=\($0.value)" }
    }

    private func shellEnvironment() -> [String] {
        let directory = NSTemporaryDirectory() + "trama-shell-\(getuid())/zsh"
        guard (try? ShellIntegration.install(at: directory)) != nil else { return [] }
        return ShellIntegration.environment(directory: directory, home: homeDirectory)
    }

    private func drain() {
        let batch = queue.take(byteLimit: 262_144)
        var changed = false
        for item in batch.items {
            switch item {
            case .stream(let event, let date):
                if handle(event, at: date) { changed = true }
            case .exited(let code, let date):
                finishRunningBlock(exitCode: code, at: date)
                changed = true
                onChange?()
                onExit?(code)
            }
        }
        if changed { onChange?() }
        if batch.more {
            DispatchQueue.main.async { [weak self] in self?.drain() }
        }
    }

    private func handle(_ event: StreamEvent, at date: Date) -> Bool {
        switch event {
        case .output(let bytes):
            terminalView.feed(byteArray: bytes[...])
            return false
        case .sessionReady:
            startupOutput = TerminalSnapshot.capture(terminalView.getTerminal())
            resetLiveView()
            mode = .ready
            return true
        case .commandBegan:
            resetLiveView()
            mode = .running
            terminalView.window?.makeFirstResponder(terminalView)
            return true
        case .commandEnded:
            storeOutputOfRunningBlock()
            resetLiveView()
            mode = .ready
            return true
        case .metadata(let marker):
            let changed = tracker.apply(marker, at: date)
            if changed { pruneOutputs() }
            return changed
        }
    }

    private func finishRunningBlock(exitCode: Int32?, at date: Date) {
        guard mode == .running else { return }
        storeOutputOfRunningBlock()
        tracker.apply(.commandFinished(exitCode: exitCode), at: date)
        resetLiveView()
        mode = .ready
    }

    private func storeOutputOfRunningBlock() {
        guard let running = tracker.blocks.last(where: \.isRunning) else { return }
        outputs[running.id] = TerminalSnapshot.capture(terminalView.getTerminal())
    }

    private func resetLiveView() {
        terminalView.feed(byteArray: [0x1b, 0x63][...])
    }

    private func pruneOutputs() {
        guard outputs.count > Self.outputCapacity else { return }
        let alive = Set(tracker.blocks.map(\.id))
        outputs = outputs.filter { alive.contains($0.key) }
    }

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        MainActor.assumeIsolated { pty?.write(bytes) }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated { pty?.resize(columns: newCols, rows: newRows) }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func scrolled(source: TerminalView, position: Double) {}
    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    nonisolated func clipboardRead(source: TerminalView) -> Data? {
        NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
    }
}
