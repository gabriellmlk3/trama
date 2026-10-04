import Foundation
import XCTest
@testable import trama

final class ZshIntegrationTests: XCTestCase {
    func testRealZshProducesBlocksWithCommandStatusDirectoryAndDuration() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let home = lab.root + "/home"
        let work = lab.root + "/trabalho com espaço"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
        try lab.write(home + "/.zshrc", "PS1='% '\nexport TRAMA_TESTE_RC=carregado\n")
        let integration = lab.root + "/zsh"
        try ShellIntegration.install(at: integration)

        let scanner = MarkerScanner()
        let lock = NSLock()
        nonisolated(unsafe) var events: [(TerminalMarker, Date)] = []
        nonisolated(unsafe) var output = ""
        let exited = expectation(description: "saiu")
        let environment = ["TERM=xterm-256color", "HOME=" + home, "USER=teste", "LANG=en_US.UTF-8"]
            + ShellIntegration.environment(directory: integration, home: home)
        let pty = try PTY(
            executable: "/bin/zsh",
            arguments: ["-il"],
            environment: environment,
            directory: work,
            columns: 100,
            rows: 30,
            onOutput: { chunk in
                let markers = scanner.feed(chunk)
                lock.lock()
                output += String(decoding: chunk, as: UTF8.self)
                events += markers.map { ($0, Date()) }
                lock.unlock()
            },
            onExit: { _ in exited.fulfill() }
        )
        pty.write(Array("echo $TRAMA_TESTE_RC\nls /nao/existe\nsleep 0.3\nfor i in 1 2; do\necho $i\ndone\ncd /tmp\nexit\n".utf8))
        wait(for: [exited], timeout: 15)

        var tracker = BlockTracker()
        lock.lock()
        for (marker, date) in events { tracker.apply(marker, at: date) }
        let seenOutput = output
        lock.unlock()

        XCTAssertTrue(seenOutput.contains("carregado"), "o .zshrc do usuário precisa ser carregado")
        XCTAssertEqual(tracker.blocks.map(\.command), ["echo $TRAMA_TESTE_RC", "ls /nao/existe", "sleep 0.3", "for i in 1 2; do\necho $i\ndone", "cd /tmp", "exit"])
        XCTAssertEqual(tracker.blocks.map(\.exitCode).prefix(5), [0, 1, 0, 0, 0])
        XCTAssertEqual(tracker.blocks[0].directory, Paths.real(work))
        XCTAssertEqual(tracker.blocks[4].directory, Paths.real(work))
        XCTAssertGreaterThanOrEqual(tracker.blocks[2].duration ?? 0, 0.25)
        XCTAssertEqual(tracker.directory.map { Paths.real($0) }, Paths.real("/tmp"))
    }
}
