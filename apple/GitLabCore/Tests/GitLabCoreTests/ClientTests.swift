import Foundation
import Testing
@testable import GitLabCore

/// Records requests and replies with a canned response.
final class RecordingTransport: GitLabTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var reply: (URLRequest) -> (Int, [String: String], Data)

    init(_ reply: @escaping (URLRequest) -> (Int, [String: String], Data)) { self.reply = reply }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, headers, body) = reply(request)
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

private func client(_ transport: RecordingTransport, instance: String = "https://git.example.test/gitlab/") throws -> GitLabClient {
    GitLabClient(instance: try GitLabInstance(instance), credential: .accessToken("test-only"), transport: transport)
}

@Suite struct InstanceTests {
    @Test(arguments: ["http://host", "https://user:secret@host", "https://host?token=a", "https://host/#x",
                      "https://host/a/../b", "file:///tmp/x", "ftp://host"])
    func rejectsUnsafeInstances(_ url: String) {
        #expect(throws: GitLabError.invalidInstance) { try GitLabInstance(url) }
    }

    @Test func normalisesInput() throws {
        #expect(try GitLabInstance("git.Example.com/").url.absoluteString == "https://git.example.com")
        #expect(try GitLabInstance("https://git.example.com/gitlab/api/v4/").url.absoluteString == "https://git.example.com/gitlab")
        #expect(try GitLabInstance(" https://gitlab.com ").isGitLabCom)
        #expect(try GitLabInstance("https://git.example.com/gitlab").displayName == "git.example.com/gitlab")
    }

    @Test func encodesSegmentsAndQueryIndependently() throws {
        let instance = try GitLabInstance("https://git.example.test/gitlab")
        let url = instance.endpoint(["projects", "team/app", "repository", "files", "文 件/a#b%.swift"],
                                    query: [.init(name: "ref", value: "feat/a&b+c")])
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        #expect(parts.percentEncodedPath.hasPrefix("/gitlab/api/v4/projects/team%2Fapp/repository/files/"))
        #expect(parts.percentEncodedPath.hasSuffix("%2Fa%23b%25.swift"))
        #expect(parts.percentEncodedQuery == "ref=feat%2Fa%26b%2Bc")
        #expect(url.user == nil)
    }

    @Test func resolvesRelativeAvatar() throws {
        let instance = try GitLabInstance("https://git.example.test/gitlab")
        #expect(instance.resolve("/uploads/a.png")?.absoluteString == "https://git.example.test/gitlab/uploads/a.png")
        #expect(instance.resolve("https://cdn.test/a.png")?.absoluteString == "https://cdn.test/a.png")
        #expect(instance.resolve(nil) == nil)
    }
}

@Suite struct RequestTests {
    @Test func tokenHeaderAndNoTokenInURL() async throws {
        let transport = RecordingTransport { _ in (200, [:], Data(#"{"id":1,"username":"u","name":"U"}"#.utf8)) }
        let user = try await client(transport).currentUser()
        #expect(user.username == "u")
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "test-only")
        #expect(!(request.url!.absoluteString.contains("test-only")))
    }

    @Test func oauthUsesBearer() throws {
        let client = GitLabClient(instance: try GitLabInstance("https://h"), credential: .oauth("abc"),
                                  transport: RecordingTransport { _ in (200, [:], Data()) })
        #expect(try client.request(["user"]).value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func rejectsTokenWithControlCharacters() throws {
        let client = GitLabClient(instance: try GitLabInstance("https://h"), credential: .accessToken("bad\nvalue"),
                                  transport: RecordingTransport { _ in (200, [:], Data()) })
        #expect(throws: GitLabError.self) { try client.request(["user"]) }
    }

    @Test func pagination() async throws {
        let fixture = try Data(contentsOf: contractsDirectory().appendingPathComponent("fixtures/projects.json"))
        let transport = RecordingTransport { _ in (200, ["X-Next-Page": "3", "X-Total": "61"], fixture) }
        let page = try await client(transport).projects(page: 2)
        #expect(page.next == 3)
        #expect(page.total == 61)
        #expect(page.items.first?.pathWithNamespace == "group/app")
        let query = transport.requests[0].url!.query!
        #expect(query.contains("page=2"))
        #expect(query.contains("membership=true"))
    }

    @Test func ignoresNonAdvancingNextPage() async throws {
        let transport = RecordingTransport { _ in (200, ["X-Next-Page": "1"], Data("[]".utf8)) }
        let page: Page<Project> = try await client(transport).list(["projects"], page: 1)
        #expect(page.next == nil)
    }

    @Test func multiFileCommitBody() async throws {
        let transport = RecordingTransport { _ in
            (201, [:], Data(#"{"id":"abc","short_id":"abc","title":"t","author_name":"a"}"#.utf8))
        }
        let request = CommitRequest(branch: "feat/x", message: "Update docs", startBranch: "main", actions: [
            CommitAction(action: .update, filePath: "README.md", text: "héllo", lastCommitId: "123"),
            CommitAction(action: .move, filePath: "b.txt", previousPath: "a.txt"),
            CommitAction(action: .delete, filePath: "old.txt")
        ])
        _ = try await client(transport).createCommit(7, request)
        let sent = try #require(transport.requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url!.path.hasSuffix("/projects/7/repository/commits"))
        let json = try #require(try JSONSerialization.jsonObject(with: sent.httpBody!) as? [String: Any])
        #expect(json["branch"] as? String == "feat/x")
        #expect(json["start_branch"] as? String == "main")
        #expect(json["commit_message"] as? String == "Update docs")
        let actions = try #require(json["actions"] as? [[String: Any]])
        #expect(actions[0]["action"] as? String == "update")
        #expect(actions[0]["encoding"] as? String == "base64")
        #expect(actions[0]["last_commit_id"] as? String == "123")
        #expect(Data(base64Encoded: actions[0]["content"] as! String) == Data("héllo".utf8))
        #expect(actions[1]["previous_path"] as? String == "a.txt")
    }

    @Test func emptyCommitIsRejectedLocally() async throws {
        let transport = RecordingTransport { _ in (201, [:], Data()) }
        await #expect(throws: GitLabError.self) {
            _ = try await client(transport).createCommit(1, CommitRequest(branch: "main", message: "x", actions: []))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func pipelineTriggerWithVariables() async throws {
        let transport = RecordingTransport { _ in (201, [:], Data(#"{"id":5,"status":"created","ref":"main"}"#.utf8)) }
        let pipeline = try await client(transport).runPipeline(3, ref: "main", variables: [
            PipelineVariable(key: "DEPLOY", value: "1"), PipelineVariable(key: " ", value: "ignored")
        ])
        #expect(pipeline.status == .created)
        let json = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
        #expect((json["variables"] as! [[String: Any]]).count == 1)
    }

    @Test func unknownCIStatusDecodes() throws {
        let job: Job = try JSON.decode(Data(#"{"id":1,"name":"a","status":"brand_new","stage":"s"}"#.utf8))
        #expect(job.status == .unknown)
    }

    @Test(arguments: ["2026-10-28T03:29:08.123Z", "2026-10-28T03:29:08Z", "2026-10-28T11:29:08.123+08:00"])
    func decodesGitLabDates(_ text: String) throws {
        let date = try #require(JSON.parseDate(text))
        #expect(abs(date.timeIntervalSince1970 - 1_793_158_148) < 1)
    }
}

@Suite struct ErrorTests {
    @Test func mapsStatuses() {
        #expect(GitLabError.from(status: 401, body: Data(), headers: [:]) == .unauthorized)
        #expect(GitLabError.from(status: 404, body: Data(), headers: [:]) == .notFound)
        #expect(GitLabError.from(status: 429, body: Data(), headers: ["Retry-After": "30"]) == .rateLimited(retryAfter: 30))
        #expect(GitLabError.from(status: 502, body: Data(), headers: [:]) == .server(502))
    }

    @Test func extractsAndSanitisesServerMessages() {
        let nested = Data(#"{"message":{"branch":["already exists"],"base":["is invalid"]}}"#.utf8)
        #expect(GitLabError.from(status: 400, body: nested, headers: [:]) == .validation("base is invalid；branch already exists"))
        let control = Data("{\"message\":\"bad\\u0007 thing\"}".utf8)
        #expect(GitLabError.serverMessage(control) == "bad thing")
        let long = Data(("{\"message\":\"" + String(repeating: "x", count: 500) + "\"}").utf8)
        #expect(GitLabError.serverMessage(long)!.count == 241)
    }

    @Test func httpErrorsSurfaceThroughClient() async throws {
        let transport = RecordingTransport { _ in (409, [:], Data(#"{"message":"A file with this name already exists"}"#.utf8)) }
        await #expect(throws: GitLabError.conflict("A file with this name already exists")) {
            _ = try await client(transport).createBranch(1, name: "x", from: "main")
        }
    }

    @Test func invalidBranchNameRejectedLocally() async throws {
        let transport = RecordingTransport { _ in (201, [:], Data()) }
        await #expect(throws: GitLabError.self) { _ = try await client(transport).createBranch(1, name: "has space", from: "main") }
        #expect(transport.requests.isEmpty)
    }
}

@Suite struct ModelTests {
    @Test func editableText() throws {
        let file = RepositoryFile(filePath: "a/b.txt", text: "hello\n", lastCommitId: "1")
        #expect(try file.text() == "hello\n")
        #expect(file.fileName == "b.txt")
        let binary: RepositoryFile = try JSON.decode(Data(#"{"file_name":"x","file_path":"x","size":3,"encoding":"base64","content":"AAEC","last_commit_id":"1"}"#.utf8))
        #expect(throws: GitLabError.binaryFile) { try binary.text() }
    }

    @Test func readmePathFromURL() {
        var project = Project(id: 1, name: "a", pathWithNamespace: "g/a", defaultBranch: "main")
        project.readmeUrl = "https://h/g/a/-/blob/main/docs/README.md"
        #expect(project.readmePath == "docs/README.md")
    }

    @Test func stagesKeepPipelineOrder() {
        let jobs = [Job(id: 3, name: "deploy", status: .manual, stage: "deploy"),
                    Job(id: 1, name: "b", status: .success, stage: "build"),
                    Job(id: 2, name: "test", status: .failed, stage: "test"),
                    Job(id: 4, name: "a", status: .success, stage: "build")]
        let stages = PipelineStage.group(jobs)
        #expect(stages.map(\.name) == ["build", "test", "deploy"])
        #expect(stages[0].jobs.map(\.name) == ["a", "b"])
        #expect(stages[1].status == .failed)
        #expect(stages[2].status == .manual)
    }

    @Test func allowedFailureDoesNotFailStage() {
        let stage = PipelineStage(name: "lint", jobs: [Job(id: 1, name: "a", status: .failed, stage: "lint", allowFailure: true),
                                                       Job(id: 2, name: "b", status: .success, stage: "lint")])
        #expect(stage.status == .success)
    }

    @Test func mergeBlockers() {
        var mr = MergeRequest(id: 1, iid: 1, projectId: 1, title: "x", sourceBranch: "a")
        mr.detailedMergeStatus = "mergeable"
        #expect(mr.isMergeable && mr.mergeBlocker == nil)
        mr.detailedMergeStatus = "discussions_not_resolved"
        #expect(!mr.isMergeable && mr.mergeBlocker == "还有未解决的讨论")
    }

    @Test func permissions() {
        let permissions = ProjectPermissions(projectAccess: .init(accessLevel: 20), groupAccess: .init(accessLevel: 40))
        #expect(permissions.canPush && permissions.roleName == "Maintainer")
    }
}

func contractsDirectory() -> URL {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root.appendingPathComponent("contracts")
}
