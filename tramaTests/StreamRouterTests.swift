import Foundation
import XCTest
@testable import trama

final class StreamRouterTests: XCTestCase {
    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    func testBeforeTheFirstPromptEverythingIsOutput() {
        let router = StreamRouter()
        XCTAssertEqual(router.feed(bytes("carregando\r\n")), [.output(bytes("carregando\r\n"))])
    }

    func testOnlyBytesBetweenCommandStartAndEndAreOutput() {
        let router = StreamRouter()
        _ = router.feed(bytes("\u{1b}]133;A\u{07}% \u{1b}]133;B\u{07}"))
        let events = router.feed(bytes("ls\r\n\u{1b}]633;E;ls\u{07}\u{1b}]133;C\u{07}a.txt\r\n\u{1b}[31mb\u{1b}[0m\r\n\u{1b}]133;D;0\u{07}\u{1b}]7;file://h/tmp\u{07}\u{1b}]133;A\u{07}% "))
        XCTAssertEqual(events, [
            .metadata(.commandText("ls")),
            .commandBegan,
            .metadata(.commandStart),
            .output(bytes("a.txt\r\n\u{1b}[31mb\u{1b}[0m\r\n")),
            .commandEnded(exitCode: 0),
            .metadata(.commandFinished(exitCode: 0)),
            .metadata(.directory("/tmp")),
            .metadata(.promptStart),
        ])
    }

    func testFirstPromptSignalsReadyOnlyOnce() {
        let router = StreamRouter()
        let first = router.feed(bytes("boas-vindas\u{1b}]133;A\u{07}"))
        XCTAssertEqual(first, [.output(bytes("boas-vindas")), .sessionReady, .metadata(.promptStart)])
        XCTAssertEqual(router.feed(bytes("\u{1b}]133;A\u{07}")), [.metadata(.promptStart)])
    }

    func testOtherEscapeSequencesAndSplitChunksPassThroughIntact() {
        let router = StreamRouter()
        _ = router.feed(bytes("\u{1b}]133;A\u{07}\u{1b}]133;C\u{07}"))
        var output: [UInt8] = []
        for chunk in ["x\u{1b}", "[2Ky\u{1b}]0;tit", "ulo\u{07}z\u{1b}]13", "3;D;1\u{07}"] {
            for case .output(let part) in router.feed(bytes(chunk)) { output += part }
        }
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "x\u{1b}[2Ky\u{1b}]0;titulo\u{07}z")
    }
}
