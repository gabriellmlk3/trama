import Foundation
import XCTest
@testable import trama

final class HooksTests: XCTestCase {
    func testInstallRemove() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let path = lab.root + "/settings.json"
        try lab.write(path, #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say pronto"}]}]}}"#)
        let exe = "/Applications/Trama.app/Contents/MacOS/trama"
        try Hooks.install(settings: path, executable: exe)
        try Hooks.install(settings: path, executable: exe)
        XCTAssertTrue(try Hooks.status(settings: path).values.allSatisfy { $0 })
        XCTAssertEqual(Hooks.installedCommand(settings: path), exe + " hook")

        let m = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        XCTAssertEqual(m["model"] as? String, "opus", "não perde outras configurações")
        let hooks = try XCTUnwrap(m["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["Stop"] as? [Any])?.count, 2, "o hook do usuário + o do Trama, sem duplicar")
        let start = ((hooks["SessionStart"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(start?["command"] as? String, exe + " hook")
        XCTAssertNil(start?["async"], "SessionStart é síncrono")
        XCTAssertTrue(Paths.exists(path + ".antes-da-trama"))
        XCTAssertFalse(try String(contentsOfFile: path).contains("\\/"), "caminhos sem barras escapadas")

        XCTAssertFalse(Hooks.repointIfNeeded(settings: path, executable: exe))
        XCTAssertTrue(Hooks.repointIfNeeded(settings: path, executable: "/Users/x/Applications/Trama.app/Contents/MacOS/trama"))
        XCTAssertEqual(Hooks.installedCommand(settings: path), "/Users/x/Applications/Trama.app/Contents/MacOS/trama hook")

        XCTAssertEqual(try Hooks.remove(settings: path), Hooks.events.count)
        let after = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let left = try XCTUnwrap(after["hooks"] as? [String: Any])
        XCTAssertEqual(Array(left.keys), ["Stop"])

        try lab.write(path, "{ quebrado")
        XCTAssertThrowsError(try Hooks.install(settings: path, executable: exe), "não sobrescreve settings.json inválido")
    }

    func testCommandWithSpace() {
        XCTAssertEqual(Hooks.command("/Users/x/My Apps/Trama.app/Contents/MacOS/trama"), "\"/Users/x/My Apps/Trama.app/Contents/MacOS/trama\" hook")
    }
}
