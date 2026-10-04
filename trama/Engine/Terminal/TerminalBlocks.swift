import Foundation

public struct TerminalBlock: Identifiable, Equatable {
    public let id: Int
    public var command: String
    public var directory: String?
    public let startedAt: Date
    public var finishedAt: Date?
    public var exitCode: Int32?

    public var isRunning: Bool { finishedAt == nil }

    public var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

public struct BlockTracker {
    private static let capacity = 500

    public private(set) var blocks: [TerminalBlock] = []
    public private(set) var directory: String?
    private var pendingCommand = ""
    private var nextID = 0

    public init() {}

    @discardableResult
    public mutating func apply(_ marker: TerminalMarker, at date: Date) -> Bool {
        switch marker {
        case .directory(let path):
            let changed = directory != path
            directory = path
            return changed
        case .commandText(let text):
            pendingCommand = text
            return false
        case .commandStart:
            blocks.append(TerminalBlock(id: nextID, command: pendingCommand, directory: directory, startedAt: date))
            nextID += 1
            pendingCommand = ""
            if blocks.count > Self.capacity {
                blocks.removeFirst(blocks.count - Self.capacity)
            }
            return true
        case .commandFinished(let exitCode):
            guard let index = blocks.lastIndex(where: \.isRunning) else { return false }
            blocks[index].finishedAt = date
            blocks[index].exitCode = exitCode
            return true
        case .promptStart, .promptEnd:
            return false
        }
    }
}
