import SwiftUI
import GitLabCore

/// A full source file with line numbers, syntax colouring and optional wrapping.
struct SourceCodeView: View {
    let text: String
    let fileName: String
    var wrap = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lines = SyntaxHighlighter(fileName: fileName).highlight(text)
        let gutter = max(2, String(lines.count).count)
        let content = LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, tokens in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(index + 1))
                        .foregroundStyle(.tertiary)
                        .frame(width: CGFloat(gutter) * 9, alignment: .trailing)
                        .accessibilityHidden(true)
                    if wrap {
                        tokens.reduce(Text("")) { $0 + Text($1.text).foregroundColor(Theme.color(for: $1.kind, dark: scheme == .dark)) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        CodeLine(tokens: tokens, dark: scheme == .dark)
                    }
                }
                .padding(.vertical, 1.5)
                .padding(.horizontal, 12)
            }
        }
        .font(.system(.footnote, design: .monospaced))
        .padding(.vertical, 10)
        .textSelection(.enabled)

        if wrap {
            ScrollView { content }
        } else {
            ScrollView([.vertical, .horizontal]) { content }
        }
    }
}

// MARK: Diffs

struct DiffFileHeader: View {
    let diff: FileDiff
    var expanded: Bool

    var body: some View {
        let counts = diff.lineCounts
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text((diff.path as NSString).lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                Group {
                    if diff.change == .renamed {
                        Text("\(diff.oldPath) → \(diff.newPath)")
                    } else {
                        Text((diff.path as NSString).deletingLastPathComponent)
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            if counts.additions > 0 { Text("+\(counts.additions)").foregroundStyle(Theme.opened) }
            if counts.deletions > 0 { Text("−\(counts.deletions)").foregroundStyle(Theme.closed) }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch diff.change {
        case .added: return "plus.square.fill"
        case .deleted: return "minus.square.fill"
        case .renamed: return "arrow.right.square.fill"
        case .modified: return "pencil.line"
        }
    }

    private var color: Color {
        switch diff.change {
        case .added: return Theme.opened
        case .deleted: return Theme.closed
        case .renamed: return Theme.purple
        case .modified: return Theme.orange
        }
    }
}

/// Unified diff of one file. `onComment` enables long-press inline comments.
struct DiffBody: View {
    let diff: FileDiff
    var onComment: ((DiffLine) -> Void)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if diff.tooLarge == true || (diff.diff.isEmpty && diff.collapsed == true) {
            Label("差异过大，未在此显示。可在浏览器中查看。", systemImage: "eye.slash")
                .font(.footnote).foregroundStyle(.secondary).padding()
        } else if diff.diff.isEmpty {
            Label(diff.change == .renamed ? "仅重命名，内容未变" : "二进制文件或内容无变化", systemImage: "doc")
                .font(.footnote).foregroundStyle(.secondary).padding()
        } else {
            let highlighter = SyntaxHighlighter(fileName: diff.path)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(DiffParser.parse(diff.diff)) { hunk in
                        Text(hunk.header)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.purple)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.purple.opacity(0.08))
                        ForEach(hunk.lines) { line in
                            DiffLineRow(line: line, tokens: highlighter.highlight(line.text).first ?? [], dark: scheme == .dark)
                                .contextMenu {
                                    if let onComment, line.kind != .noNewline {
                                        Button { onComment(line) } label: { Label("评论此行", systemImage: "text.bubble") }
                                    }
                                    Button { Clipboard.copy(line.text) } label: { Label("复制", systemImage: "doc.on.doc") }
                                }
                        }
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
    }
}

struct DiffLineRow: View {
    let line: DiffLine
    let tokens: [SyntaxHighlighter.Token]
    let dark: Bool

    var body: some View {
        HStack(spacing: 0) {
            number(line.oldLine)
            number(line.newLine)
            Text(marker).foregroundStyle(markerColor).frame(width: 14)
            if line.kind == .noNewline {
                Text(line.text).foregroundStyle(.secondary).italic()
            } else {
                CodeLine(tokens: tokens, dark: dark)
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 1)
        .background(background)
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(.tertiary)
            .frame(width: 38, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var marker: String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "−"
        default: return " "
        }
    }

    private var markerColor: Color { line.kind == .addition ? Theme.opened : line.kind == .deletion ? Theme.closed : .clear }

    private var background: Color {
        switch line.kind {
        case .addition: return Theme.opened.opacity(dark ? 0.18 : 0.12)
        case .deletion: return Theme.closed.opacity(dark ? 0.18 : 0.10)
        default: return .clear
        }
    }
}

/// A list of changed files, each collapsible, with per-file diffs.
struct DiffList: View {
    let diffs: [FileDiff]
    var onComment: ((FileDiff, DiffLine) -> Void)?
    @State private var collapsed: Set<String> = []

    var body: some View {
        LazyVStack(spacing: 12) {
            let totals = diffs.reduce((0, 0)) { ($0.0 + $1.lineCounts.additions, $0.1 + $1.lineCounts.deletions) }
            HStack {
                Text("\(diffs.count) 个文件").font(.subheadline.weight(.semibold))
                Spacer()
                Text("+\(totals.0)").foregroundStyle(Theme.opened)
                Text("−\(totals.1)").foregroundStyle(Theme.closed)
                Button(collapsed.isEmpty ? "全部折叠" : "全部展开") {
                    withAnimation { collapsed = collapsed.isEmpty ? Set(diffs.map(\.id)) : [] }
                }
                .font(.caption).buttonStyle(.borderless)
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 4)

            ForEach(diffs) { diff in
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.snappy) {
                            if collapsed.contains(diff.id) { collapsed.remove(diff.id) } else { collapsed.insert(diff.id) }
                        }
                    } label: {
                        DiffFileHeader(diff: diff, expanded: !collapsed.contains(diff.id)).padding(12)
                    }
                    .buttonStyle(.plain)
                    if !collapsed.contains(diff.id) {
                        Divider()
                        DiffBody(diff: diff, onComment: onComment.map { handler in { line in handler(diff, line) } })
                            .padding(.vertical, 4)
                    }
                }
                .solidCard(cornerRadius: 14)
            }
        }
    }
}
