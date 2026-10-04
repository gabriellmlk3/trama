import Foundation
import XCTest
@testable import trama

final class CapsuleTests: XCTestCase {
    func testSections() {
        let t = Trama(slug: "x", title: "X", branch: "trama/x", base: nil, repos: ["a", "b"], state: TramaState.active, task: nil, createdAt: 0)
        var doc = CapsuleDoc.new(t, goal: "")
        XCTAssertTrue(doc.contains("_("))
        doc = CapsuleDoc.set(doc, section: CapsuleSection.goal, content: "Fazer Y")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.decisions, line: "- 2026-09-30 10:00 · você: usar Z")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.decisions, line: "- 2026-09-30 10:05 · agente · api: janela usa fuso da cidade")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.pending, line: "- [ ] testar 5h59")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.pending, line: "- [ ] texto do selo")
        doc = CapsuleDoc.insert(doc, section: CapsuleSection.handoffs, line: "- [ ] 2026-09-30 10:06 · rebocs_api → rebocs-android · agente · api: exibir selo")
        let c = CapsuleDoc.parse(slug: "x", path: "/tmp/x.md", doc: doc)
        XCTAssertEqual(c.title, "X")
        XCTAssertEqual(c.goal, "Fazer Y")
        XCTAssertEqual(c.decisions.count, 2)
        XCTAssertEqual(c.decisions[1].author, "agente · api")
        XCTAssertEqual(c.decisions[1].text, "janela usa fuso da cidade")
        XCTAssertNotNil(c.decisions[1].timestamp)
        XCTAssertEqual(c.handoffs.count, 1)
        XCTAssertEqual(c.handoffs[0].from, "rebocs_api")
        XCTAssertEqual(c.handoffs[0].to, "rebocs-android")
        XCTAssertEqual(c.handoffs[0].author, "agente · api")
        XCTAssertEqual(c.handoffs[0].text, "exibir selo")
        XCTAssertFalse(c.handoffs[0].done)
        XCTAssertEqual(c.pending.map(\.text), ["testar 5h59", "texto do selo"])

        let (doc2, n) = CapsuleDoc.mark(doc, section: CapsuleSection.pending) { $0.index == 2 }
        let c2 = CapsuleDoc.parse(slug: "x", path: "", doc: doc2)
        XCTAssertEqual(n, 1)
        XCTAssertFalse(c2.pending[0].done)
        XCTAssertTrue(c2.pending[1].done)
        XCTAssertEqual(doc2.components(separatedBy: "## \(CapsuleSection.journal)").count, 2)
        XCTAssertEqual(doc2.components(separatedBy: "## \(CapsuleSection.handoffs)").count, 2)
    }

    func testMissingSectionIsCreated() {
        let doc = CapsuleDoc.insert("# Só título\n", section: CapsuleSection.decisions, line: "- 2026-09-30 10:00 · você: ok")
        XCTAssertEqual(CapsuleDoc.parse(slug: "x", path: "", doc: doc).decisions.count, 1)
    }
}
