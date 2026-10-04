import Foundation
import XCTest
@testable import trama

final class PinOrderTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func testPinAndReorderPersist() throws {
        let w = try lab.workspace()
        let (a, _) = try w.newTrama(NewTramaOptions(title: "Alfa", repos: ["api"]))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Beta", repos: ["api"]))
        XCTAssertFalse(try w.trama(a.slug).pinned)
        XCTAssertNil(try w.trama(a.slug).order)

        try w.setPinned(b.slug, true)
        try w.reorderTramas([b.slug, a.slug])

        let reloaded = try lab.workspace()
        XCTAssertTrue(try reloaded.trama(b.slug).pinned)
        XCTAssertFalse(try reloaded.trama(a.slug).pinned)
        XCTAssertEqual(try reloaded.trama(b.slug).order, 0)
        XCTAssertEqual(try reloaded.trama(a.slug).order, 1)
        XCTAssertThrowsError(try w.setPinned("nao-existe", true))
    }
}
