import Foundation

/// A small, dependency-free lexer that colours source code well enough for reading on a phone.
/// It is deliberately approximate: keywords, strings, comments, numbers, types and keys.
public struct SyntaxHighlighter: Sendable {
    public enum Kind: String, Sendable { case plain, keyword, string, comment, number, type, attribute, punctuation, function }

    public struct Token: Hashable, Sendable {
        public let text: String
        public let kind: Kind
    }

    public struct Language: Sendable, Hashable {
        public let name: String
        var keywords: Set<String> = []
        var lineComments: [String] = []
        var blockComment: (String, String)? = nil
        var stringDelimiters: [Character] = ["\"", "'"]
        var tripleQuotes = false
        var capitalizedTypes = true
        var keyBeforeColon = false
        var markup = false

        public static func == (lhs: Language, rhs: Language) -> Bool { lhs.name == rhs.name }
        public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    }

    public let language: Language

    public init(language: Language) { self.language = language }

    public init(fileName: String) { self.language = Self.language(for: fileName) }

    /// Tokens per line; multi-line strings and block comments carry over.
    public func highlight(_ source: String) -> [[Token]] {
        var lines: [[Token]] = [[]]

        func emit(_ text: String, _ tokenKind: Kind) {
            guard !text.isEmpty else { return }
            // Split on newlines so every line gets its own token array.
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty { lines[lines.count - 1].append(Token(text: String(part), kind: tokenKind)) }
            }
        }

        let chars = Array(source)
        var i = 0
        var plain = ""
        func flushPlain() { if !plain.isEmpty { emitWords(plain, into: &lines); plain = "" } }

        func hasPrefix(_ text: String, at index: Int) -> Bool {
            let pattern = Array(text)
            guard index + pattern.count <= chars.count else { return false }
            for offset in 0..<pattern.count where chars[index + offset] != pattern[offset] { return false }
            return true
        }

        while i < chars.count {
            let c = chars[i]
            // Block comment
            if let (open, close) = language.blockComment, hasPrefix(open, at: i) {
                flushPlain()
                var j = i + open.count
                while j < chars.count && !hasPrefix(close, at: j) { j += 1 }
                j = min(chars.count, j + close.count)
                emit(String(chars[i..<j]), .comment)
                i = j
                continue
            }
            // Line comment
            if let marker = language.lineComments.first(where: { hasPrefix($0, at: i) }),
               marker != "#" || i == 0 || chars[i - 1].isWhitespace || chars[i - 1] == "\n" {
                flushPlain()
                var j = i
                while j < chars.count && chars[j] != "\n" { j += 1 }
                emit(String(chars[i..<j]), .comment)
                i = j
                continue
            }
            // Strings
            if language.stringDelimiters.contains(c), !(c == "'" && i > 0 && chars[i - 1].isLetter && !language.keyBeforeColon) {
                flushPlain()
                let triple = language.tripleQuotes && hasPrefix(String(repeating: c, count: 3), at: i)
                let closer = triple ? String(repeating: c, count: 3) : String(c)
                var j = i + closer.count
                while j < chars.count {
                    if chars[j] == "\\" { j += 2; continue }
                    if hasPrefix(closer, at: j) { j += closer.count; break }
                    if !triple && c != "`" && chars[j] == "\n" { break }
                    j += 1
                }
                j = min(j, chars.count)
                var tokenKind: Kind = .string
                if language.keyBeforeColon {
                    var k = j
                    while k < chars.count, chars[k] == " " { k += 1 }
                    if k < chars.count, chars[k] == ":" { tokenKind = .attribute }
                }
                emit(String(chars[i..<j]), tokenKind)
                i = j
                continue
            }
            // Markup tags
            if language.markup, c == "<" {
                flushPlain()
                var j = i + 1
                while j < chars.count && chars[j] != ">" && chars[j] != "\n" { j += 1 }
                j = min(chars.count, j + 1)
                emit(String(chars[i..<j]), .keyword)
                i = j
                continue
            }
            if c == "\n" {
                flushPlain()
                lines.append([])
                i += 1
                continue
            }
            plain.append(c)
            i += 1
        }
        flushPlain()
        return lines
    }

    private func emitWords(_ text: String, into lines: inout [[Token]]) {
        let chars = Array(text)
        var i = 0
        var tokens: [Token] = []
        var other = ""
        func flushOther() { if !other.isEmpty { tokens.append(Token(text: other, kind: .plain)); other = "" } }
        while i < chars.count {
            let c = chars[i]
            if c.isLetter || c == "_" || c == "$" || c == "@" {
                flushOther()
                var j = i + 1
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "-" && language.keyBeforeColon) { j += 1 }
                let word = String(chars[i..<j])
                var kind: Kind = .plain
                if language.keywords.contains(word) { kind = .keyword }
                else if language.keyBeforeColon, j < chars.count, chars[j] == ":" { kind = .attribute }
                else if language.capitalizedTypes, let first = word.first, first.isUppercase, word.count > 1 { kind = .type }
                else if word.hasPrefix("@") { kind = .attribute }
                else if j < chars.count, chars[j] == "(" { kind = .function }
                tokens.append(Token(text: word, kind: kind))
                i = j
            } else if c.isNumber {
                flushOther()
                var j = i + 1
                while j < chars.count && (chars[j].isNumber || chars[j].isLetter || chars[j] == "." || chars[j] == "_") { j += 1 }
                tokens.append(Token(text: String(chars[i..<j]), kind: .number))
                i = j
            } else {
                other.append(c)
                i += 1
            }
        }
        flushOther()
        lines[lines.count - 1].append(contentsOf: tokens)
    }

    // MARK: Languages

    static let cFamily: Set<String> = ["if", "else", "for", "while", "do", "switch", "case", "default", "break",
                                       "continue", "return", "true", "false", "null", "nil", "new", "class", "struct",
                                       "enum", "static", "const", "public", "private", "protected", "import", "try",
                                       "catch", "throw", "this", "void", "in", "is", "as"]

    public static func language(for fileName: String) -> Language {
        let lower = fileName.lowercased()
        let ext = (lower as NSString).pathExtension
        switch (lower, ext) {
        case (_, "swift"):
            return Language(name: "Swift", keywords: cFamily.union(["func", "let", "var", "guard", "defer", "extension", "protocol",
                "init", "deinit", "self", "Self", "some", "any", "async", "await", "throws", "rethrows", "where", "inout",
                "final", "override", "mutating", "fileprivate", "internal", "open", "typealias", "associatedtype", "actor",
                "repeat", "fallthrough", "subscript", "lazy", "weak", "unowned", "@MainActor", "@State", "@Observable"]),
                lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\""], tripleQuotes: true)
        case (_, "kt"), (_, "kts"):
            return Language(name: "Kotlin", keywords: cFamily.union(["fun", "val", "var", "object", "companion", "data",
                "sealed", "when", "override", "suspend", "inline", "package", "internal", "open", "lateinit", "by", "init",
                "it", "interface", "typealias", "out", "reified", "vararg"]),
                lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'"], tripleQuotes: true)
        case (_, "java"), (_, "c"), (_, "h"), (_, "cpp"), (_, "cc"), (_, "hpp"), (_, "m"), (_, "mm"), (_, "cs"), (_, "dart"), (_, "scala"):
            return Language(name: ext.uppercased(), keywords: cFamily.union(["int", "long", "char", "float", "double", "bool",
                "boolean", "unsigned", "extends", "implements", "interface", "package", "final", "abstract", "namespace",
                "using", "template", "typename", "virtual", "override", "sizeof", "struct", "typedef", "auto", "var",
                "async", "await", "extern", "#include", "#define", "#import"]),
                lineComments: ["//"], blockComment: ("/*", "*/"))
        case (_, "go"):
            return Language(name: "Go", keywords: cFamily.union(["func", "package", "var", "type", "interface", "map", "chan",
                "go", "defer", "select", "range", "fallthrough", "goto", "struct", "string", "int", "error", "bool", "byte"]),
                lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"], capitalizedTypes: false)
        case (_, "rs"):
            return Language(name: "Rust", keywords: cFamily.union(["fn", "let", "mut", "impl", "trait", "pub", "use", "mod",
                "crate", "self", "Self", "match", "loop", "where", "move", "ref", "dyn", "unsafe", "async", "await", "type",
                "Some", "None", "Ok", "Err"]),
                lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\""])
        case (_, "js"), (_, "jsx"), (_, "ts"), (_, "tsx"), (_, "mjs"), (_, "cjs"), (_, "vue"), (_, "svelte"):
            return Language(name: ext == "ts" || ext == "tsx" ? "TypeScript" : "JavaScript",
                keywords: cFamily.union(["function", "let", "var", "const", "export", "from", "async", "await", "yield",
                "typeof", "instanceof", "undefined", "of", "extends", "interface", "type", "implements", "readonly",
                "delete", "super", "get", "set", "declare", "keyof", "never", "unknown", "any"]),
                lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"])
        case (_, "py"), (_, "pyi"):
            return Language(name: "Python", keywords: ["def", "class", "if", "elif", "else", "for", "while", "return",
                "import", "from", "as", "with", "try", "except", "finally", "raise", "pass", "break", "continue", "lambda",
                "yield", "async", "await", "None", "True", "False", "and", "or", "not", "in", "is", "global", "nonlocal",
                "self", "match", "case"],
                lineComments: ["#"], stringDelimiters: ["\"", "'"], tripleQuotes: true)
        case (_, "rb"), ("gemfile", _), ("rakefile", _):
            return Language(name: "Ruby", keywords: ["def", "class", "module", "if", "elsif", "else", "unless", "end",
                "do", "while", "until", "return", "yield", "begin", "rescue", "ensure", "require", "self", "nil",
                "true", "false", "and", "or", "not", "then", "case", "when", "attr_reader", "attr_accessor"],
                lineComments: ["#"])
        case (_, "sh"), (_, "bash"), (_, "zsh"), (".bashrc", _), (".zshrc", _), ("dockerfile", _), (_, "dockerfile"):
            return Language(name: lower == "dockerfile" || ext == "dockerfile" ? "Dockerfile" : "Shell",
                keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "case", "esac",
                "function", "return", "export", "local", "set", "echo", "exit", "source", "FROM", "RUN", "COPY", "ADD",
                "CMD", "ENTRYPOINT", "ENV", "ARG", "WORKDIR", "EXPOSE", "USER", "LABEL", "VOLUME"],
                lineComments: ["#"], capitalizedTypes: false)
        case (_, "yml"), (_, "yaml"):
            return Language(name: "YAML", keywords: ["true", "false", "null", "yes", "no"],
                lineComments: ["#"], capitalizedTypes: false, keyBeforeColon: true)
        case (_, "json"), (_, "jsonc"):
            return Language(name: "JSON", keywords: ["true", "false", "null"], lineComments: ext == "jsonc" ? ["//"] : [],
                stringDelimiters: ["\""], capitalizedTypes: false, keyBeforeColon: true)
        case (_, "toml"), (_, "ini"), (_, "cfg"), (_, "properties"), (_, "conf"), (".gitignore", _), (".env", _):
            return Language(name: "Config", keywords: ["true", "false"], lineComments: ["#", ";"],
                capitalizedTypes: false, keyBeforeColon: true)
        case (_, "html"), (_, "htm"), (_, "xml"), (_, "plist"), (_, "svg"), (_, "xib"), (_, "storyboard"):
            return Language(name: ext == "xml" || ext == "plist" ? "XML" : "HTML", blockComment: ("<!--", "-->"),
                stringDelimiters: ["\""], capitalizedTypes: false, markup: true)
        case (_, "css"), (_, "scss"), (_, "less"):
            return Language(name: "CSS", keywords: ["important", "media", "import", "from", "to"],
                lineComments: ext == "css" ? [] : ["//"], blockComment: ("/*", "*/"), capitalizedTypes: false, keyBeforeColon: true)
        case (_, "sql"):
            return Language(name: "SQL", keywords: ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
                "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "JOIN", "LEFT", "RIGHT", "INNER", "ON", "AND", "OR", "NOT",
                "NULL", "AS", "ORDER", "BY", "GROUP", "LIMIT", "PRIMARY", "KEY", "select", "from", "where", "insert",
                "update", "delete", "create", "table", "join", "on", "and", "or", "not", "null", "as", "order", "by"],
                lineComments: ["--"], blockComment: ("/*", "*/"), capitalizedTypes: false)
        case (_, "md"), (_, "markdown"), (_, "txt"), (_, "rst"), (_, ""):
            return Language(name: ext == "md" || ext == "markdown" ? "Markdown" : "Text", stringDelimiters: [], capitalizedTypes: false)
        default:
            return Language(name: ext.uppercased(), keywords: cFamily, lineComments: ["//", "#"], blockComment: ("/*", "*/"),
                            capitalizedTypes: false)
        }
    }
}
