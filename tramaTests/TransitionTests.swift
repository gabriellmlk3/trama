import Foundation
import XCTest
@testable import trama

final class TransitionTests: XCTestCase {
    private func agent(_ session: String, _ state: String) -> Agent {
        Agent(session: session, trama: "t", repo: "r", cwd: "/x", state: state, message: nil, startedAt: 1, updatedAt: 1)
    }

    func testTransitionsOnlyOnChange() {
        let before = [agent("a", AgentState.working), agent("b", AgentState.waiting), agent("c", AgentState.working)]
        let after = [agent("a", AgentState.waiting), agent("b", AgentState.waiting), agent("c", AgentState.done), agent("d", AgentState.waiting), agent("e", AgentState.done)]
        let result = agentTransitions(from: before, to: after)
        XCTAssertEqual(result.map(\.agent.session), ["a", "c", "d"])
        XCTAssertEqual(result.map(\.alert), [.waiting, .done, .waiting])
    }
}
