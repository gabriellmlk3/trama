import Foundation
import XCTest
@testable import trama

final class AgentSkillTests: XCTestCase {
    func testInstallRefreshRemove() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let exe = "/Applications/Trama.app/Contents/MacOS/trama"
        XCTAssertFalse(AgentSkill.isInstalled(home: lab.root))
        try AgentSkill.install(executable: exe, home: lab.root)
        XCTAssertTrue(AgentSkill.isInstalled(home: lab.root))
        let text = try XCTUnwrap(try File.read(AgentSkill.path(home: lab.root)))
        XCTAssertTrue(text.hasPrefix("---\nname: trama\n"))
        for command in CLI.commands.keys where ["nova", "ls", "estacionar", "retomar", "arquivar", "pr", "puxar", "handoff"].contains(command) {
            XCTAssertTrue(text.contains("trama \(command)"), command)
        }
        XCTAssertFalse(AgentSkill.refreshIfInstalled(executable: exe, home: lab.root))
        XCTAssertTrue(AgentSkill.refreshIfInstalled(executable: "/Users/x/Trama.app/Contents/MacOS/trama", home: lab.root))
        XCTAssertTrue(try AgentSkill.remove(home: lab.root))
        XCTAssertFalse(Paths.exists(Paths.parent(AgentSkill.path(home: lab.root))))
    }

    func testDoesNotRemoveUserSkill() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.write(AgentSkill.path(home: lab.root), "---\nname: trama\n---\nminha")
        XCTAssertFalse(AgentSkill.isInstalled(home: lab.root))
        XCTAssertFalse(try AgentSkill.remove(home: lab.root))
        XCTAssertTrue(Paths.exists(AgentSkill.path(home: lab.root)))
    }
}
