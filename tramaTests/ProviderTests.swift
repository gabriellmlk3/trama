import Foundation
import XCTest
@testable import trama

final class ProviderTests: XCTestCase {
    var lab: Lab!

    override func setUpWithError() throws {
        lab = try Lab()
    }

    override func tearDown() {
        lab.cleanup()
    }

    func fakeTool(_ name: String, _ script: String) throws -> String {
        let path = lab.root + "/" + name
        try lab.write(path, "#!/bin/sh\n" + script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func host(_ w: Workspace, _ repo: String, as url: String) throws {
        let dir = lab.repos[repo]!
        try w.setProvider(repo, nil)
        try lab.git(dir, "remote", "set-url", "origin", url)
        try lab.git(dir, "config", "url.\(lab.root)/remotos/\(repo).git.insteadOf", url)
    }

    func commitAll(_ w: Workspace, _ t: Trama, _ repos: [String]) throws {
        for name in repos {
            try lab.commit(w.worktreePath(t.slug, name), "feature.txt", "x\n", "feature")
        }
    }

    func testRemoteParsingDetectsTheProvider() throws {
        func detect(_ raw: String) -> ProviderKind? { RemoteRepo.parse(raw)?.detectedKind }
        XCTAssertEqual(detect("git@github.com:acme/api.git"), .github)
        XCTAssertEqual(detect("https://github.com/acme/api"), .github)
        XCTAssertEqual(detect("ssh://git@github.example.com:22/acme/api.git"), .github)
        XCTAssertEqual(detect("https://user:token@gitlab.com/group/sub/proj.git"), .gitlab)
        XCTAssertEqual(detect("git@gitlab.mycompany.com:group/proj.git"), .gitlab)
        XCTAssertEqual(detect("https://bitbucket.org/acme/api.git"), .bitbucket)
        XCTAssertEqual(detect("https://git.mycompany.com/team/api.git"), .manual)
        XCTAssertEqual(detect("https://acme@dev.azure.com/acme/Proj/_git/api"), .azure)
        XCTAssertEqual(detect("git@ssh.dev.azure.com:v3/acme/Proj/api"), .azure)
        XCTAssertEqual(detect("https://acme.visualstudio.com/Proj/_git/api"), .azure)
        XCTAssertEqual(detect("https://tfs.mycompany.com/tfs/Col/Proj/_git/api"), .azure)
        XCTAssertNil(RemoteRepo.parse("/tmp/remotos/api.git"))
        XCTAssertNil(RemoteRepo.parse("../remotos/api.git"))
        XCTAssertNil(RemoteRepo.parse("file:///tmp/remotos/api.git"))
        XCTAssertNil(RemoteRepo.parse(""))

        XCTAssertEqual(RemoteRepo.parse("https://acme@dev.azure.com/acme/My%20Project/_git/api")?.azure,
                       AzureCoordinates(organizationURL: "https://dev.azure.com/acme", project: "My Project", repository: "api"))
        XCTAssertEqual(RemoteRepo.parse("git@ssh.dev.azure.com:v3/acme/Proj/api")?.azure,
                       AzureCoordinates(organizationURL: "https://dev.azure.com/acme", project: "Proj", repository: "api"))
        XCTAssertEqual(RemoteRepo.parse("https://acme.visualstudio.com/DefaultCollection/Proj/_git/api")?.azure,
                       AzureCoordinates(organizationURL: "https://acme.visualstudio.com", project: "Proj", repository: "api"))
        XCTAssertEqual(RemoteRepo.parse("https://dev.azure.com/acme/_git/api")?.azure?.project, "api")
        XCTAssertEqual(RemoteRepo.parse("https://tfs.mycompany.com/tfs/Col/Proj/_git/api")?.azure,
                       AzureCoordinates(organizationURL: "https://tfs.mycompany.com/tfs/Col", project: "Proj", repository: "api"))
        XCTAssertNil(RemoteRepo.parse("https://github.com/acme/api")?.azure)
        XCTAssertEqual(RemoteRepo.parse("https://dev.azure.com/acme/My%20Project/_git/api")?.azure?.webURL,
                       "https://dev.azure.com/acme/My%20Project/_git/api")

        func link(_ raw: String, _ kind: ProviderKind) -> String? {
            RemoteRepo.parse(raw)?.newPullRequestURL(kind: kind, branch: "trama/x", target: "main")
        }
        XCTAssertEqual(link("git@github.com:acme/api.git", .github), "https://github.com/acme/api/compare/main...trama/x?expand=1")
        XCTAssertEqual(link("https://dev.azure.com/acme/Proj/_git/api", .azure),
                       "https://dev.azure.com/acme/Proj/_git/api/pullrequestcreate?sourceRef=trama%2Fx&targetRef=main")
        XCTAssertEqual(link("git@gitlab.com:g/p.git", .gitlab),
                       "https://gitlab.com/g/p/-/merge_requests/new?merge_request%5Bsource_branch%5D=trama%2Fx&merge_request%5Btarget_branch%5D=main")
        XCTAssertEqual(link("https://bitbucket.org/acme/api.git", .bitbucket),
                       "https://bitbucket.org/acme/api/pull-requests/new?source=trama%2Fx&dest=main")
        XCTAssertEqual(link("https://git.mycompany.com/team/api.git", .manual), "https://git.mycompany.com/team/api")

        XCTAssertEqual(ProviderKind.named("Azure-DevOps"), .azure)
        XCTAssertEqual(ProviderKind.named("gh"), .github)
        XCTAssertNil(ProviderKind.named("auto"))
        XCTAssertEqual(AzureProvider.pullRequestId("https://dev.azure.com/acme/Proj/_git/api/pullrequest/42"), 42)
        XCTAssertEqual(GitLabProvider.mergeRequestId("https://gitlab.com/g/p/-/merge_requests/5"), 5)
        XCTAssertEqual(AzureProvider.ciState([]), CIState.none)
        XCTAssertEqual(GitLabProvider.ci(["head_pipeline": ["status": "running"]]), CIState.pending)
        XCTAssertEqual(GitLabProvider.ci([:]), CIState.none)
    }

    func testProviderIsDetectedAndStoredPerRepo() throws {
        let w = try lab.workspace()
        XCTAssertEqual(try w.repo("api").provider, .github)
        try w.setProvider("api", nil)
        XCTAssertEqual(w.providerKind(for: try w.repo("api")), .manual, "um remoto local não diz nada")
        try lab.git(lab.repos["rebocs_api"]!, "remote", "set-url", "origin", "git@gitlab.com:acme/api.git")
        XCTAssertEqual(w.providerKind(for: try w.repo("api")), .gitlab)
        try w.setProvider("api", .azure)
        XCTAssertEqual(w.providerKind(for: try w.repo("api")), .azure, "o ajuste manual vence a detecção")
        XCTAssertEqual(try Workspace.open(root: w.root).repo("api").provider, .azure)
        try w.setProvider("api", nil)
        XCTAssertNil(try Workspace.open(root: w.root).repo("api").provider)
    }

    func testAzurePullRequestsAreOpenedRetargetedAndTracked() throws {
        let w = try lab.workspace()
        let log = lab.root + "/az.log"
        let states = lab.root + "/az-estados"
        try FileManager.default.createDirectory(atPath: states, withIntermediateDirectories: true)
        let fake = try fakeTool("az", """
        echo "$PWD|$*" >> "\(log)"
        repo="$(basename "$PWD")"
        prev=""
        for arg in "$@"; do
          if [ "$prev" = "--in-file" ]; then cat "$arg" >> "\(log)"; echo >> "\(log)"; fi
          prev="$arg"
        done
        case "$1 $2 $3" in
          "repos pr list") cat "\(states)/lista-$repo.json" 2>/dev/null || echo '[]' ;;
          "repos pr show") cat "\(states)/pr-$repo.json" 2>/dev/null || exit 1 ;;
          "repos pr create") echo '{"pullRequestId":42,"status":"active","isDraft":false,"targetRefName":"refs/heads/main","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/'"$repo"'"}}' ;;
          "repos pr update") echo '{}' ;;
          "repos pr policy") cat "\(states)/politicas-$repo.json" 2>/dev/null || echo '[]' ;;
          "devops invoke "*) echo '{}' ;;
        esac
        """)
        setenv("TRAMA_AZ", fake, 1)
        defer { unsetenv("TRAMA_AZ") }
        let names = ["rebocs-admin", "rebocs-android", "rebocs_api"]
        for name in names {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
            try host(w, name, as: "https://acme@dev.azure.com/acme/Proj/_git/\(name)")
        }
        func pullRequest(_ repo: String, status: String, target: String) throws {
            try lab.write("\(states)/pr-\(repo).json", #"{"pullRequestId":42,"status":"\#(status)","isDraft":false,"targetRefName":"refs/heads/\#(target)","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/\#(repo)"}}"#)
        }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Azure", repos: ["api", "admin", "android"], goal: "Entregar no Azure", noFetch: true))
        try commitAll(w, t, names)

        let plan = try w.pullRequestPlan(t.slug)
        XCTAssertEqual(plan.map(\.provider), [.azure, .azure, .azure])
        XCTAssertEqual(plan.map(\.action), [.create, .create, .create])

        let first = try w.openPullRequests(t.slug, draft: true)
        XCTAssertEqual(first.prs.map(\.repo), names)
        XCTAssertTrue(first.manual.isEmpty)
        XCTAssertEqual(try w.trama(t.slug).prs["rebocs_api"], "https://dev.azure.com/acme/Proj/_git/rebocs_api/pullrequest/42")
        var calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("repos pr create --source-branch \(t.branch) --target-branch main --title Azure --description=## Azure"))
        XCTAssertTrue(calls.contains("--draft true"))
        XCTAssertTrue(calls.contains("--organization https://dev.azure.com/acme --detect false --output json --project Proj --repository rebocs_api"))
        XCTAssertTrue(calls.contains("Entregar no Azure"))
        XCTAssertTrue(calls.contains("repos pr update --id 42 --description=## Azure"))
        XCTAssertTrue(calls.contains("### PRs desta trama"))
        XCTAssertTrue(Git.branchExists(lab.root + "/remotos/rebocs_api.git", t.branch))

        for name in names { try pullRequest(name, status: "active", target: "main") }
        let existing = try w.existingPullRequests(t.slug)
        XCTAssertEqual(existing["rebocs-admin"]?.number, 42)
        XCTAssertEqual(existing["rebocs-admin"]?.base, "main")
        XCTAssertEqual(existing["rebocs-admin"]?.state, "open")
        XCTAssertEqual(try w.pullRequestPlan(t.slug, targets: ["rebocs-admin": "develop"], existing: existing).map(\.action), [.retarget, .update, .update])

        _ = try w.openPullRequests(t.slug, targets: ["rebocs-admin": "develop"], only: ["rebocs-admin"])
        calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("devops invoke --area git --resource pullRequests --route-parameters project=Proj repositoryId=rebocs-admin pullRequestId=42 --http-method PATCH --in-file"))
        XCTAssertTrue(calls.contains(#"{"targetRefName":"refs/heads/develop"}"#))
        XCTAssertEqual(try w.trama(t.slug).prBases, ["rebocs-admin": "develop"])

        try lab.write("\(states)/politicas-rebocs_api.json", #"[{"status":"approved","configuration":{"type":{"displayName":"Build"}}},{"status":"queued","configuration":{"type":{"displayName":"Minimum number of reviewers"}}}]"#)
        var infos = w.pullRequestInfos(try w.trama(t.slug))
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.number, 42)
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.state, "open")
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.ci, CIState.success, "a política de revisores não conta como CI")
        try lab.write("\(states)/politicas-rebocs_api.json", #"[{"status":"rejected","configuration":{"type":{"displayName":"Build"}}}]"#)
        infos = w.pullRequestInfos(try w.trama(t.slug))
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.ci, CIState.failure)

        try pullRequest("rebocs_api", status: "completed", target: "main")
        let merged = try w.pullRequestPlan(t.slug, existing: try w.existingPullRequests(t.slug))
        XCTAssertEqual(merged.first { $0.repo == "rebocs_api" }?.blocker, .merged)
        XCTAssertThrowsError(try w.openPullRequests(t.slug, only: ["rebocs_api"])) {
            XCTAssertTrue(errorMessage($0).contains("já foi mesclado"))
        }

        try lab.write("\(states)/lista-rebocs-android.json", #"[{"pullRequestId":7,"status":"abandoned","sourceRefName":"refs/heads/\#(t.branch)","targetRefName":"refs/heads/main","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/rebocs-android"}},{"pullRequestId":9,"status":"active","sourceRefName":"refs/heads/\#(t.branch)","targetRefName":"refs/heads/develop","repository":{"webUrl":"https://dev.azure.com/acme/Proj/_git/rebocs-android"}}]"#)
        let provider = try XCTUnwrap(w.host(for: try w.repo("android"), dir: w.worktreePath(t.slug, "rebocs-android")).provider)
        let byBranch = try XCTUnwrap(provider.existing(w.worktreePath(t.slug, "rebocs-android"), t.branch))
        XCTAssertEqual(byBranch.number, 9, "o PR ativo vence o abandonado")
        XCTAssertEqual(byBranch.base, "develop")
    }

    func testGitLabMergeRequestsAreOpenedAndRetargeted() throws {
        let w = try lab.workspace()
        let log = lab.root + "/glab.log"
        let states = lab.root + "/glab-estados"
        try FileManager.default.createDirectory(atPath: states, withIntermediateDirectories: true)
        let fake = try fakeTool("glab", """
        echo "$PWD|$*" >> "\(log)"
        repo="$(basename "$PWD")"
        case "$1 $2" in
          "mr view") cat "\(states)/$repo.json" 2>/dev/null || exit 1 ;;
          "mr create")
            echo "Creating merge request for x into main in acme/$repo"
            echo
            echo "!5 Titulo (https://gitlab.com/acme/$repo/-/merge_requests/5)" ;;
          "mr update") ;;
        esac
        """)
        setenv("TRAMA_GLAB", fake, 1)
        defer { unsetenv("TRAMA_GLAB") }
        let names = ["rebocs-admin", "rebocs_api"]
        for name in names {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
            try host(w, name, as: "git@gitlab.com:acme/\(name).git")
        }
        func mergeRequest(_ repo: String, state: String, target: String, pipeline: String) throws {
            try lab.write("\(states)/\(repo).json", #"{"iid":5,"web_url":"https://gitlab.com/acme/\#(repo)/-/merge_requests/5","state":"\#(state)","target_branch":"\#(target)","draft":false,"head_pipeline":{"status":"\#(pipeline)"}}"#)
        }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "GitLab", repos: ["api", "admin"], noFetch: true))
        try commitAll(w, t, names)
        XCTAssertEqual(try w.pullRequestPlan(t.slug).map(\.provider), [.gitlab, .gitlab])

        let first = try w.openPullRequests(t.slug, draft: true)
        XCTAssertEqual(first.prs.map(\.repo), names)
        XCTAssertEqual(try w.trama(t.slug).prs["rebocs_api"], "https://gitlab.com/acme/rebocs_api/-/merge_requests/5")
        var calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("mr create --source-branch \(t.branch) --target-branch main --title GitLab --description=## GitLab"))
        XCTAssertTrue(calls.contains("--yes --no-editor --draft"))
        XCTAssertTrue(calls.contains("mr update 5 --description=## GitLab"))

        try mergeRequest("rebocs-admin", state: "opened", target: "main", pipeline: "failed")
        try mergeRequest("rebocs_api", state: "opened", target: "main", pipeline: "success")
        let existing = try w.existingPullRequests(t.slug)
        XCTAssertEqual(existing["rebocs-admin"]?.number, 5)
        XCTAssertEqual(try w.pullRequestPlan(t.slug, existing: existing).map(\.action), [.update, .update])
        XCTAssertEqual(try w.pullRequestPlan(t.slug, targets: ["rebocs-admin": "develop"], existing: existing).map(\.action), [.retarget, .update])

        _ = try w.openPullRequests(t.slug, targets: ["rebocs-admin": "develop"], only: ["rebocs-admin"])
        calls = try File.read(log) ?? ""
        XCTAssertTrue(calls.contains("mr update 5 --target-branch develop"))

        let infos = w.pullRequestInfos(try w.trama(t.slug))
        XCTAssertEqual(infos.first { $0.repo == "rebocs-admin" }?.ci, CIState.failure)
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.ci, CIState.success)
        XCTAssertEqual(infos.first { $0.repo == "rebocs_api" }?.state, "open")

        try mergeRequest("rebocs_api", state: "merged", target: "main", pipeline: "success")
        let merged = try w.pullRequestPlan(t.slug, existing: try w.existingPullRequests(t.slug))
        XCTAssertEqual(merged.first { $0.repo == "rebocs_api" }?.blocker, .merged)
    }

    func testHostsWithoutAutomationGetALinkAndTheBranchPushed() throws {
        let w = try lab.workspace()
        for name in ["rebocs-admin", "rebocs-android", "rebocs_api"] {
            try lab.git(lab.repos[name]!, "push", "-q", "origin", "main:develop")
        }
        try host(w, "rebocs_api", as: "https://bitbucket.org/acme/rebocs_api.git")
        try host(w, "rebocs-admin", as: "https://dev.azure.com/acme/Proj/_git/rebocs-admin")
        try host(w, "rebocs-android", as: "https://git.mycompany.com/team/rebocs-android.git")
        setenv("TRAMA_AZ", lab.root + "/nao-existe/az", 1)
        defer { unsetenv("TRAMA_AZ") }
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Manual", repos: ["api", "admin", "android"], noFetch: true))
        try commitAll(w, t, ["rebocs-admin", "rebocs-android", "rebocs_api"])

        let plan = try w.pullRequestPlan(t.slug)
        XCTAssertEqual(plan.map(\.provider), [.azure, .manual, .bitbucket])
        XCTAssertEqual(plan.map(\.action), [.manual, .manual, .manual])
        XCTAssertEqual(plan.map(\.automatic), [false, false, false])
        XCTAssertEqual(plan[0].missingTool, "az")
        XCTAssertTrue(plan[0].summary.contains("sem o az"))
        XCTAssertNil(plan[2].missingTool)

        let result = try w.openPullRequests(t.slug, targets: ["rebocs_api": "develop"])
        XCTAssertTrue(result.prs.isEmpty)
        XCTAssertEqual(result.manual.map(\.repo), ["rebocs-admin", "rebocs-android", "rebocs_api"])
        let branch = queryEncoded(t.branch)
        XCTAssertEqual(result.manual[0].url, "https://dev.azure.com/acme/Proj/_git/rebocs-admin/pullrequestcreate?sourceRef=\(branch)&targetRef=main")
        XCTAssertEqual(result.manual[1].url, "https://git.mycompany.com/team/rebocs-android")
        XCTAssertEqual(result.manual[2].url, "https://bitbucket.org/acme/rebocs_api/pull-requests/new?source=\(branch)&dest=develop")
        XCTAssertTrue(result.warnings.contains { $0.repo == "rebocs-admin" && $0.message.contains("não encontrei o `az`") })
        for name in ["rebocs-admin", "rebocs-android", "rebocs_api"] {
            XCTAssertTrue(Git.branchExists(lab.root + "/remotos/\(name).git", t.branch), name)
        }
        let saved = try w.trama(t.slug)
        XCTAssertEqual(saved.prs, [:])
        XCTAssertEqual(saved.prBases, ["rebocs_api": "develop"])
        XCTAssertTrue(try w.readCapsule(t.slug).journal.contains { $0.text.contains("pelo navegador") })
    }

    func testPullRequestBodyKeepsTheLinksWhenTooLong() throws {
        let w = try lab.workspace()
        let (t, _) = try w.newTrama(NewTramaOptions(title: "Longa", repos: ["api"], goal: "Objetivo", noFetch: true))
        for i in 1...40 {
            try w.addDecision(t.slug, author: "você", String(repeating: "decisão \(i) ", count: 10))
        }
        let capsule = try w.readCapsule(t.slug)
        let links = [(repo: "a", url: "https://x/1"), (repo: "b", url: "https://x/2")]
        let full = w.pullRequestBody(t, capsule: capsule, links: links, current: "b")
        XCTAssertTrue(full.count > 1000)
        let short = w.pullRequestBody(t, capsule: capsule, links: links, current: "b", limit: 1000)
        XCTAssertTrue(short.count <= 1000)
        XCTAssertTrue(short.contains("2. https://x/2 ← este PR"))
        XCTAssertTrue(short.contains("…"))
        XCTAssertTrue(short.hasPrefix("## Longa"))
    }
}
