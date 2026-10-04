import Foundation
import XCTest
@testable import trama

final class ProposalTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func testNewProposalResolvesAliasesAndPersists() throws {
        let w = try lab.workspace()
        XCTAssertNil(w.currentProposal())
        let p = try w.proposeNew(title: "Surcharge noturno", repos: ["api,admin,api"], goal: "Cobrar mais", base: nil, task: nil, reason: "toca os dois")
        XCTAssertEqual(p.repos, ["rebocs_api", "rebocs-admin"])
        XCTAssertEqual(w.currentProposal(), p)
        XCTAssertThrowsError(try w.proposeNew(title: "x", repos: [], goal: "", base: nil, task: nil, reason: ""))
        XCTAssertThrowsError(try w.proposeNew(title: "x", repos: ["nao-existe"], goal: "", base: nil, task: nil, reason: ""))
        w.clearProposal()
        XCTAssertNil(w.currentProposal())
    }

    func testApproveExistingResumesPullsAndRegistersHandoff() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Base", repos: ["api"], goal: "g"))
        _ = try w.park(t.slug)
        let p = try w.proposeExisting(slug: t.slug, extraRepos: ["admin"], handoffRepo: "admin", handoffText: "ajustar tela", reason: "continua")
        XCTAssertEqual(p.repos, ["rebocs-admin"])
        try w.approveExisting(p)
        let after = try w.trama(t.slug)
        XCTAssertTrue(after.isActive)
        XCTAssertEqual(Set(after.repos), ["rebocs_api", "rebocs-admin"])
        let handoffs = try w.readCapsule(t.slug).handoffs
        XCTAssertEqual(handoffs.last?.to, "rebocs-admin")
        XCTAssertEqual(handoffs.last?.text, "ajustar tela")
    }

    func testExistingProposalValidation() throws {
        let w = try lab.workspace()
        XCTAssertThrowsError(try w.proposeExisting(slug: "nao-existe", extraRepos: [], handoffRepo: nil, handoffText: nil, reason: ""))
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Base", repos: ["api"]))
        XCTAssertThrowsError(try w.proposeExisting(slug: t.slug, extraRepos: [], handoffRepo: nil, handoffText: "sem destino", reason: ""))
    }
}
