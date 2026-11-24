import Foundation

/// Block-level Markdown (GitLab Flavored subset). Inline formatting inside each block is left
/// as Markdown text for the UI to render with `AttributedString(markdown:)`.
public enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String, text: String)
    case list(ordered: Bool, items: [ListItem])
    case quote(String)
    case table(header: [String], rows: [[String]])
    case image(alt: String, url: String)
    case rule

    public struct ListItem: Hashable, Sendable {
        public let text: String
        /// nil for a plain item, true/false for a task list checkbox.
        public let checked: Bool?
        public let depth: Int
    }
}

public enum Markdown {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flushParagraph(); index += 1; continue }

            // Fenced code
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index]); index += 1
                }
                index += 1
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                continue
            }

            // Headings
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let rest = trimmed.dropFirst(level)
                if level <= 6, rest.isEmpty || rest.hasPrefix(" ") {
                    flushParagraph()
                    blocks.append(.heading(level: level, text: rest.trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)))
                    index += 1
                    continue
                }
            }

            // Setext headings
            if !paragraph.isEmpty, !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) || (trimmed.allSatisfy({ $0 == "-" }) && trimmed.count >= 2) {
                let text = paragraph.joined(separator: " ")
                paragraph = []
                blocks.append(.heading(level: trimmed.first == "=" ? 1 : 2, text: text))
                index += 1
                continue
            }

            // Rule
            let compact = trimmed.replacingOccurrences(of: " ", with: "")
            if compact.count >= 3, Set(compact).count == 1, ["-", "*", "_"].contains(compact.first!) {
                flushParagraph(); blocks.append(.rule); index += 1; continue
            }

            // Standalone image
            if trimmed.hasPrefix("!["), trimmed.hasSuffix(")"), let close = trimmed.range(of: "]("),
               trimmed.firstIndex(of: "\n") == nil {
                flushParagraph()
                let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
                var url = String(trimmed[close.upperBound..<trimmed.index(before: trimmed.endIndex)])
                if let space = url.firstIndex(of: " ") { url = String(url[..<space]) }
                blocks.append(.image(alt: alt, url: url))
                index += 1
                continue
            }

            // Block quote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            // Table
            if trimmed.hasPrefix("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let header = cells(trimmed)
                index += 2
                var rows: [[String]] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[index].trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // Lists
            if listMarker(line) != nil {
                flushParagraph()
                var items: [MarkdownBlock.ListItem] = []
                let ordered = listMarker(line)!.ordered
                while index < lines.count, let marker = listMarker(lines[index]), marker.ordered == ordered || marker.indent > 0 {
                    var text = marker.text
                    var checked: Bool?
                    if text.hasPrefix("[ ] ") { checked = false; text.removeFirst(4) }
                    else if text.lowercased().hasPrefix("[x] ") { checked = true; text.removeFirst(4) }
                    items.append(.init(text: text, checked: checked, depth: marker.indent / 2))
                    index += 1
                    // Continuation lines belong to the previous item.
                    while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                          listMarker(lines[index]) == nil, lines[index].hasPrefix("  ") {
                        let last = items.removeLast()
                        items.append(.init(text: last.text + " " + lines[index].trimmingCharacters(in: .whitespaces),
                                           checked: last.checked, depth: last.depth))
                        index += 1
                    }
                }
                blocks.append(.list(ordered: ordered, items: items))
                continue
            }

            // Indented HTML comments and details tags are noise on mobile.
            if trimmed.hasPrefix("<!--") {
                while index < lines.count, !lines[index].contains("-->") { index += 1 }
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    static func listMarker(_ line: String) -> (ordered: Bool, text: String, indent: Int)? {
        let indent = line.prefix(while: { $0 == " " }).count
        let rest = line.dropFirst(indent)
        if let first = rest.first, ["-", "*", "+"].contains(first), rest.dropFirst().first == " " {
            return (false, String(rest.dropFirst(2)), indent)
        }
        let digits = rest.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count < 10 {
            let after = rest.dropFirst(digits.count)
            if (after.first == "." || after.first == ")"), after.dropFirst().first == " " {
                return (true, String(after.dropFirst(2)), indent)
            }
        }
        return nil
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    static func cells(_ line: String) -> [String] {
        var text = line
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
