import Foundation

/// Value of a pipeline input. GitLab inputs are strings, numbers, booleans or arrays.
public enum CIInputValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([CIInputValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([CIInputValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported input value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int(value)) } else { try container.encode(value) }
        case .bool(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        }
    }

    /// Plain text for form fields and option labels.
    public var text: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .array(let values): return values.map(\.text).joined(separator: ", ")
        }
    }

    public var bool: Bool? { if case .bool(let value) = self { return value } else { return nil } }

    /// The items of an array value, or the value itself.
    public var items: [CIInputValue] { if case .array(let values) = self { return values } else { return [self] } }
}

/// One input declared under `spec: inputs` in the project's CI configuration.
public struct CIInputSpec: Decodable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Decodable, Sendable {
        case string = "STRING", number = "NUMBER", boolean = "BOOLEAN", array = "ARRAY", unknown

        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var id: String { name }
    public let name: String
    public var type: Kind
    public var description: String?
    public var `default`: CIInputValue?
    public var options: [CIInputValue]?
    public var required: Bool
    public var regex: String?

    enum CodingKeys: String, CodingKey { case name, type, description, `default`, options, required, regex }

    public init(name: String, type: Kind, description: String? = nil, default value: CIInputValue? = nil,
                options: [CIInputValue]? = nil, required: Bool = false, regex: String? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.default = value
        self.options = options
        self.required = required
        self.regex = regex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .string
        description = try container.decodeIfPresent(String.self, forKey: .description)
        self.default = try? container.decodeIfPresent(CIInputValue.self, forKey: .default)
        options = (try? container.decodeIfPresent(CIInputValue.self, forKey: .options))?.items
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        regex = try container.decodeIfPresent(String.self, forKey: .regex)
    }

    /// Turns what the user typed back into a value of the declared type.
    public func value(from text: String) throws -> CIInputValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .boolean:
            guard let value = Bool(trimmed.lowercased()) else { throw GitLabError.invalidInput("输入「\(name)」应为 true 或 false。") }
            return .bool(value)
        case .number:
            guard let value = Double(trimmed) else { throw GitLabError.invalidInput("输入「\(name)」应为数字。") }
            return .number(value)
        case .array:
            return .array(trimmed.split(separator: ",").map { .string($0.trimmingCharacters(in: .whitespaces)) }.filter { $0.text != "" })
        case .string, .unknown:
            return .string(text)
        }
    }
}

/// A variable the CI configuration pre-fills in the "Run pipeline" form
/// (`variables:` with `description`, `value` and optional `options`).
public struct CIConfigVariable: Decodable, Hashable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public var value: String?
    public var valueOptions: [String]
    public var description: String?

    enum CodingKeys: String, CodingKey { case key, value, valueOptions, description }

    public init(key: String, value: String?, valueOptions: [String] = [], description: String? = nil) {
        self.key = key
        self.value = value
        self.valueOptions = valueOptions
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        // Typed as String in the schema, returned as a list in practice; accept both.
        if let list = try? container.decodeIfPresent([String].self, forKey: .valueOptions) { valueOptions = list }
        else if let single = try? container.decodeIfPresent(String.self, forKey: .valueOptions) { valueOptions = [single] }
        else { valueOptions = [] }
    }
}

/// What the CI configuration on a ref declares for manual runs.
public struct RunPipelineForm: Hashable, Sendable {
    public var inputs: [CIInputSpec]
    public var variables: [CIConfigVariable]

    public init(inputs: [CIInputSpec] = [], variables: [CIConfigVariable] = []) {
        self.inputs = inputs
        self.variables = variables
    }

    public var isEmpty: Bool { inputs.isEmpty && variables.isEmpty }
}

public struct PipelineSchedule: Codable, Identifiable, Hashable, Sendable {
    public struct LastPipeline: Codable, Hashable, Sendable {
        public let id: Int
        public var sha: String?
        public var ref: String?
        public var status: CIStatus?
    }

    public struct Variable: Codable, Hashable, Sendable {
        public let key: String
        public var value: String?
        public var variableType: String?
    }

    public struct Input: Codable, Hashable, Sendable {
        public let name: String
        public var value: CIInputValue?
    }

    public let id: Int
    public var description: String?
    public let ref: String
    public var cron: String?
    public var cronTimezone: String?
    public var nextRunAt: Date?
    public var active: Bool
    public var createdAt: Date?
    public var updatedAt: Date?
    public var owner: User?
    public var lastPipeline: LastPipeline?
    /// Only returned to maintainers and the schedule owner, and only by the single-schedule endpoint.
    public var variables: [Variable]?
    public var inputs: [Input]?

    enum CodingKeys: String, CodingKey {
        case id, description, ref, cron, cronTimezone, nextRunAt, active, createdAt, updatedAt, owner, lastPipeline, variables, inputs
    }

    public init(id: Int, description: String?, ref: String, cron: String?, cronTimezone: String? = "UTC", nextRunAt: Date?,
                active: Bool, owner: User?, lastPipeline: LastPipeline? = nil, variables: [Variable]? = nil, inputs: [Input]? = nil) {
        self.id = id
        self.description = description
        self.ref = ref
        self.cron = cron
        self.cronTimezone = cronTimezone
        self.nextRunAt = nextRunAt
        self.active = active
        self.owner = owner
        self.lastPipeline = lastPipeline
        self.variables = variables
        self.inputs = inputs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        ref = try container.decodeIfPresent(String.self, forKey: .ref) ?? ""
        cron = try container.decodeIfPresent(String.self, forKey: .cron)
        cronTimezone = try container.decodeIfPresent(String.self, forKey: .cronTimezone)
        nextRunAt = try? container.decodeIfPresent(Date.self, forKey: .nextRunAt)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
        owner = try? container.decodeIfPresent(User.self, forKey: .owner)
        lastPipeline = try? container.decodeIfPresent(LastPipeline.self, forKey: .lastPipeline)
        // Shapes vary across GitLab versions and roles; a mismatch hides the field instead of failing the list.
        variables = try? container.decodeIfPresent([Variable].self, forKey: .variables)
        inputs = try? container.decodeIfPresent([Input].self, forKey: .inputs)
    }

    public var title: String {
        let text = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "计划 #\(id)" : text
    }

    public var refName: String { GitRef(ref).shortName }
}

/// Readable form of the refs GitLab reports for pipelines and schedules.
public struct GitRef: Hashable, Sendable {
    public let raw: String

    public init(_ raw: String) { self.raw = raw }

    /// `!12` for merge request refs (`refs/merge-requests/12/head`, `/merge`, `/train`).
    public var mergeRequestIID: Int? {
        let parts = raw.split(separator: "/")
        guard parts.count == 4, parts[0] == "refs", parts[1] == "merge-requests" else { return nil }
        return Int(parts[2])
    }

    public var isTag: Bool { raw.hasPrefix("refs/tags/") }

    public var shortName: String {
        if let iid = mergeRequestIID { return "!\(iid)" }
        for prefix in ["refs/heads/", "refs/tags/"] where raw.hasPrefix(prefix) { return String(raw.dropFirst(prefix.count)) }
        return raw
    }
}

extension Pipeline {
    public var gitRef: GitRef { GitRef(ref) }
}

/// Plain-language summary of the common cron shapes GitLab schedules use; anything else stays as the raw expression.
public enum CronDescription {
    private static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    public static func describe(_ cron: String) -> String {
        let fields = cron.split(separator: " ").map(String.init)
        guard fields.count == 5 else { return cron }
        let (minute, hour, day, month, weekday) = (fields[0], fields[1], fields[2], fields[3], fields[4])
        if minute == "*", hour == "*", day == "*", month == "*", weekday == "*" { return "每分钟" }
        if let step = minute.stepValue, hour == "*", day == "*", month == "*", weekday == "*" { return "每 \(step) 分钟" }
        guard let m = Int(minute), (0..<60).contains(m) else { return cron }
        if hour == "*", day == "*", month == "*", weekday == "*" { return "每小时第 \(m) 分" }
        if let step = hour.stepValue, day == "*", month == "*", weekday == "*" { return "每 \(step) 小时（第 \(m) 分）" }
        guard let h = Int(hour), (0..<24).contains(h) else { return cron }
        let time = String(format: "%02d:%02d", h, m)
        guard month == "*" else { return cron }
        switch (day, weekday) {
        case ("*", "*"): return "每天 \(time)"
        case ("*", "1-5"): return "工作日 \(time)"
        case ("*", "0,6"), ("*", "6,0"): return "周末 \(time)"
        case ("*", let w):
            let days = w.split(separator: ",").compactMap { Int($0) }
            guard !days.isEmpty, days.count == w.split(separator: ",").count, days.allSatisfy({ (0...7).contains($0) }) else { return cron }
            return "每\(days.map { weekdays[$0] }.joined(separator: "、")) \(time)"
        case (let d, "*"):
            guard let date = Int(d), (1...31).contains(date) else { return cron }
            return "每月 \(date) 日 \(time)"
        default: return cron
        }
    }
}

private extension String {
    /// `*/15` → 15.
    var stepValue: Int? {
        guard hasPrefix("*/"), let value = Int(dropFirst(2)), value > 0 else { return nil }
        return value
    }
}
