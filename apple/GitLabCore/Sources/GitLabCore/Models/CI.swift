import Foundation

/// GitLab CI status values shared by pipelines and jobs.
public enum CIStatus: String, Codable, Sendable, CaseIterable {
    case created, waitingForResource = "waiting_for_resource", preparing, pending, running
    case success, failed, canceled, canceling, skipped, manual, scheduled
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CIStatus(rawValue: raw) ?? .unknown
    }

    public var isActive: Bool { [.created, .waitingForResource, .preparing, .pending, .running, .canceling].contains(self) }
    public var isFinished: Bool { [.success, .failed, .canceled, .skipped].contains(self) }
    public var canRetry: Bool { [.failed, .canceled, .success].contains(self) }
    public var canCancel: Bool { isActive }

    public var title: String {
        switch self {
        case .created: return "已创建"
        case .waitingForResource: return "等待资源"
        case .preparing: return "准备中"
        case .pending: return "排队中"
        case .running: return "运行中"
        case .success: return "已通过"
        case .failed: return "失败"
        case .canceled: return "已取消"
        case .canceling: return "取消中"
        case .skipped: return "已跳过"
        case .manual: return "手动"
        case .scheduled: return "已计划"
        case .unknown: return "未知"
        }
    }
}

public struct Pipeline: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var iid: Int?
    public var projectId: Int?
    public let status: CIStatus
    public var source: String?
    public let ref: String
    public var sha: String?
    public var webUrl: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var duration: Int?
    public var queuedDuration: Double?
    public var user: User?
    public var coverage: String?
    public var name: String?

    public init(id: Int, iid: Int? = nil, projectId: Int? = nil, status: CIStatus, ref: String, sha: String? = nil,
                source: String? = "push", user: User? = nil, createdAt: Date? = nil, duration: Int? = nil) {
        self.id = id
        self.iid = iid
        self.projectId = projectId
        self.status = status
        self.ref = ref
        self.sha = sha
        self.source = source
        self.user = user
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.duration = duration
    }

    public var sourceTitle: String {
        switch source {
        case "push": return "推送"
        case "merge_request_event": return "合并请求"
        case "schedule": return "定时"
        case "web": return "手动运行"
        case "api": return "API"
        case "trigger": return "触发器"
        case "pipeline", "parent_pipeline": return "上游流水线"
        case .some(let other): return other
        case nil: return ""
        }
    }
}

public struct Runner: Codable, Hashable, Sendable {
    public let id: Int
    public var description: String?
}

public struct Job: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let status: CIStatus
    public let stage: String
    public var ref: String?
    public var createdAt: Date?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var duration: Double?
    public var queuedDuration: Double?
    public var user: User?
    public var webUrl: String?
    public var allowFailure: Bool?
    public var failureReason: String?
    public var runner: Runner?
    public var tagList: [String]?
    public var pipeline: PipelineRef?
    public var commit: Commit?
    public var coverage: Double?

    public struct PipelineRef: Codable, Hashable, Sendable {
        public let id: Int
        public var ref: String?
        public var status: CIStatus?
    }

    public init(id: Int, name: String, status: CIStatus, stage: String, duration: Double? = nil,
                allowFailure: Bool = false, startedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.stage = stage
        self.duration = duration
        self.allowFailure = allowFailure
        self.startedAt = startedAt
        self.createdAt = startedAt
    }

    public var isManual: Bool { status == .manual }
}

/// Jobs grouped by stage, in pipeline order (GitLab returns jobs newest first).
public struct PipelineStage: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let jobs: [Job]

    public var status: CIStatus {
        let statuses = jobs.map(\.status)
        if statuses.contains(.running) { return .running }
        if jobs.contains(where: { $0.status == .failed && $0.allowFailure != true }) { return .failed }
        if statuses.contains(where: \.isActive) { return .pending }
        if statuses.contains(.manual) && !statuses.contains(.success) { return .manual }
        if statuses.allSatisfy({ $0 == .skipped }) { return .skipped }
        if statuses.allSatisfy({ $0 == .canceled }) { return .canceled }
        return statuses.contains(.success) ? .success : (statuses.first ?? .unknown)
    }

    public static func group(_ jobs: [Job]) -> [PipelineStage] {
        var order: [String] = []
        var map: [String: [Job]] = [:]
        for job in jobs.sorted(by: { $0.id < $1.id }) {
            if map[job.stage] == nil { order.append(job.stage) }
            map[job.stage, default: []].append(job)
        }
        return order.map { PipelineStage(name: $0, jobs: map[$0]!.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
    }
}

public struct PipelineVariable: Codable, Hashable, Sendable, Identifiable {
    public var id: String { key }
    public var key: String
    public var value: String
    public var variableType: String

    public init(key: String, value: String, variableType: String = "env_var") {
        self.key = key
        self.value = value
        self.variableType = variableType
    }
}
