import Foundation

struct GitResult {
    var output: String
    var error: String
    var code: Int32
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum ProcessRunner {
    static let launchFailureCode: Int32 = -1

    static func run(
        _ executable: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 0
    ) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        if let environment { process.environment = environment }
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return GitResult(output: "", error: error.localizedDescription, code: launchFailureCode)
        }
        var timer: DispatchWorkItem?
        if timeout > 0 {
            let item = DispatchWorkItem { if process.isRunning { process.terminate() } }
            timer = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }
        let errorBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBox.data = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timer?.cancel()
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\n") { text.removeLast() }
        return GitResult(output: text, error: String(decoding: errorBox.data, as: UTF8.self), code: process.terminationStatus)
    }

    static func runInheritingOutput(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return launchFailureCode
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func spawnDetached(_ executable: String, _ arguments: [String], environment: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
