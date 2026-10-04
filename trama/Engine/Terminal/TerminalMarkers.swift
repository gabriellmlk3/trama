import Foundation

public enum TerminalMarker: Equatable {
    case promptStart
    case promptEnd
    case commandStart
    case commandFinished(exitCode: Int32?)
    case commandText(String)
    case directory(String)
}

public enum StreamPiece: Equatable {
    case marker(TerminalMarker)
    case bytes([UInt8])
}

public final class MarkerScanner {
    private enum State {
        case ground
        case escape
        case osc
        case oscEscape
    }

    private static let limit = 8192
    private var state = State.ground
    private var raw: [UInt8] = []
    private var body: [UInt8] = []
    private var overflowed = false

    public init() {}

    public func feed(_ bytes: [UInt8]) -> [TerminalMarker] {
        split(bytes).compactMap {
            if case .marker(let marker) = $0 { return marker }
            return nil
        }
    }

    public func split(_ bytes: [UInt8]) -> [StreamPiece] {
        var pieces: [StreamPiece] = []
        var passthrough: [UInt8] = []

        func flush() {
            if !passthrough.isEmpty {
                pieces.append(.bytes(passthrough))
                passthrough.removeAll(keepingCapacity: true)
            }
        }

        func finish() {
            state = .ground
            if !overflowed, let marker = Self.parse(body) {
                flush()
                pieces.append(.marker(marker))
            } else {
                passthrough.append(contentsOf: raw)
            }
            raw.removeAll(keepingCapacity: true)
        }

        for byte in bytes {
            switch state {
            case .ground:
                if byte == 0x1b {
                    state = .escape
                } else {
                    passthrough.append(byte)
                }
            case .escape:
                if byte == 0x5d {
                    state = .osc
                    raw = [0x1b, 0x5d]
                    body.removeAll(keepingCapacity: true)
                    overflowed = false
                } else if byte == 0x1b {
                    passthrough.append(0x1b)
                } else {
                    passthrough.append(0x1b)
                    passthrough.append(byte)
                    state = .ground
                }
            case .osc:
                raw.append(byte)
                if byte == 0x07 {
                    finish()
                } else if byte == 0x1b {
                    state = .oscEscape
                } else if byte == 0x18 || byte == 0x1a {
                    state = .ground
                    passthrough.append(contentsOf: raw)
                    raw.removeAll(keepingCapacity: true)
                } else if body.count < Self.limit {
                    body.append(byte)
                } else {
                    overflowed = true
                }
            case .oscEscape:
                raw.append(byte)
                if byte == 0x5c {
                    finish()
                } else {
                    state = .ground
                    passthrough.append(contentsOf: raw)
                    raw.removeAll(keepingCapacity: true)
                }
            }
        }
        flush()
        return pieces
    }

    private static func parse(_ body: [UInt8]) -> TerminalMarker? {
        let text = String(decoding: body, as: UTF8.self)
        guard let separator = text.firstIndex(of: ";") else { return nil }
        let code = text[..<separator]
        let rest = String(text[text.index(after: separator)...])
        switch code {
        case "133":
            switch rest.first {
            case "A": return .promptStart
            case "B": return .promptEnd
            case "C": return .commandStart
            case "D":
                let fields = rest.split(separator: ";", omittingEmptySubsequences: false)
                return .commandFinished(exitCode: fields.count > 1 ? Int32(fields[1]) : nil)
            default: return nil
            }
        case "633":
            guard rest.hasPrefix("E;") else { return nil }
            return .commandText(unescape(String(rest.dropFirst(2))))
        case "7":
            return directory(fromURL: rest).map(TerminalMarker.directory)
        default:
            return nil
        }
    }

    private static func directory(fromURL url: String) -> String? {
        guard url.hasPrefix("file://") else { return nil }
        let afterScheme = url.dropFirst("file://".count)
        guard let slash = afterScheme.firstIndex(of: "/") else { return nil }
        return String(afterScheme[slash...]).removingPercentEncoding
    }

    private static func unescape(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var result: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x5c, index + 1 < bytes.count {
                let next = bytes[index + 1]
                if next == 0x5c {
                    result.append(0x5c)
                    index += 2
                    continue
                }
                if next == 0x78, index + 3 < bytes.count,
                   let value = UInt8(String(decoding: bytes[(index + 2)...(index + 3)], as: UTF8.self), radix: 16) {
                    result.append(value)
                    index += 4
                    continue
                }
            }
            result.append(byte)
            index += 1
        }
        return String(decoding: result, as: UTF8.self)
    }
}

public enum StreamEvent: Equatable {
    case sessionReady
    case commandBegan
    case output([UInt8])
    case commandEnded(exitCode: Int32?)
    case metadata(TerminalMarker)
}

public final class StreamRouter {
    private enum Region {
        case output
        case prompt
    }

    private let scanner = MarkerScanner()
    private var region = Region.output
    private var integrated = false

    public init() {}

    public func feed(_ bytes: [UInt8]) -> [StreamEvent] {
        var events: [StreamEvent] = []
        for piece in scanner.split(bytes) {
            switch piece {
            case .bytes(let chunk):
                guard region == .output else { continue }
                if case .output(let previous)? = events.last {
                    events[events.count - 1] = .output(previous + chunk)
                } else {
                    events.append(.output(chunk))
                }
            case .marker(let marker):
                switch marker {
                case .promptStart:
                    if !integrated {
                        integrated = true
                        events.append(.sessionReady)
                    }
                    region = .prompt
                case .commandStart:
                    region = .output
                    events.append(.commandBegan)
                case .commandFinished(let code):
                    region = .prompt
                    events.append(.commandEnded(exitCode: code))
                case .promptEnd:
                    break
                case .commandText, .directory:
                    break
                }
                events.append(.metadata(marker))
            }
        }
        return events
    }
}
