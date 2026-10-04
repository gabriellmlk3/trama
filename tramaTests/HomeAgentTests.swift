import XCTest
@testable import trama

final class HomeAgentTests: XCTestCase {
    func testInstructionsRequireProposalInsteadOfCreating() {
        let text = HomeAgent.instructions
        XCTAssertTrue(text.contains("trama estado"))
        XCTAssertTrue(text.contains("trama propor existente"))
        XCTAssertTrue(text.contains("trama propor nova"))
        XCTAssertTrue(text.contains("NÃO crie nem altere nada"))
        XCTAssertTrue(text.contains("Não rode `trama nova`"))
    }

    func testInstructionsCoverArchiveAndRemoveWithConfirmation() {
        let text = HomeAgent.instructions
        XCTAssertTrue(text.contains("trama arquivar"))
        XCTAssertTrue(text.contains("trama remover"))
        XCTAssertTrue(text.contains("peça confirmação no chat"))
        XCTAssertTrue(text.contains("sem `--forcar` e sem `--branches`"))
    }

    func testAdjustmentRequestMentionsProposeCommand() {
        let text = HomeAgent.adjustmentRequest("trocar o repo")
        XCTAssertTrue(text.contains("trama propor"))
        XCTAssertTrue(text.hasSuffix("trocar o repo"))
    }

    @MainActor
    func testSessionUsesHomeInstructionsAndAllowsTramaCommand() {
        XCTAssertEqual(GeneralAgentSession.role, HomeAgent.instructions)
        XCTAssertTrue(GeneralAgentSession.allowedTools.contains("Bash(trama *)"))
    }

    func testAgentPathPutsTramaLinkFirst() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let path = Integration.agentPath(root: lab.root, current: "/usr/bin:/bin")
        let parts = path.split(separator: ":").map(String.init)
        XCTAssertTrue(parts.suffix(2) == ["/usr/bin", "/bin"])
        if let exe = Integration.embeddedCommand {
            XCTAssertEqual(parts.first, Paths.join(lab.root, ".trama", "bin"))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: Paths.join(lab.root, ".trama", "bin", "trama")), exe)
        }
    }
}
