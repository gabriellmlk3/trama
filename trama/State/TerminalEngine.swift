import AppKit
import Foundation

enum TerminalMode {
    case starting
    case ready
    case running
}

@MainActor
protocol TerminalEngine: AnyObject {
    var view: NSView { get }
    var mode: TerminalMode { get }
    var blocks: [TerminalBlock] { get }
    var startupOutput: BlockOutput { get }
    var currentDirectory: String? { get }
    var onChange: (() -> Void)? { get set }
    var onExit: ((Int32?) -> Void)? { get set }

    func output(for blockID: Int) -> BlockOutput?
    func start(directory: String, command: String?)
    func send(_ text: String)
    func submit(_ command: String)
    func interrupt()
    func terminate()
}
