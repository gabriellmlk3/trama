import XCTest
@testable import trama

final class HomeAgentTests: XCTestCase {
    func testPromptAsksForProposalBeforeCreating() {
        let prompt = HomeAgent.prompt(request: "ajustar login\nno api e no admin", executable: "/Applications/My Apps/Trama.app/Contents/MacOS/trama")
        XCTAssertFalse(prompt.contains("\n"))
        XCTAssertTrue(prompt.contains("ajustar login no api e no admin"))
        XCTAssertTrue(prompt.contains("\"/Applications/My Apps/Trama.app/Contents/MacOS/trama\" estado"))
        XCTAssertTrue(prompt.contains("NÃO crie nem altere nada"))
    }

    func testCommandKeepsLongPromptOutOfTheTerminalLine() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let prompt = String(repeating: "texto longo ", count: 400)
        let command = try HomeAgent.command(prompt: prompt, stateDir: Paths.join(lab.root, ".trama"))
        XCTAssertLessThan(command.utf8.count, 400)
        XCTAssertTrue(command.hasPrefix("claude \"$(cat '"))
        let folder = Paths.join(lab.root, ".trama", "prompts")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try File.read(Paths.join(folder, files[0])), prompt)
    }
}
