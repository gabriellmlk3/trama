import Foundation
import XCTest
@testable import trama

final class GitAuthenticationTests: XCTestCase {
    func testAuthenticationFailuresPointToGitAccounts() {
        let messages = [
            "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
            "remote: Invalid username or token. Password authentication is not supported",
            "remote: HTTP Basic: Access denied",
            "git@gitlab.com: Permission denied (publickey)."
        ]
        for stderr in messages {
            let error = GitError(args: ["push"], code: 128, stderr: stderr)
            XCTAssertTrue(error.isAuthenticationFailure, stderr)
            XCTAssertTrue(error.description.contains("Contas Git"), stderr)
        }
    }

    func testOtherFailuresKeepTheGitMessage() {
        let error = GitError(args: ["push"], code: 1, stderr: "! [rejected] main -> main (non-fast-forward)")
        XCTAssertFalse(error.isAuthenticationFailure)
        XCTAssertTrue(error.description.hasPrefix("git push:"))
    }

    func testCredentialEnvironmentsCoverEveryProvider() {
        for kind in ProviderKind.withCredentials {
            XCTAssertFalse(kind.defaultHost.isEmpty)
            XCTAssertNotNil(kind.tokenPage(host: kind.defaultHost, organization: "acme"))
        }
    }

    func testInstallerCoversEveryProviderCLI() {
        for kind in ProviderKind.withCredentials {
            guard let cli = kind.cliName else { continue }
            let tool = ToolInstaller.named(cli)
            XCTAssertNotNil(tool, cli)
            XCTAssertTrue(tool?.installCommand.contains("brew install") == true, cli)
            XCTAssertTrue(kind.loginCommand(host: kind.defaultHost)?.contains(tool?.ensureCommand ?? "?") == true, cli)
        }
        XCTAssertEqual(ToolInstaller.named("GitHub")?.id, "gh")
        XCTAssertNil(ToolInstaller.named("foo"))
    }

    func testClaudeSessionHistoryIsDetectedPerWorktree() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let worktree = lab.root + "/trama/app"
        try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        XCTAssertFalse(ClaudeSessions.hasHistory(at: worktree, home: lab.root))
        let dir = ClaudeSessions.projectDirectory(for: worktree, home: lab.root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        XCTAssertFalse(ClaudeSessions.hasHistory(at: worktree, home: lab.root))
        try lab.write(dir + "/abc.jsonl", "{}\n")
        XCTAssertTrue(ClaudeSessions.hasHistory(at: worktree, home: lab.root))
        XCTAssertFalse(ClaudeSessions.hasHistory(at: lab.root + "/trama/outro", home: lab.root))
    }

    func testClaudeConversationsAreListedNewestFirstWithTitles() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let worktree = lab.root + "/trama/app"
        try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        let dir = ClaudeSessions.projectDirectory(for: worktree, home: lab.root)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try lab.write(dir + "/velha.jsonl", "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"primeira pergunta\\nsegunda linha\"}}\n")
        try lab.write(dir + "/nova.jsonl", "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>x</command-name>\"}}\n{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"ignorada\"}}\n{\"type\":\"custom-title\",\"customTitle\":\"Título dado\"}\n")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: dir + "/velha.jsonl")
        let list = ClaudeSessions.conversations(at: worktree, home: lab.root)
        XCTAssertEqual(list.map(\.id), ["nova", "velha"])
        XCTAssertEqual(list.map(\.title), ["Título dado", "primeira pergunta"])
    }
}
