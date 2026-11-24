import Foundation

public enum WorkItemState: String, Codable, Sendable, CaseIterable {
    case opened, closed, merged, locked, all
}

public struct DiffRefs: Codable, Hashable, Sendable {
    public let baseSha: String
    public let headSha: String
    public let startSha: String
    public init(baseSha: String, headSha: String, startSha: String) {
        self.baseSha = baseSha
        self.headSha = headSha
        self.startSha = startSha
    }
}

public struct TaskCompletion: Codable, Hashable, Sendable {
    public let count: Int
    public let completedCount: Int
}

public struct MergeRequest: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let iid: Int
    public let projectId: Int
    public let title: String
    public var description: String?
    public let state: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var mergedAt: Date?
    public var closedAt: Date?
    public var author: User?
    public var assignees: [User]?
    public var reviewers: [User]?
    public var mergedBy: User?
    public let sourceBranch: String
    public let targetBranch: String
    public var sourceProjectId: Int?
    public var targetProjectId: Int?
    public var labels: [String]?
    public var draft: Bool?
    public var mergeStatus: String?
    public var detailedMergeStatus: String?
    public var hasConflicts: Bool?
    public var userNotesCount: Int?
    public var upvotes: Int?
    public var downvotes: Int?
    public var webUrl: String?
    public var references: References?
    public var sha: String?
    public var headPipeline: Pipeline?
    public var changesCount: String?
    public var milestone: Milestone?
    public var squash: Bool?
    public var forceRemoveSourceBranch: Bool?
    public var blockingDiscussionsResolved: Bool?
    public var diffRefs: DiffRefs?
    public var taskCompletionStatus: TaskCompletion?

    public init(id: Int, iid: Int, projectId: Int, title: String, description: String? = nil,
                state: String = "opened", sourceBranch: String, targetBranch: String = "main",
                author: User? = nil, createdAt: Date? = nil) {
        self.id = id
        self.iid = iid
        self.projectId = projectId
        self.title = title
        self.description = description
        self.state = state
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var isDraft: Bool { draft ?? title.lowercased().hasPrefix("draft:") }
    public var reference: String { references?.short ?? "!\(iid)" }

    /// True when GitLab reports the MR can be merged right now.
    public var isMergeable: Bool {
        if let detailedMergeStatus { return detailedMergeStatus == "mergeable" }
        return mergeStatus == "can_be_merged"
    }

    public var mergeBlocker: String? {
        switch detailedMergeStatus {
        case nil, "mergeable": return nil
        case "draft_status": return "草稿状态，需先标记为就绪"
        case "discussions_not_resolved": return "还有未解决的讨论"
        case "not_approved": return "尚未获得所需的批准"
        case "ci_must_pass", "ci_still_running": return "流水线需要先通过"
        case "conflict", "broken_status": return "存在合并冲突"
        case "need_rebase": return "需要先变基"
        case "blocked_status": return "被其他合并请求阻塞"
        case "checking", "unchecked", "preparing", "approvals_syncing": return "GitLab 正在检查可合并性"
        case "not_open": return "合并请求未处于打开状态"
        case .some(let other): return other.replacingOccurrences(of: "_", with: " ")
        }
    }
}

public struct Issue: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let iid: Int
    public let projectId: Int
    public let title: String
    public var description: String?
    public let state: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var closedAt: Date?
    public var author: User?
    public var assignees: [User]?
    public var labels: [String]?
    public var milestone: Milestone?
    public var userNotesCount: Int?
    public var upvotes: Int?
    public var downvotes: Int?
    public var dueDate: String?
    public var confidential: Bool?
    public var webUrl: String?
    public var references: References?
    public var issueType: String?
    public var taskCompletionStatus: TaskCompletion?

    public init(id: Int, iid: Int, projectId: Int, title: String, description: String? = nil,
                state: String = "opened", author: User? = nil, labels: [String] = [], createdAt: Date? = nil) {
        self.id = id
        self.iid = iid
        self.projectId = projectId
        self.title = title
        self.description = description
        self.state = state
        self.author = author
        self.labels = labels
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    public var reference: String { references?.short ?? "#\(iid)" }
}

public struct NotePosition: Codable, Hashable, Sendable {
    public var baseSha: String
    public var startSha: String
    public var headSha: String
    public var positionType: String = "text"
    public var oldPath: String?
    public var newPath: String?
    public var oldLine: Int?
    public var newLine: Int?

    public init(refs: DiffRefs, oldPath: String, newPath: String, oldLine: Int?, newLine: Int?) {
        baseSha = refs.baseSha
        startSha = refs.startSha
        headSha = refs.headSha
        self.oldPath = oldPath
        self.newPath = newPath
        self.oldLine = oldLine
        self.newLine = newLine
    }
}

public struct Note: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let body: String
    public var author: User?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var system: Bool?
    public var resolvable: Bool?
    public var resolved: Bool?
    public var type: String?
    public var position: NotePosition?

    public init(id: Int, body: String, author: User?, createdAt: Date?, system: Bool = false) {
        self.id = id
        self.body = body
        self.author = author
        self.createdAt = createdAt
        self.system = system
    }

    public var isSystem: Bool { system ?? false }
}

public struct Discussion: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var individualNote: Bool?
    public var notes: [Note]

    public init(id: String, notes: [Note], individualNote: Bool = true) {
        self.id = id
        self.notes = notes
        self.individualNote = individualNote
    }

    public var isResolvable: Bool { notes.contains { $0.resolvable == true } }
    public var isResolved: Bool { isResolvable && notes.filter { $0.resolvable == true }.allSatisfy { $0.resolved == true } }
    public var position: NotePosition? { notes.first?.position }
    public var isSystem: Bool { notes.allSatisfy(\.isSystem) }
}

public struct Approvals: Codable, Hashable, Sendable {
    public struct Approver: Codable, Hashable, Sendable { public let user: User }
    public var approved: Bool?
    public var approvalsRequired: Int?
    public var approvalsLeft: Int?
    public var approvedBy: [Approver]?
    public var userHasApproved: Bool?
    public var userCanApprove: Bool?

    public init(approvedBy: [User] = [], required: Int = 0, userHasApproved: Bool = false, userCanApprove: Bool = true) {
        self.approvedBy = approvedBy.map(Approver.init)
        self.approvalsRequired = required
        self.approvalsLeft = max(0, required - approvedBy.count)
        self.approved = approvalsLeft == 0
        self.userHasApproved = userHasApproved
        self.userCanApprove = userCanApprove
    }
}

public struct TodoTarget: Codable, Hashable, Sendable {
    public var id: Int?
    public var iid: Int?
    public var title: String?
    public var state: String?
    public var webUrl: String?
    public var projectId: Int?
}

public struct Todo: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var project: Project?
    public var author: User?
    public let actionName: String
    public let targetType: String
    public var target: TodoTarget?
    public var targetUrl: String?
    public let body: String
    public var state: String?
    public var createdAt: Date?

    public init(id: Int, project: Project?, author: User?, actionName: String, targetType: String,
                target: TodoTarget?, body: String, createdAt: Date?) {
        self.id = id
        self.project = project
        self.author = author
        self.actionName = actionName
        self.targetType = targetType
        self.target = target
        self.body = body
        self.state = "pending"
        self.createdAt = createdAt
    }

    public var actionDescription: String {
        switch actionName {
        case "assigned": return "指派给你"
        case "mentioned", "directly_addressed": return "提到了你"
        case "build_failed": return "流水线失败"
        case "marked": return "添加了待办"
        case "approval_required": return "请求你批准"
        case "unmergeable": return "无法合并"
        case "review_requested": return "请求你审查"
        case "member_access_requested": return "申请访问权限"
        case "review_submitted": return "提交了审查"
        default: return actionName.replacingOccurrences(of: "_", with: " ")
        }
    }
}

public struct PushData: Codable, Hashable, Sendable {
    public var commitCount: Int?
    public var action: String?
    public var refType: String?
    public var ref: String?
    public var commitTitle: String?
}

public struct Event: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var projectId: Int?
    public let actionName: String
    public var targetType: String?
    public var targetIid: Int?
    public var targetTitle: String?
    public var createdAt: Date?
    public var author: User?
    public var pushData: PushData?
    public var note: Note?
}
