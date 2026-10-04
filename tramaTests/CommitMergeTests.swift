import Foundation
import XCTest
@testable import trama

final class CommitMergeTests: XCTestCase {
    func testMergedNameFromCommonMessages() {
        XCTAssertEqual(Commit(hash: "a", subject: "Merge branch 'trama/onboarding' into trama/melhorias", timestamp: 0, parents: 2).mergedName, "trama/onboarding")
        XCTAssertEqual(Commit(hash: "a", subject: "Merge remote-tracking branch 'origin/main' into x", timestamp: 0, parents: 2).mergedName, "origin/main")
        XCTAssertEqual(Commit(hash: "a", subject: "Merge pull request #12 from org/feature-x", timestamp: 0, parents: 2).mergedName, "org/feature-x")
        XCTAssertNil(Commit(hash: "a", subject: "Merge branch 'x'", timestamp: 0).mergedName)
        XCTAssertFalse(Commit(hash: "a", subject: "fix", timestamp: 0).isMerge)
    }

    func testCommitDecodesWithoutParentsField() throws {
        let json = #"{"hash":"abc","subject":"s","timestamp":1}"#
        XCTAssertEqual(try JSONDecoder().decode(Commit.self, from: Data(json.utf8)).parents, 1)
    }

    func testOverviewMarksRealMergeCommits() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let dir = try lab.newRepo("merge-repo")
        try lab.git(dir, "checkout", "-q", "-b", "lateral")
        try lab.commit(dir, "lateral.txt", "x", "lateral")
        try lab.git(dir, "checkout", "-q", "main")
        try lab.commit(dir, "main.txt", "y", "principal")
        try lab.git(dir, "merge", "-q", "--no-ff", "-m", "Merge branch 'lateral' into main", "lateral")

        let commits = Git.commits(dir, "HEAD", limit: 5)
        XCTAssertTrue(commits[0].isMerge)
        XCTAssertEqual(commits[0].mergedName, "lateral")
        XCTAssertFalse(commits[1].isMerge)
    }
}
