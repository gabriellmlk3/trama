import Foundation
import XCTest
@testable import trama

final class PreparationTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func testRecipeSuggestionOnRegistration() throws {
        let dir = try lab.newRepo("suggest-web")
        try lab.write(dir + "/.env", "A=1\n")
        try lab.write(dir + "/.env.example", "A=\n")
        try lab.write(dir + "/package-lock.json", "{}\n")
        let w = try lab.workspace()
        let r = try w.addRepo(dir)
        XCTAssertEqual(r.recipe, Recipe(copy: [".env*"], run: ["npm ci"]))
        XCTAssertEqual(try Workspace.open(root: w.root).repo("suggest-web").recipe, r.recipe)
    }

    func testRecipeCopiesFilesAndRunsCommands() throws {
        let w = try lab.workspace()
        let api = lab.repos["rebocs_api"]!
        try lab.write(api + "/.env", "SECRET=1\n")
        try lab.write(api + "/config/.env.local", "LOCAL=1\n")
        try w.setRecipe("api", copy: [".env*", "config/.env*"], run: ["echo ok > prepared.txt"])
        XCTAssertThrowsError(try w.setRecipe("api", copy: ["../fora"], run: []))
        let (t, warnings) = try w.newTrama(NewTramaOptions(title: "Preparada", repos: ["api", "admin"], noFetch: true))
        XCTAssertTrue(warnings.isEmpty)
        let wt = w.worktreePath(t.slug, "rebocs_api")
        XCTAssertEqual(try File.read(wt + "/.env"), "SECRET=1\n")
        XCTAssertEqual(try File.read(wt + "/config/.env.local"), "LOCAL=1\n")
        let deadline = Date().addingTimeInterval(20)
        while w.prepState(t.slug, "rebocs_api") == PrepState.running, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(w.prepState(t.slug, "rebocs_api"), PrepState.ready)
        XCTAssertEqual(try File.read(wt + "/prepared.txt"), "ok\n")
        XCTAssertNil(w.prepState(t.slug, "rebocs-admin"))
        let status = w.repoStatus(t, try w.repo("api"), predictConflict: false)
        XCTAssertEqual(status.prep, PrepState.ready)
        XCTAssertTrue(try File.read(w.prepLogPath(t.slug, "rebocs_api"))?.contains("copiado: .env") == true)
    }

    func testRecipeFailureIsReported() throws {
        let w = try lab.workspace()
        try w.setRecipe("api", copy: [], run: ["echo antes", "exit 3", "echo depois"])
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Falha", repos: ["api"], noFetch: true))
        let deadline = Date().addingTimeInterval(20)
        while w.prepState(t.slug, "rebocs_api") == PrepState.running, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(w.prepState(t.slug, "rebocs_api"), PrepState.failed)
        let log = try File.read(w.prepLogPath(t.slug, "rebocs_api")) ?? ""
        XCTAssertTrue(log.contains("antes"))
        XCTAssertFalse(log.contains("depois"))
        _ = try w.archive(t.slug)
        XCTAssertNil(w.prepState(t.slug, "rebocs_api"))
    }

    func testPortsPerTramaAndServiceLifecycle() throws {
        let w = try lab.workspace()
        try w.setServices("api", [ServiceConfig(name: "dev", command: "echo $PORT $TRAMA_PORTA_BASE > ports.txt; exec sleep 60", port: 3100)])
        XCTAssertThrowsError(try w.setServices("api", [ServiceConfig(name: "x y", command: "a", port: 3000)]))
        let (a, _) = try w.newTrama(NewTramaOptions(title: "Porta A", repos: ["api"], noFetch: true))
        let (b, _) = try w.newTrama(NewTramaOptions(title: "Porta B", repos: ["api"], noFetch: true))
        XCTAssertEqual([a.portIndex, b.portIndex], [0, 1])
        let r = try w.repo("api")
        let service = r.services[0]
        XCTAssertEqual(w.servicePort(a, service), 3100)
        XCTAssertEqual(w.servicePort(b, service), 3110)
        defer {
            w.stopServices(a.slug)
            w.stopServices(b.slug)
        }
        XCTAssertEqual(try w.startServices(a.slug).map(\.port), [3100])
        XCTAssertEqual(try w.startServices(b.slug).map(\.port), [3110])
        XCTAssertTrue(try w.startServices(a.slug).isEmpty, "já no ar")
        XCTAssertTrue(w.serviceStatuses(a, r)[0].running)
        let wt = w.worktreePath(b.slug, "rebocs_api")
        let deadline = Date().addingTimeInterval(20)
        while !Paths.exists(wt + "/ports.txt"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(try File.read(wt + "/ports.txt"), "3110 3010\n")
        XCTAssertEqual(w.stopServices(a.slug), 1)
        XCTAssertFalse(w.serviceStatuses(a, r)[0].running)
        XCTAssertTrue(w.serviceStatuses(b, r)[0].running)
        _ = try w.park(b.slug)
        XCTAssertFalse(w.serviceStatuses(b, r)[0].running)
        XCTAssertThrowsError(try w.startServices(b.slug), "estacionada")
        _ = try w.archive(a.slug, force: true)
        let (c, _) = try w.newTrama(NewTramaOptions(title: "Porta C", repos: ["api"], noFetch: true))
        XCTAssertEqual(c.portIndex, 0, "o índice de uma trama arquivada é reaproveitado")
    }

    func testPortInUseIsRefused() throws {
        let w = try lab.workspace()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = in_addr_t(0)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 1)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        let busy = Int(UInt16(bigEndian: addr.sin_port))
        XCTAssertTrue(Workspace.portInUse(busy))
        try w.setServices("api", [ServiceConfig(name: "dev", command: "sleep 60", port: busy)])
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Ocupada", repos: ["api"], noFetch: true))
        XCTAssertThrowsError(try w.startServices(t.slug)) { XCTAssertTrue(errorMessage($0).contains("em uso")) }
    }
}
