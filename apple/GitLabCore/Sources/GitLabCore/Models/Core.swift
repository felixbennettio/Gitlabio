import Foundation

public struct User: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let username: String
    public let name: String
    public var avatarUrl: String?
    public var webUrl: String?
    public var state: String?
    public var bio: String?
    public var publicEmail: String?
    public var isAdmin: Bool?

    public init(id: Int, username: String, name: String, avatarUrl: String? = nil, webUrl: String? = nil) {
        self.id = id
        self.username = username
        self.name = name
        self.avatarUrl = avatarUrl
        self.webUrl = webUrl
    }
}

public struct Namespace: Codable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let path: String
    public var kind: String?
    public var fullPath: String?
    public var avatarUrl: String?

    public init(id: Int, name: String, path: String, kind: String? = nil, fullPath: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.fullPath = fullPath
    }
}

public struct ProjectPermissions: Codable, Hashable, Sendable {
    public struct Access: Codable, Hashable, Sendable {
        public let accessLevel: Int
        public init(accessLevel: Int) { self.accessLevel = accessLevel }
    }
    public var projectAccess: Access?
    public var groupAccess: Access?

    public init(projectAccess: Access? = nil, groupAccess: Access? = nil) {
        self.projectAccess = projectAccess
        self.groupAccess = groupAccess
    }

    /// Highest of project and inherited group access level (10 guest … 50 owner).
    public var level: Int { max(projectAccess?.accessLevel ?? 0, groupAccess?.accessLevel ?? 0) }
    public var canPush: Bool { level >= 30 }
    public var canMaintain: Bool { level >= 40 }

    public var roleName: String {
        switch level {
        case 50...: return "Owner"
        case 40..<50: return "Maintainer"
        case 30..<40: return "Developer"
        case 20..<30: return "Reporter"
        case 10..<20: return "Guest"
        default: return "访客"
        }
    }
}

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public var nameWithNamespace: String?
    public var path: String?
    public let pathWithNamespace: String
    public var description: String?
    public var defaultBranch: String?
    public var webUrl: String?
    public var avatarUrl: String?
    public var starCount: Int?
    public var forksCount: Int?
    public var openIssuesCount: Int?
    public var lastActivityAt: Date?
    public var createdAt: Date?
    public var visibility: String?
    public var namespace: Namespace?
    public var archived: Bool?
    public var emptyRepo: Bool?
    public var readmeUrl: String?
    public var httpUrlToRepo: String?
    public var sshUrlToRepo: String?
    public var topics: [String]?
    public var permissions: ProjectPermissions?
    public var issuesEnabled: Bool?
    public var mergeRequestsEnabled: Bool?
    public var jobsEnabled: Bool?

    public init(id: Int, name: String, pathWithNamespace: String, description: String? = nil,
                defaultBranch: String? = "main") {
        self.id = id
        self.name = name
        self.pathWithNamespace = pathWithNamespace
        self.description = description
        self.defaultBranch = defaultBranch
    }

    public var namespacePath: String {
        guard let slash = pathWithNamespace.lastIndex(of: "/") else { return "" }
        return String(pathWithNamespace[..<slash])
    }

    /// Path of the README inside the repository, derived from `readme_url`.
    public var readmePath: String? {
        guard let readmeUrl, let range = readmeUrl.range(of: "/-/blob/") else { return nil }
        let rest = readmeUrl[range.upperBound...]
        guard let branch = defaultBranch, rest.hasPrefix(branch + "/") else {
            return rest.split(separator: "/").last.map(String.init)
        }
        return String(rest.dropFirst(branch.count + 1)).removingPercentEncoding
    }
}

public struct ProjectLabel: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let color: String
    public var textColor: String?
    public var description: String?

    public init(id: Int, name: String, color: String, textColor: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.textColor = textColor
    }
}

public struct Milestone: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var iid: Int?
    public let title: String
    public var state: String?
    public var dueDate: String?

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

public struct References: Codable, Hashable, Sendable {
    public var short: String?
    public var relative: String?
    public var full: String?
    public init(short: String? = nil, full: String? = nil) {
        self.short = short
        self.full = full
    }
}

public struct ServerVersion: Codable, Sendable {
    public let version: String
    public var revision: String?
}

public struct AccessTokenInfo: Codable, Sendable {
    public let id: Int
    public let name: String
    public let scopes: [String]
    public var expiresAt: String?
    public var active: Bool?
    public var revoked: Bool?

    public var canWrite: Bool { scopes.contains("api") }
}

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let username: String
    public let name: String
    public var avatarUrl: String?
    public var accessLevel: Int?

    public var user: User { User(id: id, username: username, name: name, avatarUrl: avatarUrl) }
}
