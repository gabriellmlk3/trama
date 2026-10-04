import Foundation
import XCTest
@testable import trama

final class TextTests: XCTestCase {
    func testSlugify() {
        XCTAssertEqual(slugify("Surcharge noturno"), "surcharge-noturno")
        XCTAssertEqual(slugify("Onboarding do prestador!"), "onboarding-do-prestador")
        XCTAssertEqual(slugify("  Ação: Pix / Repasse D+1 "), "acao-pix-repasse-d-1")
        XCTAssertEqual(slugify("ÇÃO"), "cao")
        XCTAssertEqual(slugify("!!!"), "")
    }

    func testRelativeTime() {
        let now = Date()
        let t = Int64(now.timeIntervalSince1970)
        XCTAssertEqual(relativeTime(t - 10, now: now), "agora")
        XCTAssertEqual(relativeTime(t - 8 * 60, now: now), "há 8 min")
        XCTAssertEqual(relativeTime(t - 3 * 3600, now: now), "há 3 h")
        XCTAssertEqual(relativeTime(t - 30 * 3600, now: now), "ontem")
        XCTAssertEqual(relativeTime(t - 6 * 86400, now: now), "há 6 dias")
        XCTAssertEqual(relativeTime(nil), "")
    }

    func testTable() {
        XCTAssertEqual(table([["a", "bb", "c"], ["ddd", "e", "f"]]), "a    bb  c\nddd  e   f\n")
    }

    func testArguments() throws {
        let a = try Arguments.parse(["Surcharge", "noturno", "--repos", "api,admin", "--sem-fetch", "--base=develop"], valueFlags: ["repos", "base"])
        XCTAssertEqual(a.text(from: 0), "Surcharge noturno")
        XCTAssertEqual(a.value("repos"), "api,admin")
        XCTAssertEqual(a.value("base"), "develop")
        XCTAssertTrue(a.has("sem-fetch"))
        XCTAssertThrowsError(try Arguments.parse(["--repos"], valueFlags: ["repos"]))
    }
}
