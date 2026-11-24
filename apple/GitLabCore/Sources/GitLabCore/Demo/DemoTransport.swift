import Foundation

/// An in-memory GitLab used by the demo mode, UI screenshots and tests. All data is fictional.
public final class DemoTransport: GitLabTransport {
    public static let instance = try! GitLabInstance("https://gitlab.demo.invalid")
    public static let token = "demo-token"
    let data = DemoData()
    let latency: Duration

    public init(latency: Duration = .milliseconds(120)) {
        self.latency = latency
    }

    public static func client(latency: Duration = .milliseconds(120)) -> GitLabClient {
        GitLabClient(instance: instance, credential: .accessToken(token), transport: DemoTransport(latency: latency))
    }

    struct Reply {
        let url: URL
        let query: [String: String]
        var page: Int { Int(query["page"] ?? "1") ?? 1 }

        func json(_ value: some Encodable, status: Int = 200, headers: [String: String] = [:]) throws -> (Data, HTTPURLResponse) {
            (try JSON.encoder.encode(value), HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }

        func page<T: Encodable>(_ items: [T]) throws -> (Data, HTTPURLResponse) {
            let size = Int(query["per_page"] ?? "30") ?? 30
            let start = min((page - 1) * size, items.count)
            let slice = Array(items[start..<min(start + size, items.count)])
            var headers = ["X-Total": String(items.count)]
            if start + size < items.count { headers["X-Next-Page"] = String(page + 1) }
            return try json(slice, headers: headers)
        }

        func text(_ value: String) -> (Data, HTTPURLResponse) {
            (Data(value.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"])!)
        }

        func error(_ status: Int, _ message: String) -> (Data, HTTPURLResponse) {
            (Data("{\"message\":\"\(message)\"}".utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!)
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GitLabError.malformedResponse
        }
        if components.path.hasSuffix("/api/graphql") {
            if latency > .zero { try await Task.sleep(for: latency) }
            return try graphQL(request.httpBody, url: url)
        }
        guard let range = components.percentEncodedPath.range(of: "/api/v4/") else { throw GitLabError.malformedResponse }
        let segments = components.percentEncodedPath[range.upperBound...].split(separator: "/")
            .map { String($0).removingPercentEncoding ?? String($0) }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let reply = Reply(url: url, query: query)
        if latency > .zero { try await Task.sleep(for: latency) }
        return try route(request.httpMethod ?? "GET", segments, reply, body: request.httpBody)
    }

    /// The demo answers only the run-pipeline form query; GraphQL keys are camelCase, so no key strategy.
    func graphQL(_ body: Data?, url: URL) throws -> (Data, HTTPURLResponse) {
        struct Query: Decodable { let query: String }
        let query = (try? JSONDecoder().decode(Query.self, from: body ?? Data()))?.query ?? ""
        guard query.contains("ciPipelineCreationInputs") else {
            return (Data(#"{"data":null,"errors":[{"message":"Unsupported demo query"}]}"#.utf8),
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!)
        }
        let form = data.runForm
        func spec(_ input: CIInputSpec) -> [String: Any] {
            var value: [String: Any] = ["name": input.name, "type": input.type.rawValue, "required": input.required]
            value["description"] = input.description
            if let fallback = input.default { value["default"] = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(fallback), options: .fragmentsAllowed) }
            if let options = input.options { value["options"] = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) }
            return value
        }
        let variables: [[String: Any]] = form.variables.map {
            ["key": $0.key, "value": $0.value ?? NSNull(), "valueOptions": $0.valueOptions, "description": $0.description ?? NSNull()]
        }
        let object: [String: Any] = ["data": ["project": ["ciPipelineCreationInputs": form.inputs.map(spec), "ciConfigVariables": variables]]]
        return (try JSONSerialization.data(withJSONObject: object),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!)
    }

    func route(_ method: String, _ path: [String], _ reply: Reply, body: Data?) throws -> (Data, HTTPURLResponse) {
        let q = reply.query
        switch (method, path.first ?? "") {
        case ("GET", "user"): return try reply.json(data.me)
        case ("GET", "version"): return try reply.json(ServerVersion(version: "18.5.1", revision: "demo"))
        case ("GET", "personal_access_tokens"):
            return try reply.json(AccessTokenInfo(id: 1, name: "Gitlabio", scopes: ["api", "read_user"], expiresAt: "2027-06-30",
                                                  active: true, revoked: false))
        case ("GET", "todos"): return try reply.page(data.todos)
        case ("POST", "todos"): return try reply.json(GitLabClient.Empty())
        case ("GET", "events"): return try reply.page(data.events)
        case ("GET", "merge_requests"): return try reply.page(filter(data.mergeRequests, q))
        case ("GET", "issues"): return try reply.page(filter(data.issues, q))
        case ("GET", "search"):
            let term = (q["search"] ?? "").lowercased()
            switch q["scope"] {
            case "issues": return try reply.page(data.issues.filter { $0.title.lowercased().contains(term) })
            case "merge_requests": return try reply.page(data.mergeRequests.filter { $0.title.lowercased().contains(term) })
            default: return try reply.page(data.projects.filter { $0.pathWithNamespace.lowercased().contains(term) })
            }
        case ("GET", "projects") where path.count == 1:
            var items = data.projects
            if q["starred"] == "true" { items = items.filter { ($0.starCount ?? 0) >= 40 } }
            if let term = q["search"]?.lowercased(), !term.isEmpty {
                items = items.filter { $0.pathWithNamespace.lowercased().contains(term) || $0.name.lowercased().contains(term) }
            }
            if q["order_by"] == "name" { items.sort { $0.name.lowercased() < $1.name.lowercased() } }
            if q["order_by"] == "star_count" { items.sort { ($0.starCount ?? 0) > ($1.starCount ?? 0) } }
            return try reply.page(items)
        case (_, "projects") where path.count >= 2:
            guard let project = data.projects.first(where: { String($0.id) == path[1] || $0.pathWithNamespace == path[1] }) else {
                throw GitLabError.notFound
            }
            return try projectRoute(method, project, Array(path.dropFirst(2)), reply, body: body)
        default:
            return reply.error(404, "404 Not Found")
        }
    }

    func filter<T>(_ items: [T], _ q: [String: String]) -> [T] where T: DemoWorkItem {
        items.filter { item in
            if let state = q["state"], state != "all", item.state != state { return false }
            switch q["scope"] {
            case "assigned_to_me": if !(item.assignees ?? []).contains(data.me) { return false }
            case "created_by_me": if item.author != data.me { return false }
            default: break
            }
            if q["reviewer_username"] != nil, !item.reviewerList.contains(data.me) { return false }
            if let term = q["search"]?.lowercased(), !term.isEmpty, !item.title.lowercased().contains(term) { return false }
            return true
        }
    }

    func projectRoute(_ method: String, _ project: Project, _ path: [String], _ reply: Reply, body: Data?) throws -> (Data, HTTPURLResponse) {
        let q = reply.query
        let id = project.id
        switch (method, path) {
        case ("GET", []): return try reply.json(project)
        case ("POST", ["star"]), ("POST", ["unstar"]): return try reply.json(project)
        case ("GET", ["members", "all"]): return try reply.page(data.members)
        case ("GET", ["labels"]): return try reply.page(data.labels)
        case ("GET", ["milestones"]): return try reply.page(data.milestones)
        case ("GET", ["events"]): return try reply.page(data.events.filter { $0.projectId == id })

        // Repository
        case ("GET", ["repository", "tree"]):
            return try reply.page(data.tree(id, path: q["path"] ?? ""))
        case ("GET", let p) where p.count == 4 && p[0] == "repository" && p[1] == "files" && p[3] == "raw":
            guard let text = data.file(id, p[2]) else { return reply.error(404, "404 File Not Found") }
            return reply.text(text)
        case ("GET", let p) where p.count == 3 && p[0] == "repository" && p[1] == "files":
            guard let text = data.file(id, p[2]) else { return reply.error(404, "404 File Not Found") }
            return try reply.json(RepositoryFile(filePath: p[2], text: text, lastCommitId: data.commits[0].id))
        case ("GET", ["repository", "branches"]):
            let term = (q["search"] ?? "").lowercased()
            return try reply.page(data.branches.filter { term.isEmpty || $0.name.lowercased().contains(term) })
        case ("GET", let p) where p.count == 3 && p[0] == "repository" && p[1] == "branches":
            guard let branch = data.branches.first(where: { $0.name == p[2] }) else { return reply.error(404, "404 Branch Not Found") }
            return try reply.json(branch)
        case ("POST", ["repository", "branches"]):
            return try reply.json(Branch(name: q["branch"] ?? "new-branch", commit: data.commits[0]), status: 201)
        case ("DELETE", let p) where p.count == 3 && p[0] == "repository" && p[1] == "branches":
            return (Data(), HTTPURLResponse(url: reply.url, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        case ("GET", ["repository", "tags"]): return try reply.page(data.tags)
        case ("GET", ["repository", "commits"]): return try reply.page(data.commits)
        case ("POST", ["repository", "commits"]):
            let request = try body.map { try JSON.decoder.decode(CommitRequest.self, from: $0) }
            var commit = Commit(id: "f00dfeed" + String(repeating: "0", count: 32), title: request?.commitMessage.components(separatedBy: "\n").first ?? "Commit",
                                message: request?.commitMessage, authorName: data.me.name, date: Date())
            commit.webUrl = (project.webUrl ?? "") + "/-/commit/" + commit.id
            return try reply.json(commit, status: 201)
        case ("GET", let p) where p.count == 3 && p[0] == "repository" && p[1] == "commits":
            guard var commit = data.commits.first(where: { $0.id.hasPrefix(p[2]) || $0.shortId == p[2] }) else { return reply.error(404, "404 Commit Not Found") }
            commit.lastPipeline = data.pipelines.first
            return try reply.json(commit)
        case ("GET", let p) where p.count == 4 && p[0] == "repository" && p[1] == "commits" && p[3] == "diff":
            return try reply.page(data.diffs)
        case ("GET", ["repository", "compare"]):
            return try reply.json(Comparison(commit: data.commits.first, commits: Array(data.commits.prefix(3)), diffs: data.diffs,
                                             compareTimeout: false, compareSameRef: false))

        // Merge requests
        case ("GET", ["merge_requests"]): return try reply.page(filter(data.mergeRequests.filter { $0.projectId == id }, q))
        case ("POST", ["merge_requests"]):
            let request = try body.map { try JSON.decoder.decode(NewMergeRequest.self, from: $0) }
            var mr = MergeRequest(id: 9001, iid: 99, projectId: id, title: request?.title ?? "New", description: request?.description,
                                  sourceBranch: request?.sourceBranch ?? "feature", targetBranch: request?.targetBranch ?? "main",
                                  author: data.me, createdAt: Date())
            mr.webUrl = (project.webUrl ?? "") + "/-/merge_requests/99"
            return try reply.json(mr, status: 201)
        case (_, let p) where p.count >= 2 && p[0] == "merge_requests":
            guard let mr = data.mergeRequests.first(where: { String($0.iid) == p[1] && $0.projectId == id }) else {
                return reply.error(404, "404 Not found")
            }
            return try mergeRequestRoute(method, mr, Array(p.dropFirst(2)), reply)

        // Issues
        case ("GET", ["issues"]): return try reply.page(filter(data.issues.filter { $0.projectId == id }, q))
        case ("POST", ["issues"]):
            let fields = try body.map { try JSON.decoder.decode(WorkItemUpdate.self, from: $0) }
            let issue = Issue(id: 8001, iid: 77, projectId: id, title: fields?.title ?? "New issue", description: fields?.description,
                              author: data.me, labels: fields?.labels?.components(separatedBy: ",") ?? [], createdAt: Date())
            return try reply.json(issue, status: 201)
        case (_, let p) where p.count >= 2 && p[0] == "issues":
            guard var issue = data.issues.first(where: { String($0.iid) == p[1] && $0.projectId == id }) else {
                return reply.error(404, "404 Not found")
            }
            if p.count == 2 && method == "PUT" {
                let update = try body.map { try JSON.decoder.decode(WorkItemUpdate.self, from: $0) }
                issue = Issue(id: issue.id, iid: issue.iid, projectId: issue.projectId, title: update?.title ?? issue.title,
                              description: update?.description ?? issue.description,
                              state: update?.stateEvent == "close" ? "closed" : update?.stateEvent == "reopen" ? "opened" : issue.state,
                              author: issue.author, labels: update?.labels?.components(separatedBy: ",") ?? issue.labels ?? [],
                              createdAt: issue.createdAt)
                return try reply.json(issue)
            }
            if p.count == 2 { return try reply.json(issue) }
            return try discussionRoute(method, Array(p.dropFirst(2)), reply, discussions: data.issueDiscussions)

        // CI/CD
        case ("GET", ["pipelines"]):
            let ref = q["ref"]
            return try reply.page(data.pipelines.filter { ref == nil || $0.ref == ref })
        case ("GET", ["pipeline_schedules"]):
            return try reply.page(data.schedules.map { schedule -> PipelineSchedule in
                var listed = schedule
                listed.variables = nil
                return listed
            })
        case ("GET", let p) where p.count == 2 && p[0] == "pipeline_schedules":
            guard let schedule = data.schedules.first(where: { String($0.id) == p[1] }) else { return reply.error(404, "404 Not found") }
            return try reply.json(schedule)
        case ("POST", let p) where p.count == 3 && p[0] == "pipeline_schedules" && p[2] == "play":
            return try reply.json(["message": "201 Created"], status: 201)
        case ("POST", ["pipeline"]):
            return try reply.json(Pipeline(id: 4242, iid: 420, projectId: id, status: .created, ref: "main", sha: data.commits[0].id,
                                           source: "web", user: data.me, createdAt: Date()), status: 201)
        case ("GET", let p) where p.count == 2 && p[0] == "pipelines":
            guard let pipeline = data.pipelines.first(where: { String($0.id) == p[1] }) else { return reply.error(404, "404 Not found") }
            return try reply.json(pipeline)
        case ("GET", let p) where p.count == 3 && p[0] == "pipelines" && p[2] == "jobs":
            return try reply.page(data.jobs(pipeline: Int(p[1]) ?? 0))
        case ("POST", let p) where p.count == 3 && p[0] == "pipelines":
            guard let pipeline = data.pipelines.first(where: { String($0.id) == p[1] }) else { return reply.error(404, "404 Not found") }
            return try reply.json(Pipeline(id: pipeline.id, iid: pipeline.iid, projectId: id, status: p[2] == "cancel" ? .canceled : .pending,
                                           ref: pipeline.ref, sha: pipeline.sha, source: pipeline.source, user: data.me, createdAt: pipeline.createdAt))
        case ("GET", let p) where p.count == 2 && p[0] == "jobs":
            guard let job = data.allJobs.first(where: { String($0.id) == p[1] }) else { return reply.error(404, "404 Not found") }
            return try reply.json(job)
        case ("GET", let p) where p.count == 3 && p[0] == "jobs" && p[2] == "trace":
            return reply.text(data.trace(job: Int(p[1]) ?? 0))
        case ("POST", let p) where p.count == 3 && p[0] == "jobs":
            guard let job = data.allJobs.first(where: { String($0.id) == p[1] }) else { return reply.error(404, "404 Not found") }
            return try reply.json(Job(id: job.id + (p[2] == "retry" ? 1000 : 0), name: job.name,
                                      status: p[2] == "cancel" ? .canceled : .pending, stage: job.stage))
        default:
            return reply.error(404, "404 Not Found")
        }
    }

    func mergeRequestRoute(_ method: String, _ mr: MergeRequest, _ path: [String], _ reply: Reply) throws -> (Data, HTTPURLResponse) {
        switch (method, path) {
        case ("GET", []):
            var detail = mr
            detail.headPipeline = data.pipelines.first { $0.ref == mr.sourceBranch } ?? data.pipelines.first
            return try reply.json(detail)
        case ("PUT", []): return try reply.json(mr)
        case ("GET", ["diffs"]): return try reply.page(data.diffs)
        case ("GET", ["commits"]): return try reply.page(Array(data.commits.prefix(4)))
        case ("GET", ["pipelines"]): return try reply.page(data.pipelines.filter { $0.ref == mr.sourceBranch })
        case ("GET", ["approvals"]): return try reply.json(data.approvals(for: mr))
        case ("POST", ["approve"]), ("POST", ["unapprove"]): return try reply.json(data.approvals(for: mr))
        case ("PUT", ["merge"]):
            let merged = MergeRequest(id: mr.id, iid: mr.iid, projectId: mr.projectId, title: mr.title, description: mr.description,
                                      state: "merged", sourceBranch: mr.sourceBranch, targetBranch: mr.targetBranch,
                                      author: mr.author, createdAt: mr.createdAt)
            return try reply.json(merged)
        case ("PUT", ["rebase"]): return try reply.json(["rebase_in_progress": true], status: 202)
        default: return try discussionRoute(method, path, reply, discussions: data.mergeRequestDiscussions)
        }
    }

    func discussionRoute(_ method: String, _ path: [String], _ reply: Reply, discussions: [Discussion]) throws -> (Data, HTTPURLResponse) {
        switch (method, path) {
        case ("GET", ["discussions"]): return try reply.page(discussions)
        case ("POST", ["discussions"]):
            return try reply.json(Discussion(id: UUID().uuidString, notes: [Note(id: 99_000, body: "已发送", author: data.me, createdAt: Date())]), status: 201)
        case ("POST", let p) where p.count == 3 && p[0] == "discussions" && p[2] == "notes":
            return try reply.json(Note(id: 99_001, body: "已回复", author: data.me, createdAt: Date()), status: 201)
        case ("PUT", let p) where p.count == 2 && p[0] == "discussions":
            return try reply.json(discussions.first { $0.id == p[1] } ?? discussions[0])
        default:
            return reply.error(404, "404 Not Found")
        }
    }
}

protocol DemoWorkItem {
    var state: String { get }
    var title: String { get }
    var author: User? { get }
    var assignees: [User]? { get }
    var reviewerList: [User] { get }
}

extension MergeRequest: DemoWorkItem { var reviewerList: [User] { reviewers ?? [] } }
extension Issue: DemoWorkItem { var reviewerList: [User] { [] } }
