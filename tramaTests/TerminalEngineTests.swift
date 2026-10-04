import Foundation
import XCTest
@testable import trama

@MainActor
final class TerminalEngineTests: XCTestCase {
    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 15, _ message: String = "") async {
        let limit = Date().addingTimeInterval(timeout)
        while !condition(), Date() < limit {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "tempo esgotado: \(message)")
    }

    func testEngineSplitsSessionIntoBlocksWithCapturedOutput() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\necho bem-vindo\n")
        let engine = SwiftTermEngine(homeDirectory: home)
        engine.start(directory: home, command: nil)
        defer { engine.terminate() }

        XCTAssertEqual(engine.mode, .starting)
        await waitUntil(engine.mode == .ready, "primeiro prompt")
        XCTAssertTrue(engine.startupOutput.plain.contains("bem-vindo"))

        let longLine = String(repeating: "x", count: 130)
        engine.submit("printf 'ola\\n\\033[31mvermelho\\033[0m\\n'; echo \(longLine)")
        await waitUntil(engine.blocks.count == 1 && engine.blocks[0].exitCode != nil, "primeiro bloco")
        XCTAssertEqual(engine.mode, .ready)
        let first = try XCTUnwrap(engine.output(for: engine.blocks[0].id))
        XCTAssertEqual(first.plain, "ola\nvermelho\n" + longLine)
        XCTAssertFalse(first.plain.contains("%"), "o prompt não pode vazar para a saída")

        engine.submit("sleep 0.6; echo depois")
        await waitUntil(engine.mode == .running, "modo executando")
        XCTAssertEqual(engine.blocks.count, 2)
        XCTAssertTrue(engine.blocks[1].isRunning)
        await waitUntil(engine.mode == .ready && engine.blocks[1].exitCode != nil, "segundo bloco")
        XCTAssertEqual(engine.output(for: engine.blocks[1].id)?.plain, "depois")

        engine.submit("false")
        await waitUntil(engine.blocks.count == 3 && engine.blocks[2].exitCode != nil, "terceiro bloco")
        XCTAssertEqual(engine.blocks[2].exitCode, 1)
        XCTAssertEqual(engine.output(for: engine.blocks[2].id)?.isEmpty, true)
        XCTAssertEqual(engine.blocks.map(\.command), [
            "printf 'ola\\n\\033[31mvermelho\\033[0m\\n'; echo \(longLine)",
            "sleep 0.6; echo depois",
            "false",
        ])
    }

    func testMultilineCommandIsSubmittedAsOneBlock() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\n")
        let engine = SwiftTermEngine(homeDirectory: home)
        engine.start(directory: home, command: nil)
        defer { engine.terminate() }
        await waitUntil(engine.mode == .ready, "primeiro prompt")
        engine.submit("for i in 1 2 3\ndo\necho item$i\ndone")
        await waitUntil(engine.blocks.count == 1 && engine.blocks[0].exitCode != nil, "bloco multilinha")
        XCTAssertEqual(engine.output(for: engine.blocks[0].id)?.plain, "item1\nitem2\nitem3")
    }

    func testExitingTheShellClosesTheRunningBlockAndReportsExit() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\n")
        let engine = SwiftTermEngine(homeDirectory: home)
        nonisolated(unsafe) var exitCode: Int32??
        engine.onExit = { exitCode = .some($0) }
        engine.start(directory: home, command: nil)
        await waitUntil(engine.mode == .ready, "primeiro prompt")
        engine.submit("exit 4")
        await waitUntil(exitCode != nil, "saída do shell")
        XCTAssertEqual(exitCode, .some(4))
        XCTAssertEqual(engine.blocks.last?.isRunning, false)
        XCTAssertEqual(engine.mode, .ready)
    }

    func testWithoutShellIntegrationTheSessionStaysClassic() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\n")
        let engine = SwiftTermEngine(homeDirectory: home, shellIntegration: false)
        engine.start(directory: home, command: nil)
        defer { engine.terminate() }
        engine.submit("echo classico")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(engine.mode, .starting)
        XCTAssertTrue(engine.blocks.isEmpty)
    }
}
