import Foundation

public struct CommitStats: Codable, Hashable, Sendable {
    public let additions: Int
    public let deletions: Int
    public var total: Int?
    public init(additions: Int, deletions: Int) {
        self.additions = additions
        self.deletions = deletions
        self.total = additions + deletions
    }
}

public struct Commit: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let shortId: String
    public let title: String
    public var message: String?
    public let authorName: String
    public var authorEmail: String?
    public var authoredDate: Date?
    public var committerName: String?
    public var committedDate: Date?
    public var createdAt: Date?
    public var parentIds: [String]?
    public var webUrl: String?
    public var stats: CommitStats?
    public var status: String?
    public var lastPipeline: Pipeline?

    public init(id: String, title: String, message: String? = nil, authorName: String,
                authorEmail: String? = nil, date: Date? = nil) {
        self.id = id
        self.shortId = String(id.prefix(8))
        self.title = title
        self.message = message ?? title
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authoredDate = date
        self.committedDate = date
        self.createdAt = date
        self.parentIds = []
    }

    public var date: Date? { committedDate ?? authoredDate ?? createdAt }

    /// Message without the title line.
    public var body: String? {
        guard let message else { return nil }
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

public struct Branch: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public var `protected`: Bool?
    public var `default`: Bool?
    public var merged: Bool?
    public var developersCanPush: Bool?
    public var canPush: Bool?
    public var commit: Commit?
    public var webUrl: String?

    public init(name: String, isProtected: Bool = false, isDefault: Bool = false, commit: Commit? = nil) {
        self.name = name
        self.protected = isProtected
        self.default = isDefault
        self.commit = commit
    }

    public var isProtected: Bool { `protected` ?? false }
    public var isDefault: Bool { `default` ?? false }
}

public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public var message: String?
    public var target: String?
    public var commit: Commit?
    public var `protected`: Bool?
    public var createdAt: Date?

    public init(name: String, message: String? = nil, commit: Commit? = nil) {
        self.name = name
        self.message = message
        self.commit = commit
    }
}

public struct TreeEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let path: String
    public var mode: String?

    public init(id: String, name: String, type: String, path: String) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
    }

    public var isDirectory: Bool { type == "tree" }
    public var isSubmodule: Bool { type == "commit" }
}

public struct RepositoryFile: Codable, Hashable, Sendable {
    public let fileName: String
    public let filePath: String
    public let size: Int
    public let encoding: String
    public let content: String
    public var ref: String?
    public var blobId: String?
    public var commitId: String?
    public let lastCommitId: String

    public init(filePath: String, text: String, lastCommitId: String) {
        self.fileName = (filePath as NSString).lastPathComponent
        self.filePath = filePath
        let data = Data(text.utf8)
        self.size = data.count
        self.encoding = "base64"
        self.content = data.base64EncodedString()
        self.lastCommitId = lastCommitId
    }

    public var data: Data? {
        guard encoding == "base64" else { return Data(content.utf8) }
        return Data(base64Encoded: content.filter { !$0.isWhitespace })
    }

    public static let editableLimit = 1_048_576

    /// UTF-8 text when the file is small enough and contains no NUL bytes.
    public func text() throws -> String {
        guard size <= Self.editableLimit else { throw GitLabError.fileTooLarge }
        guard let data, !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw GitLabError.binaryFile
        }
        return text
    }
}

public struct FileDiff: Codable, Identifiable, Hashable, Sendable {
    public var id: String { oldPath + "→" + newPath }
    public let oldPath: String
    public let newPath: String
    public var aMode: String?
    public var bMode: String?
    public var newFile: Bool?
    public var renamedFile: Bool?
    public var deletedFile: Bool?
    public let diff: String
    public var tooLarge: Bool?
    public var collapsed: Bool?
    public var generatedFile: Bool?

    public init(oldPath: String, newPath: String, diff: String, newFile: Bool = false,
                renamedFile: Bool = false, deletedFile: Bool = false) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.diff = diff
        self.newFile = newFile
        self.renamedFile = renamedFile
        self.deletedFile = deletedFile
    }

    public var path: String { deletedFile == true ? oldPath : newPath }

    public enum Change: Sendable { case added, deleted, renamed, modified }
    public var change: Change {
        if newFile == true { return .added }
        if deletedFile == true { return .deleted }
        if renamedFile == true { return .renamed }
        return .modified
    }

    public var lineCounts: (additions: Int, deletions: Int) {
        var additions = 0, deletions = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+") && !line.hasPrefix("+++") { additions += 1 }
            else if line.hasPrefix("-") && !line.hasPrefix("---") { deletions += 1 }
        }
        return (additions, deletions)
    }
}

public struct Comparison: Codable, Sendable {
    public var commit: Commit?
    public let commits: [Commit]
    public let diffs: [FileDiff]
    public var compareTimeout: Bool?
    public var compareSameRef: Bool?
}

/// One action of a multi-file commit (`POST /projects/:id/repository/commits`).
public struct CommitAction: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case create, delete, move, update, chmod }
    public var id: String { filePath }
    public var action: Kind
    public var filePath: String
    public var previousPath: String?
    public var content: String?
    public var encoding: String?
    public var lastCommitId: String?

    public init(action: Kind, filePath: String, previousPath: String? = nil, text: String? = nil,
                lastCommitId: String? = nil) {
        self.action = action
        self.filePath = filePath
        self.previousPath = previousPath
        if let text {
            self.content = Data(text.utf8).base64EncodedString()
            self.encoding = "base64"
        }
        self.lastCommitId = lastCommitId
    }

    public var text: String? {
        guard let content else { return nil }
        guard encoding == "base64" else { return content }
        return Data(base64Encoded: content).flatMap { String(data: $0, encoding: .utf8) }
    }
}

public struct CommitRequest: Codable, Sendable {
    public var branch: String
    public var commitMessage: String
    public var startBranch: String?
    public var actions: [CommitAction]
    public var authorName: String?
    public var authorEmail: String?

    public init(branch: String, message: String, startBranch: String? = nil, actions: [CommitAction]) {
        self.branch = branch
        self.commitMessage = message
        self.startBranch = startBranch
        self.actions = actions
    }
}
