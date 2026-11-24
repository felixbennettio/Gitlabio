import SwiftUI
import GitLabCore

/// Renders GitLab Markdown blocks natively. Relative links and images resolve against `base`.
struct MarkdownView: View {
    let text: String
    var base: URL?
    var compact = false

    private var blocks: [MarkdownBlock] { Markdown.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, compact ? 0 : (level <= 2 ? 6 : 2))
            if level <= 2 && !compact { Divider() }
        case .paragraph(let text):
            inline(text).font(.body)
        case .code(let language, let text):
            CodeBlock(text: text, language: language)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Group {
                            if let checked = item.checked {
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(checked ? Theme.opened : .secondary)
                            } else if ordered {
                                Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                            } else {
                                Text("•").foregroundStyle(Theme.orange)
                            }
                        }
                        .frame(minWidth: 16, alignment: .trailing)
                        inline(item.text)
                            .strikethrough(item.checked == true, color: .secondary)
                            .foregroundStyle(item.checked == true ? .secondary : .primary)
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.purple.opacity(0.6)).frame(width: 3)
                inline(text).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow { ForEach(Array(header.enumerated()), id: \.offset) { _, cell in inline(cell).font(.subheadline.bold()) } }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in inline(cell).font(.subheadline) } }
                    }
                }
                .padding(12)
            }
            .solidCard(cornerRadius: 12)
        case .image(let alt, let url):
            if let resolved = resolve(url) {
                AsyncImage(url: resolved) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure: Label(alt.isEmpty ? "图片" : alt, systemImage: "photo").foregroundStyle(.secondary)
                    default: ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .accessibilityLabel(alt)
            }
        case .rule:
            Divider()
        }
    }

    private func inline(_ markdown: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        var value = (try? AttributedString(markdown: markdown, options: options, baseURL: base)) ?? AttributedString(markdown)
        for run in value.runs where run.inlinePresentationIntent?.contains(.code) == true {
            value[run.range].font = .system(.callout, design: .monospaced)
            value[run.range].backgroundColor = Color.secondary.opacity(0.14)
        }
        for run in value.runs where run.link != nil {
            value[run.range].foregroundColor = Theme.orange
        }
        return Text(value)
    }

    private func resolve(_ path: String) -> URL? {
        if let url = URL(string: path), url.scheme != nil { return url }
        guard let base else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }
}

/// A fenced code block with highlighting and horizontal scrolling.
struct CodeBlock: View {
    let text: String
    var language: String = ""

    var body: some View {
        let name = language.isEmpty ? "snippet.txt" : "snippet.\(language)"
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "代码" : language).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { Clipboard.copy(text); Haptics.success() } label: { Image(systemName: "doc.on.doc") }
                    .font(.caption).buttonStyle(.borderless).accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 12).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HighlightedText(source: text, fileName: name)
                    .padding(12)
            }
        }
        .solidCard(cornerRadius: 12)
    }
}

/// Monospaced highlighted text without line numbers.
struct HighlightedText: View {
    let source: String
    let fileName: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lines = SyntaxHighlighter(fileName: fileName).highlight(source)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, tokens in
                CodeLine(tokens: tokens, dark: scheme == .dark)
            }
        }
        .font(.system(.footnote, design: .monospaced))
    }
}

struct CodeLine: View {
    let tokens: [SyntaxHighlighter.Token]
    let dark: Bool

    var body: some View {
        tokens.reduce(Text("")) { text, token in
            text + Text(token.text).foregroundColor(Theme.color(for: token.kind, dark: dark))
                .italic(token.kind == .comment)
                .bold(token.kind == .keyword)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 16, alignment: .leading)
    }
}
