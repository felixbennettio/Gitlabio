import Foundation

public struct DiffLine: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable { case context, addition, deletion, noNewline }
    public let id: Int
    public let kind: Kind
    public let text: String
    public let oldLine: Int?
    public let newLine: Int?
}

public struct DiffHunk: Hashable, Sendable, Identifiable {
    public let id: Int
    public let header: String
    /// Function or section name GitLab/Git appends after the `@@` range.
    public let section: String
    public let lines: [DiffLine]
}

public enum DiffParser {
    /// Parses the body of a unified diff (as GitLab returns in `diff`) into hunks with
    /// old/new line numbers.
    public static func parse(_ diff: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var header = ""
        var section = ""
        var lines: [DiffLine] = []
        var oldLine = 0, newLine = 0, lineID = 0
        var inHunk = false

        func flush() {
            if inHunk { hunks.append(DiffHunk(id: hunks.count, header: header, section: section, lines: lines)) }
            lines = []
        }

        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                flush()
                inHunk = true
                header = line
                (oldLine, newLine, section) = parseHeader(line)
                continue
            }
            guard inHunk else { continue }
            lineID += 1
            if line.hasPrefix("+") {
                lines.append(DiffLine(id: lineID, kind: .addition, text: String(line.dropFirst()), oldLine: nil, newLine: newLine))
                newLine += 1
            } else if line.hasPrefix("-") {
                lines.append(DiffLine(id: lineID, kind: .deletion, text: String(line.dropFirst()), oldLine: oldLine, newLine: nil))
                oldLine += 1
            } else if line.hasPrefix("\\") {
                lines.append(DiffLine(id: lineID, kind: .noNewline, text: line, oldLine: nil, newLine: nil))
            } else if line.isEmpty && raw.endIndex == diff.endIndex {
                continue
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                lines.append(DiffLine(id: lineID, kind: .context, text: text, oldLine: oldLine, newLine: newLine))
                oldLine += 1
                newLine += 1
            }
        }
        flush()
        return hunks
    }

    /// `@@ -12,7 +12,9 @@ func name` → (12, 12, "func name")
    static func parseHeader(_ header: String) -> (Int, Int, String) {
        let parts = header.components(separatedBy: "@@")
        let ranges = parts.count > 1 ? parts[1] : ""
        var old = 1, new = 1
        for token in ranges.split(separator: " ") {
            let numbers = token.dropFirst().split(separator: ",")
            guard let first = numbers.first, let value = Int(first) else { continue }
            if token.hasPrefix("-") { old = value } else if token.hasPrefix("+") { new = value }
        }
        let section = parts.count > 2 ? parts[2...].joined(separator: "@@").trimmingCharacters(in: .whitespaces) : ""
        return (old, new, section)
    }

    /// Pairs deletions with additions for side-by-side rendering.
    public static func sideBySide(_ hunk: DiffHunk) -> [(left: DiffLine?, right: DiffLine?)] {
        var rows: [(DiffLine?, DiffLine?)] = []
        var deletions: [DiffLine] = []
        var additions: [DiffLine] = []
        func flushChanges() {
            for index in 0..<max(deletions.count, additions.count) {
                rows.append((index < deletions.count ? deletions[index] : nil,
                             index < additions.count ? additions[index] : nil))
            }
            deletions = []
            additions = []
        }
        for line in hunk.lines {
            switch line.kind {
            case .deletion: deletions.append(line)
            case .addition: additions.append(line)
            case .context, .noNewline:
                flushChanges()
                rows.append((line, line))
            }
        }
        flushChanges()
        return rows
    }
}
