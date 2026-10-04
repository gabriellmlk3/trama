import Foundation
import XCTest
@testable import trama

final class TerminalMarkersTests: XCTestCase {
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    func testParsesMarkersWithBellAndStringTerminators() {
        let scanner = MarkerScanner()
        let markers = scanner.feed(bytes("\u{1b}]133;A\u{07}ls\u{1b}]133;C\u{1b}\\\u{1b}]133;D;2\u{07}\u{1b}]133;D\u{07}"))
        XCTAssertEqual(markers, [.promptStart, .commandStart, .commandFinished(exitCode: 2), .commandFinished(exitCode: nil)])
    }

    func testMarkersSplitAcrossChunksAreJoined() {
        let scanner = MarkerScanner()
        var markers = scanner.feed(bytes("texto\u{1b}]13"))
        markers += scanner.feed(bytes("3;D;1"))
        markers += scanner.feed(bytes("27\u{07}"))
        XCTAssertEqual(markers, [.commandFinished(exitCode: 127)])
    }

    func testDirectoryIsDecodedAndHostDropped() {
        let scanner = MarkerScanner()
        XCTAssertEqual(scanner.feed(bytes("\u{1b}]7;file://maquina/Users/main/Meu%20Projeto\u{07}")), [.directory("/Users/main/Meu Projeto")])
    }

    func testCommandTextIsUnescaped() {
        let scanner = MarkerScanner()
        let markers = scanner.feed(bytes("\u{1b}]633;E;echo a\\x3b b\\x0aecho \\\\ç\u{07}"))
        XCTAssertEqual(markers, [.commandText("echo a; b\necho \\ç")])
    }

    func testUnknownAndOversizedSequencesAreIgnored() {
        let scanner = MarkerScanner()
        let huge = String(repeating: "x", count: 20000)
        XCTAssertEqual(scanner.feed(bytes("\u{1b}]0;titulo\u{07}\u{1b}]133;\(huge)\u{07}\u{1b}[31m\u{1b}]133;A\u{07}")), [.promptStart])
    }

    func testBlockLifecycleKeepsCommandDirectoryAndDuration() {
        var tracker = BlockTracker()
        let start = Date(timeIntervalSince1970: 1000)
        tracker.apply(.directory("/tmp/a"), at: start)
        tracker.apply(.commandFinished(exitCode: 0), at: start)
        XCTAssertTrue(tracker.blocks.isEmpty)
        tracker.apply(.commandText("make test"), at: start)
        tracker.apply(.commandStart, at: start)
        XCTAssertEqual(tracker.blocks.first?.isRunning, true)
        tracker.apply(.commandFinished(exitCode: 2), at: start.addingTimeInterval(3.5))
        XCTAssertEqual(tracker.blocks.count, 1)
        XCTAssertEqual(tracker.blocks[0].command, "make test")
        XCTAssertEqual(tracker.blocks[0].directory, "/tmp/a")
        XCTAssertEqual(tracker.blocks[0].exitCode, 2)
        XCTAssertEqual(tracker.blocks[0].duration, 3.5)
    }
}
