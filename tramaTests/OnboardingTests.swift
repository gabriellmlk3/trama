import Foundation
import XCTest
@testable import trama

final class OnboardingTests: XCTestCase {
    var lab: Lab!
    var defaults: UserDefaults!
    private var suite = ""

    override func setUpWithError() throws {
        lab = try Lab()
        suite = "trama-onboarding-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        lab.cleanup()
        defaults.removePersistentDomain(forName: suite)
        unsetenv("TRAMA_CLAUDE")
    }

    func testSampleTramaIsCreatedOnceWithCapsule() throws {
        let w = try lab.workspace()
        let (t, warnings) = try w.createSampleTrama()
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(t.slug, Workspace.sampleSlug)
        XCTAssertEqual(t.repos, [Workspace.sampleRepoName])
        XCTAssertTrue(Paths.isDirectory(w.worktreePath(t.slug, Workspace.sampleRepoName)))
        XCTAssertEqual(try Git.run(w.worktreePath(t.slug, Workspace.sampleRepoName), "branch", "--show-current"), t.branch)
        let capsule = try XCTUnwrap(try File.read(w.capsulePath(t.slug)))
        XCTAssertTrue(capsule.contains("exemplo"))
        XCTAssertTrue(capsule.contains("- [ ] Remover esta trama"))
        XCTAssertThrowsError(try w.createSampleTrama())
        XCTAssertEqual(try w.tramas().filter { $0.slug == Workspace.sampleSlug }.count, 1)
        XCTAssertEqual(w.config.repos.filter { $0.name == Workspace.sampleRepoName }.count, 1)
    }

    func testSampleTramaCanBeRecreatedAfterRemoval() throws {
        let w = try lab.workspace()
        let (t, _) = try w.createSampleTrama()
        _ = try w.remove(t.slug, deleteBranches: true)
        let (again, _) = try w.createSampleTrama()
        XCTAssertEqual(again.slug, Workspace.sampleSlug)
        XCTAssertEqual(w.config.repos.filter { $0.name == Workspace.sampleRepoName }.count, 1)
    }

    func testPrerequisitesReportClaudeAvailability() {
        setenv("TRAMA_CLAUDE", "/nao/existe/claude", 1)
        var list = Prerequisite.check()
        XCTAssertEqual(list.first { $0.id == "claude" }?.installed, false)
        setenv("TRAMA_CLAUDE", "/bin/sh", 1)
        list = Prerequisite.check()
        XCTAssertEqual(list.first { $0.id == "claude" }?.installed, true)
        XCTAssertEqual(list.filter(\.required).map(\.id), ["git", "claude"])
        XCTAssertEqual(Set(list.filter { !$0.required }.map(\.id)), Set(ToolInstaller.all.map(\.id)))
    }

    func testSeenVersionMigratesLegacyFlag() {
        XCTAssertEqual(OnboardingPreference.seenVersion(defaults), 0)
        defaults.set(true, forKey: OnboardingPreference.seen)
        XCTAssertEqual(OnboardingPreference.seenVersion(defaults), 1)
        OnboardingPreference.markSeen(defaults)
        XCTAssertEqual(OnboardingPreference.seenVersion(defaults), OnboardingPage.currentVersion)
    }

    func testPagesToShowOnlyIncludesNewerPages() {
        XCTAssertEqual(OnboardingPreference.pages(seenVersion: 0).count, OnboardingPage.all.count)
        XCTAssertTrue(OnboardingPreference.pages(seenVersion: OnboardingPage.currentVersion).isEmpty)
        XCTAssertTrue(OnboardingPage.all.allSatisfy { $0.since <= OnboardingPage.currentVersion })
        XCTAssertEqual(Set(OnboardingPage.all.map(\.id)).count, OnboardingPage.all.count)
    }

    func testTipsAreShownOneAtATimeUntilDismissed() {
        let tips: [Tip] = [.capsule, .agents]
        XCTAssertEqual(TipPreference.next(in: tips, defaults: defaults), .capsule)
        TipPreference.dismiss(.capsule, defaults: defaults)
        XCTAssertEqual(TipPreference.next(in: tips, defaults: defaults), .agents)
        TipPreference.dismiss(.agents, defaults: defaults)
        XCTAssertNil(TipPreference.next(in: tips, defaults: defaults))
        XCTAssertEqual(TipPreference.next(in: [.findings], defaults: defaults), .findings)
        TipPreference.resetAll(defaults: defaults)
        XCTAssertEqual(TipPreference.next(in: tips, defaults: defaults), .capsule)
    }
}
