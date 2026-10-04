import XCTest
@testable import trama

final class HomeAgentTests: XCTestCase {
    func testPromptAsksForProposalBeforeCreating() {
        let prompt = HomeAgent.prompt(request: "ajustar login\nno api e no admin", executable: "/Applications/My Apps/Trama.app/Contents/MacOS/trama")
        XCTAssertFalse(prompt.contains("\n"))
        XCTAssertTrue(prompt.contains("ajustar login no api e no admin"))
        XCTAssertTrue(prompt.contains("\"/Applications/My Apps/Trama.app/Contents/MacOS/trama\" estado"))
        XCTAssertTrue(prompt.contains("NÃO altere nada ainda"))
    }
}
