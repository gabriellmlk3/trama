import Foundation
import XCTest
@testable import trama

final class PTYTests: XCTestCase {
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: [UInt8] = []

        func add(_ chunk: [UInt8]) {
            lock.lock()
            bytes.append(contentsOf: chunk)
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    func testDeliversOutputAndExitCodeInOrder() throws {
        let collector = Collector()
        let exited = expectation(description: "saiu")
        nonisolated(unsafe) var code: Int32?
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh", "-c", "printf trama-ok; exit 3"],
            directory: NSTemporaryDirectory(),
            columns: 80,
            rows: 24,
            onOutput: collector.add,
            onExit: { value in
                code = value
                exited.fulfill()
            }
        )
        wait(for: [exited], timeout: 5)
        XCTAssertEqual(code, 3)
        XCTAssertTrue(collector.text.contains("trama-ok"))
        XCTAssertGreaterThan(pty.pid, 0)
    }

    func testStartsInDirectoryAndEchoesInput() throws {
        let collector = Collector()
        let exited = expectation(description: "saiu")
        let directory = Paths.real(NSTemporaryDirectory())
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh"],
            directory: directory,
            columns: 80,
            rows: 24,
            onOutput: collector.add,
            onExit: { _ in exited.fulfill() }
        )
        pty.write(Array("pwd; stty size; exit\n".utf8))
        wait(for: [exited], timeout: 5)
        XCTAssertTrue(collector.text.contains(directory.hasSuffix("/") ? String(directory.dropLast()) : directory))
        XCTAssertTrue(collector.text.contains("24 80"))
    }

    func testResizeReachesChild() throws {
        let collector = Collector()
        let exited = expectation(description: "saiu")
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh"],
            directory: nil,
            columns: 80,
            rows: 24,
            onOutput: collector.add,
            onExit: { _ in exited.fulfill() }
        )
        pty.resize(columns: 120, rows: 40)
        pty.write(Array("stty size; exit\n".utf8))
        wait(for: [exited], timeout: 5)
        XCTAssertTrue(collector.text.contains("40 120"))
    }

    func testTerminateEndsTheProcess() throws {
        let exited = expectation(description: "saiu")
        let pty = try PTY(
            executable: "/bin/sh",
            arguments: ["sh", "-c", "sleep 30"],
            directory: nil,
            columns: 80,
            rows: 24,
            onOutput: { _ in },
            onExit: { _ in exited.fulfill() }
        )
        pty.terminate()
        wait(for: [exited], timeout: 5)
    }
}
