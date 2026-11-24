import Foundation

public enum ProjectScope: String, Sendable, CaseIterable, Identifiable {
    case membership, starred, owned, all
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .membership: return "我参与的"
        case .starred: return "已星标"
        case .owned: return "我拥有的"
        case .all: return "全部可见"
        }
    }
}

public enum ProjectOrder: String, Sendable, CaseIterable, Identifiable {
    case lastActivityAt = "last_activity_at", name, createdAt = "created_at", starCount = "star_count"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .lastActivityAt: return "最近活动"
        case .name: return "名称"
        case .createdAt: return "创建时间"
        case .starCount: return "星标数"
        }
    }
}

extension GitLabClient {
    func projectPath(_ id: Int) -> [String] { ["projects", String(id)] }

    // MARK: Account

    public func currentUser() async throws -> User { try await get(["user"]) }
    public func version() async throws -> ServerVersion { try await get(["version"]) }
    /// Scopes of the token in use (GitLab 15.5+). Older servers return 404.
    public func tokenInfo() async throws -> AccessTokenInfo { try await get(["personal_access_tokens", "self"]) }

    // MARK: Projects

    public func projects(scope: ProjectScope = .membership, search: String = "", order: ProjectOrder = .lastActivityAt,
                         page: Int = 1) async throws -> Page<Project> {
        var query: [URLQueryItem] = [.init(name: "order_by", value: order.rawValue),
                                     .init(name: "sort", value: order == .name ? "asc" : "desc"),
                                     .init(name: "archived", value: "false")]
        switch scope {
        case .membership: query.append(.init(name: "membership", value: "true"))
        case .starred: query.append(.init(name: "starred", value: "true"))
        case .owned: query.append(.init(name: "owned", value: "true"))
        case .all: break
        }
        let term = search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            query.append(.init(name: "search", value: term))
            query.append(.init(name: "search_namespaces", value: "true"))
        }
        return try await list(["projects"], page: page, query: query)
    }

    public func project(_ id: Int) async throws -> Project {
        try await get(projectPath(id), query: [.init(name: "license", value: "false")])
    }

    public func project(path: String) async throws -> Project { try await get(["projects", path]) }

    @discardableResult
    public func star(_ project: Int, starred: Bool) async throws -> Project {
        do { return try await send("POST", projectPath(project) + [starred ? "star" : "unstar"]) }
        catch GitLabError.http(304, _) { return try await self.project(project) }
    }

    public func members(_ project: Int, search: String = "", page: Int = 1) async throws -> Page<Member> {
        try await list(projectPath(project) + ["members", "all"], page: page,
                       query: search.isEmpty ? [] : [.init(name: "query", value: search)])
    }

    public func labels(_ project: Int, page: Int = 1) async throws -> Page<ProjectLabel> {
        try await list(projectPath(project) + ["labels"], page: page, perPage: 100)
    }

    public func milestones(_ project: Int) async throws -> Page<Milestone> {
        try await list(projectPath(project) + ["milestones"], query: [.init(name: "state", value: "active")])
    }

    public func events(page: Int = 1) async throws -> Page<Event> {
        try await list(["events"], page: page)
    }

    public func projectEvents(_ project: Int, page: Int = 1) async throws -> Page<Event> {
        try await list(projectPath(project) + ["events"], page: page)
    }

    // MARK: To-do

    public func todos(page: Int = 1) async throws -> Page<Todo> {
        try await list(["todos"], page: page, query: [.init(name: "state", value: "pending")])
    }

    public func markTodoDone(_ id: Int) async throws {
        try await perform("POST", ["todos", String(id), "mark_as_done"])
    }

    public func markAllTodosDone() async throws {
        try await perform("POST", ["todos", "mark_as_done"])
    }

    // MARK: Search

    public func searchProjects(_ term: String, page: Int = 1) async throws -> Page<Project> {
        try await list(["search"], page: page, query: [.init(name: "scope", value: "projects"),
                                                         .init(name: "search", value: term)])
    }

    public func searchIssues(_ term: String, page: Int = 1) async throws -> Page<Issue> {
        try await list(["search"], page: page, query: [.init(name: "scope", value: "issues"),
                                                         .init(name: "search", value: term)])
    }

    public func searchMergeRequests(_ term: String, page: Int = 1) async throws -> Page<MergeRequest> {
        try await list(["search"], page: page, query: [.init(name: "scope", value: "merge_requests"),
                                                         .init(name: "search", value: term)])
    }
}
