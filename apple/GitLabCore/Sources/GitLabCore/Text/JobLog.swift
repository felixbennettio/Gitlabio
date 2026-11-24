import Foundation

/// A parsed CI job log: ANSI SGR colours become styled spans, and GitLab's
/// `section_start` / `section_end` markers become collapsible sections.
public struct JobLog: Sendable {
    public struct Style: Hashable, Sendable {
        public var foreground: Int?
        public var background: Int?
        public var bold = false
        public var italic = false
        public var underline = false
        public init() {}
    }

    public struct Span: Hashable, Sendable {
        public let text: String
        public let style: Style
    }

    public struct Line: Hashable, Sendable, Identifiable {
        public let id: Int
        public let spans: [Span]
        /// Section this line belongs to (innermost), if any.
        public let section: String?
        /// Set on the line that opens a section.
        public let opensSection: String?
        public var plainText: String { spans.map(\.text).joined() }
    }

    public struct Section: Hashable, Sendable, Identifiable {
        public let id: String
        public var title: String
        public let startLine: Int
        public var endLine: Int?
        public var collapsedByDefault: Bool
        public var duration: TimeInterval?
    }

    public private(set) var lines: [Line] = []
    public private(set) var sections: [String: Section] = [:]

    public init(_ data: Data, maxLines: Int = 20_000) {
        let text = String(decoding: data, as: UTF8.self)
        self.init(text, maxLines: maxLines)
    }

    public init(_ text: String, maxLines: Int = 20_000) {
        var style = Style()
        var stack: [(name: String, started: TimeInterval?)] = []
        var physical = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if physical.last == "" { physical.removeLast() }
        if physical.count > maxLines { physical = Array(physical.suffix(maxLines)) }

        for raw in physical {
            var content = raw
            var opened: String?
            // Section markers look like "section_start:1700000000:name[collapsed=true]\r\e[0K".
            while let marker = Self.sectionMarker(in: content) {
                if marker.isStart {
                    stack.append((marker.name, marker.timestamp))
                    if sections[marker.name] == nil {
                        sections[marker.name] = Section(id: marker.name, title: marker.name, startLine: lines.count,
                                                        endLine: nil, collapsedByDefault: marker.collapsed, duration: nil)
                    }
                    opened = marker.name
                } else if let index = stack.lastIndex(where: { $0.name == marker.name }) {
                    let start = stack[index].started
                    stack.remove(at: index)
                    let startLine = sections[marker.name]?.startLine ?? 0
                    sections[marker.name]?.endLine = max(lines.count - 1, startLine)
                    if let start, let end = marker.timestamp { sections[marker.name]?.duration = end - start }
                }
                content.replaceSubrange(marker.range, with: "")
            }
            // A carriage return redraws the line; only the final segment is visible.
            if let last = content.split(separator: "\r", omittingEmptySubsequences: false).last(where: { !$0.isEmpty }) {
                content = String(last)
            } else if content.contains("\r") {
                content = ""
            }
            let spans = Self.parseSGR(content, style: &style)
            if let name = opened {
                let title = spans.map(\.text).joined().trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { sections[name]?.title = title }
            }
            if spans.isEmpty && opened == nil && content.isEmpty && raw.contains("section_end") { continue }
            lines.append(Line(id: lines.count, spans: spans, section: stack.last?.name, opensSection: opened))
        }
    }

    struct Marker {
        let isStart: Bool
        let name: String
        let timestamp: TimeInterval?
        let collapsed: Bool
        let range: Range<String.Index>
    }

    static func sectionMarker(in text: String) -> Marker? {
        for keyword in ["section_start:", "section_end:"] {
            guard let start = text.range(of: keyword) else { continue }
            var cursor = start.upperBound
            var timestamp = ""
            while cursor < text.endIndex, text[cursor].isNumber { timestamp.append(text[cursor]); cursor = text.index(after: cursor) }
            guard cursor < text.endIndex, text[cursor] == ":" else { continue }
            cursor = text.index(after: cursor)
            var name = ""
            while cursor < text.endIndex, !["\r", "[", "\u{1B}"].contains(text[cursor]) {
                name.append(text[cursor]); cursor = text.index(after: cursor)
            }
            var collapsed = false
            if cursor < text.endIndex, text[cursor] == "[" , let close = text[cursor...].firstIndex(of: "]") {
                collapsed = text[cursor...close].contains("collapsed=true")
                cursor = text.index(after: close)
            }
            if cursor < text.endIndex, text[cursor] == "\r" { cursor = text.index(after: cursor) }
            if text[cursor...].hasPrefix("\u{1B}[0K") { cursor = text.index(cursor, offsetBy: 4) }
            return Marker(isStart: keyword == "section_start:", name: name, timestamp: TimeInterval(timestamp),
                          collapsed: collapsed, range: start.lowerBound..<cursor)
        }
        return nil
    }

    /// Splits text on ESC[…m sequences, carrying the style across calls (and lines).
    static func parseSGR(_ text: String, style: inout Style) -> [Span] {
        var spans: [Span] = []
        var buffer = ""
        var index = text.startIndex
        func flush() {
            if !buffer.isEmpty { spans.append(Span(text: buffer, style: style)); buffer = "" }
        }
        while index < text.endIndex {
            let character = text[index]
            if character == "\u{1B}", text.index(after: index) < text.endIndex, text[text.index(after: index)] == "[" {
                var cursor = text.index(index, offsetBy: 2)
                var parameters = ""
                while cursor < text.endIndex, !(text[cursor].isLetter) { parameters.append(text[cursor]); cursor = text.index(after: cursor) }
                guard cursor < text.endIndex else { break }
                let command = text[cursor]
                if command == "m" {
                    flush()
                    apply(parameters, to: &style)
                }
                index = text.index(after: cursor)
                continue
            }
            buffer.append(character)
            index = text.index(after: index)
        }
        flush()
        return spans
    }

    static func apply(_ parameters: String, to style: inout Style) {
        var codes = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        if codes.isEmpty { codes = [0] }
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = Style()
            case 1: style.bold = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 22: style.bold = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 30...37: style.foreground = code - 30
            case 39: style.foreground = nil
            case 40...47: style.background = code - 40
            case 49: style.background = nil
            case 90...97: style.foreground = code - 90 + 8
            case 100...107: style.background = code - 100 + 8
            case 38, 48:
                // 256-colour: 38;5;n — truecolour (38;2;r;g;b) is approximated as bright white.
                if index + 2 < codes.count, codes[index + 1] == 5 {
                    if code == 38 { style.foreground = codes[index + 2] } else { style.background = codes[index + 2] }
                    index += 2
                } else if index + 4 < codes.count, codes[index + 1] == 2 {
                    if code == 38 { style.foreground = 15 } else { style.background = nil }
                    index += 4
                }
            default: break
            }
            index += 1
        }
    }
}
