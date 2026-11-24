import Foundation

extension GitLabClient {
    func repo(_ project: Int) -> [String] { projectPath(project) + ["repository"] }

    public func tree(_ project: Int, ref: String, path: String = "", page: Int = 1) async throws -> Page<TreeEntry> {
        var query: [URLQueryItem] = [.init(name: "ref", value: ref)]
        if !path.isEmpty { query.append(.init(name: "path", value: path)) }
        let page: Page<TreeEntry> = try await list(repo(project) + ["tree"], page: page, perPage: 100, query: query)
        var sorted = page
        sorted.items.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return sorted
    }

    public func file(_ project: Int, path: String, ref: String) async throws -> RepositoryFile {
        try await get(repo(project) + ["files", path], query: [.init(name: "ref", value: ref)])
    }

    public func rawFile(_ project: Int, path: String, ref: String) async throws -> Data {
        try await data(repo(project) + ["files", path, "raw"], query: [.init(name: "ref", value: ref)]).0
    }

    // MARK: Branches and tags

    public func branches(_ project: Int, search: String = "", page: Int = 1) async throws -> Page<Branch> {
        try await list(repo(project) + ["branches"], page: page,
                       query: search.isEmpty ? [] : [.init(name: "search", value: search)])
    }

    public func branch(_ project: Int, name: String) async throws -> Branch {
        try await get(repo(project) + ["branches", name])
    }

    public func createBranch(_ project: Int, name: String, from ref: String) async throws -> Branch {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(" "), !name.hasPrefix("-") else {
            throw GitLabError.invalidInput("分支名不能为空、不能包含空格或以 - 开头。")
        }
        return try await send("POST", repo(project) + ["branches"],
                              query: [.init(name: "branch", value: name), .init(name: "ref", value: ref)])
    }

    public func deleteBranch(_ project: Int, name: String) async throws {
        try await perform("DELETE", repo(project) + ["branches", name])
    }

    public func tags(_ project: Int, page: Int = 1) async throws -> Page<Tag> {
        try await list(repo(project) + ["tags"], page: page)
    }

    // MARK: Commits

    public func commits(_ project: Int, ref: String, path: String = "", page: Int = 1) async throws -> Page<Commit> {
        var query: [URLQueryItem] = [.init(name: "ref_name", value: ref)]
        if !path.isEmpty { query.append(.init(name: "path", value: path)) }
        return try await list(repo(project) + ["commits"], page: page, query: query)
    }

    public func commit(_ project: Int, sha: String) async throws -> Commit {
        try await get(repo(project) + ["commits", sha], query: [.init(name: "stats", value: "true")])
    }

    public func commitDiff(_ project: Int, sha: String, page: Int = 1) async throws -> Page<FileDiff> {
        try await list(repo(project) + ["commits", sha, "diff"], page: page, perPage: 50)
    }

    public func compare(_ project: Int, from: String, to: String) async throws -> Comparison {
        try await get(repo(project) + ["compare"], query: [.init(name: "from", value: from), .init(name: "to", value: to)])
    }

    /// Creates one commit containing all `actions` on `branch`. When `startBranch` is set and
    /// `branch` does not exist yet, GitLab creates it from `startBranch` first.
    public func createCommit(_ project: Int, _ request: CommitRequest) async throws -> Commit {
        guard !request.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitLabError.invalidInput("请填写提交说明。")
        }
        guard !request.actions.isEmpty else { throw GitLabError.invalidInput("没有要提交的更改。") }
        return try await send("POST", repo(project) + ["commits"], body: request)
    }
}
