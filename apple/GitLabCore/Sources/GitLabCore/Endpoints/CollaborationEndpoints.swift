import Foundation

/// Which items a list shows, relative to the signed-in user.
public enum WorkItemFilter: String, Sendable, CaseIterable, Identifiable {
    case all, assignedToMe = "assigned_to_me", createdByMe = "created_by_me", reviewRequested = "review_requested"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "全部"
        case .assignedToMe: return "指派给我"
        case .createdByMe: return "我创建的"
        case .reviewRequested: return "待我审查"
        }
    }
}

public enum WorkItemKind: String, Sendable { case issues, mergeRequests = "merge_requests" }

public struct MergeOptions: Codable, Sendable {
    public var squash: Bool?
    public var shouldRemoveSourceBranch: Bool?
    public var mergeCommitMessage: String?
    public var squashCommitMessage: String?
    public var mergeWhenPipelineSucceeds: Bool?
    public var sha: String?

    public init(squash: Bool? = nil, removeSourceBranch: Bool? = nil, message: String? = nil,
                whenPipelineSucceeds: Bool? = nil, sha: String? = nil) {
        self.squash = squash
        self.shouldRemoveSourceBranch = removeSourceBranch
        self.mergeCommitMessage = message
        self.mergeWhenPipelineSucceeds = whenPipelineSucceeds
        self.sha = sha
    }
}

public struct NewMergeRequest: Codable, Sendable {
    public var sourceBranch: String
    public var targetBranch: String
    public var title: String
    public var description: String?
    public var removeSourceBranch: Bool?
    public var squash: Bool?
    public var assigneeIds: [Int]?
    public var reviewerIds: [Int]?
    public var labels: String?

    public init(source: String, target: String, title: String, description: String? = nil,
                removeSourceBranch: Bool = true, squash: Bool = false) {
        self.sourceBranch = source
        self.targetBranch = target
        self.title = title
        self.description = description
        self.removeSourceBranch = removeSourceBranch
        self.squash = squash
    }
}

/// Fields for creating or editing an issue / merge request. `nil` leaves a field unchanged.
public struct WorkItemUpdate: Codable, Sendable {
    public var title: String?
    public var description: String?
    public var stateEvent: String?
    public var labels: String?
    public var assigneeIds: [Int]?
    public var milestoneId: Int?
    public var confidential: Bool?
    public var dueDate: String?

    public init(title: String? = nil, description: String? = nil, stateEvent: String? = nil,
                labels: [String]? = nil, assigneeIds: [Int]? = nil, confidential: Bool? = nil) {
        self.title = title
        self.description = description
        self.stateEvent = stateEvent
        self.labels = labels?.joined(separator: ",")
        self.assigneeIds = assigneeIds
        self.confidential = confidential
    }

    public static let close = WorkItemUpdate(stateEvent: "close")
    public static let reopen = WorkItemUpdate(stateEvent: "reopen")
}

struct NoteBody: Codable, Sendable {
    var body: String
    var position: NotePosition?
}

extension GitLabClient {
    func workItemQuery(state: WorkItemState, filter: WorkItemFilter, search: String,
                       username: String?) -> [URLQueryItem] {
        var query: [URLQueryItem] = [.init(name: "state", value: state.rawValue),
                                     .init(name: "order_by", value: "updated_at")]
        switch filter {
        case .all: query.append(.init(name: "scope", value: "all"))
        case .assignedToMe, .createdByMe: query.append(.init(name: "scope", value: filter.rawValue))
        case .reviewRequested:
            query.append(.init(name: "scope", value: "all"))
            if let username { query.append(.init(name: "reviewer_username", value: username)) }
        }
        if !search.isEmpty { query.append(.init(name: "search", value: search)) }
        return query
    }

    // MARK: Merge requests

    /// Merge requests of one project, or across the instance when `project` is nil.
    public func mergeRequests(project: Int? = nil, state: WorkItemState = .opened, filter: WorkItemFilter = .all,
                              search: String = "", username: String? = nil, page: Int = 1) async throws -> Page<MergeRequest> {
        let path = project.map { projectPath($0) + ["merge_requests"] } ?? ["merge_requests"]
        var filter = filter
        if project == nil && filter == .all { filter = .createdByMe }
        return try await list(path, page: page, query: workItemQuery(state: state, filter: filter, search: search, username: username))
    }

    public func mergeRequest(_ project: Int, iid: Int) async throws -> MergeRequest {
        try await get(projectPath(project) + ["merge_requests", String(iid)])
    }

    public func mergeRequestDiffs(_ project: Int, iid: Int, page: Int = 1) async throws -> Page<FileDiff> {
        try await list(projectPath(project) + ["merge_requests", String(iid), "diffs"], page: page, perPage: 50)
    }

    public func mergeRequestCommits(_ project: Int, iid: Int, page: Int = 1) async throws -> Page<Commit> {
        try await list(projectPath(project) + ["merge_requests", String(iid), "commits"], page: page)
    }

    public func mergeRequestPipelines(_ project: Int, iid: Int) async throws -> Page<Pipeline> {
        try await list(projectPath(project) + ["merge_requests", String(iid), "pipelines"])
    }

    public func approvals(_ project: Int, iid: Int) async throws -> Approvals {
        try await get(projectPath(project) + ["merge_requests", String(iid), "approvals"])
    }

    public func approve(_ project: Int, iid: Int, approve: Bool = true) async throws {
        try await perform("POST", projectPath(project) + ["merge_requests", String(iid), approve ? "approve" : "unapprove"])
    }

    public func merge(_ project: Int, iid: Int, options: MergeOptions) async throws -> MergeRequest {
        try await send("PUT", projectPath(project) + ["merge_requests", String(iid), "merge"], body: options)
    }

    public func rebase(_ project: Int, iid: Int) async throws {
        try await perform("PUT", projectPath(project) + ["merge_requests", String(iid), "rebase"])
    }

    public func createMergeRequest(_ project: Int, _ request: NewMergeRequest) async throws -> MergeRequest {
        guard !request.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GitLabError.invalidInput("请填写标题。")
        }
        guard request.sourceBranch != request.targetBranch else {
            throw GitLabError.invalidInput("源分支和目标分支不能相同。")
        }
        return try await send("POST", projectPath(project) + ["merge_requests"], body: request)
    }

    public func updateMergeRequest(_ project: Int, iid: Int, _ update: WorkItemUpdate) async throws -> MergeRequest {
        try await send("PUT", projectPath(project) + ["merge_requests", String(iid)], body: update)
    }

    // MARK: Issues

    public func issues(project: Int? = nil, state: WorkItemState = .opened, filter: WorkItemFilter = .all,
                       search: String = "", labels: [String] = [], page: Int = 1) async throws -> Page<Issue> {
        let path = project.map { projectPath($0) + ["issues"] } ?? ["issues"]
        var filter = filter == .reviewRequested ? .all : filter
        if project == nil && filter == .all { filter = .createdByMe }
        var query = workItemQuery(state: state, filter: filter, search: search, username: nil)
        if !labels.isEmpty { query.append(.init(name: "labels", value: labels.joined(separator: ","))) }
        return try await list(path, page: page, query: query)
    }

    public func issue(_ project: Int, iid: Int) async throws -> Issue {
        try await get(projectPath(project) + ["issues", String(iid)])
    }

    public func createIssue(_ project: Int, _ fields: WorkItemUpdate) async throws -> Issue {
        guard let title = fields.title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GitLabError.invalidInput("请填写标题。")
        }
        return try await send("POST", projectPath(project) + ["issues"], body: fields)
    }

    public func updateIssue(_ project: Int, iid: Int, _ update: WorkItemUpdate) async throws -> Issue {
        try await send("PUT", projectPath(project) + ["issues", String(iid)], body: update)
    }

    // MARK: Discussions

    public func discussions(_ project: Int, kind: WorkItemKind, iid: Int, page: Int = 1) async throws -> Page<Discussion> {
        try await list(projectPath(project) + [kind.rawValue, String(iid), "discussions"], page: page, perPage: 50)
    }

    /// Starts a discussion; pass `position` for an inline merge request diff comment.
    public func startDiscussion(_ project: Int, kind: WorkItemKind, iid: Int, body: String,
                                position: NotePosition? = nil) async throws -> Discussion {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitLabError.invalidInput("评论内容不能为空。")
        }
        return try await send("POST", projectPath(project) + [kind.rawValue, String(iid), "discussions"],
                              body: NoteBody(body: body, position: position))
    }

    public func reply(_ project: Int, kind: WorkItemKind, iid: Int, discussion: String, body: String) async throws -> Note {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitLabError.invalidInput("回复内容不能为空。")
        }
        return try await send("POST", projectPath(project) + [kind.rawValue, String(iid), "discussions", discussion, "notes"],
                              body: NoteBody(body: body))
    }

    public func resolve(_ project: Int, iid: Int, discussion: String, resolved: Bool) async throws -> Discussion {
        try await send("PUT", projectPath(project) + ["merge_requests", String(iid), "discussions", discussion],
                       query: [.init(name: "resolved", value: resolved ? "true" : "false")])
    }
}
