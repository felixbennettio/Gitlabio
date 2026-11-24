import Foundation
import Observation
import GitLabCore

/// Edits staged in the app for one project, committed together through the Commits API.
/// This is a remote commit (no local repository): GitLab applies all actions atomically.
@MainActor @Observable
final class ChangeBasket {
    struct Change: Identifiable, Hashable {
        enum Kind: Hashable { case create, update, delete, rename(from: String) }
        var id: String { path }
        var path: String
        var kind: Kind
        var text: String?
        var original: String?
        /// Branch the file was read from, and the commit id it was based on (conflict detection).
        var baseRef: String
        var lastCommitId: String?

        var symbol: String {
            switch kind {
            case .create: return "plus.square.fill"
            case .update: return "pencil.line"
            case .delete: return "minus.square.fill"
            case .rename: return "arrow.right.square.fill"
            }
        }

        var title: String {
            switch kind {
            case .create: return "新建"
            case .update: return "修改"
            case .delete: return "删除"
            case .rename(let from): return "重命名自 \((from as NSString).lastPathComponent)"
            }
        }

        var action: CommitAction {
            switch kind {
            case .create: return CommitAction(action: .create, filePath: path, text: text ?? "")
            case .update: return CommitAction(action: .update, filePath: path, text: text ?? "", lastCommitId: lastCommitId)
            case .delete: return CommitAction(action: .delete, filePath: path, lastCommitId: lastCommitId)
            case .rename(let from): return CommitAction(action: .move, filePath: path, previousPath: from, text: text, lastCommitId: lastCommitId)
            }
        }

        /// A unified diff of the change for preview.
        var previewDiff: FileDiff {
            let old = original ?? ""
            let new = kind == .delete ? "" : (text ?? "")
            let diff = LineDiff.unified(old: old, new: new)
            switch kind {
            case .create: return FileDiff(oldPath: path, newPath: path, diff: diff, newFile: true)
            case .delete: return FileDiff(oldPath: path, newPath: path, diff: diff, deletedFile: true)
            case .rename(let from): return FileDiff(oldPath: from, newPath: path, diff: diff, renamedFile: true)
            case .update: return FileDiff(oldPath: path, newPath: path, diff: diff)
            }
        }
    }

    let project: Project
    private(set) var changes: [Change] = []
    var branch: String

    init(project: Project) {
        self.project = project
        self.branch = project.defaultBranch ?? "main"
    }

    var isEmpty: Bool { changes.isEmpty }
    var count: Int { changes.count }

    func change(for path: String) -> Change? { changes.first { $0.path == path } }

    func stage(_ change: Change) {
        if let index = changes.firstIndex(where: { $0.path == change.path }) {
            var merged = change
            // Keep the original base so the final diff is against the server version.
            merged.original = changes[index].original ?? change.original
            merged.lastCommitId = changes[index].lastCommitId ?? change.lastCommitId
            if case .create = changes[index].kind, change.kind == .update { merged.kind = .create }
            if merged.kind == .update, merged.text == merged.original { changes.remove(at: index); return }
            changes[index] = merged
        } else {
            changes.append(change)
        }
        branch = change.baseRef
    }

    func discard(_ path: String) { changes.removeAll { $0.path == path } }
    func discardAll() { changes.removeAll() }

    func commit(using client: GitLabClient, message: String, targetBranch: String) async throws -> Commit {
        let base = changes.first?.baseRef ?? branch
        let request = CommitRequest(branch: targetBranch, message: message,
                                    startBranch: targetBranch == base ? nil : base,
                                    actions: changes.map(\.action))
        let commit = try await client.createCommit(project.id, request)
        changes.removeAll()
        return commit
    }
}

/// Minimal line diff (LCS) used to preview staged edits.
enum LineDiff {
    static func unified(old: String, new: String, context: Int = 3) -> String {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        // Guard against quadratic blow-up on very large files.
        guard a.count * b.count <= 4_000_000 else {
            return "@@ -1,\(a.count) +1,\(b.count) @@\n" + a.map { "-" + $0 }.joined(separator: "\n") + "\n" + b.map { "+" + $0 }.joined(separator: "\n")
        }
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        enum Op { case same(String), del(String), add(String) }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] { ops.append(.same(a[i])); i += 1; j += 1 }
            else if j < b.count, i == a.count || lcs[i][j + 1] >= lcs[i + 1][j] { ops.append(.add(b[j])); j += 1 }
            else { ops.append(.del(a[i])); i += 1 }
        }
        // Group into hunks with context.
        var output: [String] = []
        var index = 0
        var oldLine = 1, newLine = 1
        var positions: [(old: Int, new: Int)] = []
        for op in ops {
            positions.append((oldLine, newLine))
            switch op {
            case .same: oldLine += 1; newLine += 1
            case .del: oldLine += 1
            case .add: newLine += 1
            }
        }
        while index < ops.count {
            guard let changeStart = ops[index...].firstIndex(where: { if case .same = $0 { return false } else { return true } }) else { break }
            let start = max(0, changeStart - context)
            var end = changeStart
            var lastChange = changeStart
            while end < ops.count {
                if case .same = ops[end] {
                    if end - lastChange > context * 2 { break }
                } else {
                    lastChange = end
                }
                end += 1
            }
            end = min(ops.count, lastChange + context + 1)
            var lines: [String] = []
            var oldCount = 0, newCount = 0
            for op in ops[start..<end] {
                switch op {
                case .same(let text): lines.append(" " + text); oldCount += 1; newCount += 1
                case .del(let text): lines.append("-" + text); oldCount += 1
                case .add(let text): lines.append("+" + text); newCount += 1
                }
            }
            output.append("@@ -\(oldCount == 0 ? 0 : positions[start].old),\(oldCount) +\(newCount == 0 ? 0 : positions[start].new),\(newCount) @@")
            output += lines
            index = end
        }
        return output.joined(separator: "\n")
    }
}
