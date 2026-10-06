import Foundation
import XCTest
@testable import trama

final class StateStabilityTests: XCTestCase {
    func testFullStateIsStableBetweenReadsSoTheInterfaceIsNotRepublished() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Estavel", repos: ["api", "admin"], noFetch: true))
        try lab.commit(w.worktreePath(t.slug, "rebocs_api"), "x.txt", "x\n", "x")
        try lab.write(w.worktreePath(t.slug, "rebocs-admin") + "/sujo.txt", "a\n")

        let first = try w.fullState()
        Thread.sleep(forTimeInterval: 1.1)
        let second = try w.fullState()
        XCTAssertNotEqual(first.generatedAt, second.generatedAt)
        XCTAssertTrue(first.sameContent(as: second))

        try lab.write(w.worktreePath(t.slug, "rebocs-admin") + "/outro.txt", "b\n")
        XCTAssertFalse(first.sameContent(as: try w.fullState()), "uma mudança real continua sendo publicada")
    }
}
