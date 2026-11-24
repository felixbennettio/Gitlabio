import SwiftUI
import GitLabCore

/// Timeline of notes: compact system events, comments and resolvable threads.
struct DiscussionTimeline: View {
    let discussions: [Discussion]
    let kind: WorkItemKind
    let projectID: Int
    let iid: Int
    var base: URL?
    var onChange: () async -> Void = {}

    @Environment(Session.self) private var session
    @State private var replyingTo: Discussion?
    @State private var runner = ActionRunner()

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if discussions.isEmpty {
                Text("还没有评论").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            ForEach(discussions) { discussion in
                if discussion.isSystem {
                    ForEach(discussion.notes) { note in SystemNoteRow(note: note) }
                } else {
                    thread(discussion)
                }
            }
        }
        .sheet(item: $replyingTo) { discussion in
            CommentComposer(title: "回复") { body in
                _ = try await session.client.reply(projectID, kind: kind, iid: iid, discussion: discussion.id, body: body)
                await onChange()
            }
        }
        .actionErrors(runner)
    }

    private func thread(_ discussion: Discussion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let position = discussion.position {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                    Text("\(position.newPath ?? position.oldPath ?? "")\(position.newLine.map { ":\($0)" } ?? position.oldLine.map { ":\($0)" } ?? "")")
                        .lineLimit(1).truncationMode(.head)
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12)
            }
            ForEach(Array(discussion.notes.enumerated()), id: \.element.id) { index, note in
                NoteView(note: note, base: base)
                    .padding(.leading, index == 0 ? 0 : 22)
                    .padding(14)
                if index < discussion.notes.count - 1 { Divider().padding(.leading, index == 0 ? 14 : 36) }
            }
            HStack(spacing: 12) {
                Button { replyingTo = discussion } label: { Label("回复", systemImage: "arrowshape.turn.up.left") }
                if kind == .mergeRequests && discussion.isResolvable {
                    Button {
                        let resolved = !discussion.isResolved, client = session.client, id = projectID, iid = iid
                        runner.run {
                            _ = try await client.resolve(id, iid: iid, discussion: discussion.id, resolved: resolved)
                            await onChange()
                        }
                    } label: {
                        Label(discussion.isResolved ? "重新打开" : "标记为已解决",
                              systemImage: discussion.isResolved ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    }
                    .tint(discussion.isResolved ? .secondary : Theme.opened)
                }
                Spacer()
                if discussion.isResolved {
                    Label("已解决", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.opened)
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
        .glassCard(cornerRadius: 18, tint: discussion.isResolved ? Theme.opened : nil)
        .opacity(discussion.isResolved ? 0.8 : 1)
    }
}

struct NoteView: View {
    let note: Note
    var base: URL?
    @Environment(Session.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Avatar(user: note.author, instance: session.instance, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.author?.name ?? "未知").font(.subheadline.weight(.semibold))
                    if let date = note.createdAt { Text(date.relative).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                if note.author?.id == session.account.userID {
                    Text("你").font(.caption2.weight(.bold)).foregroundStyle(Theme.orange)
                }
            }
            MarkdownView(text: note.body, base: base, compact: true)
        }
    }
}

struct SystemNoteRow: View {
    let note: Note
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary).frame(width: 18)
            (Text(note.author?.name ?? "").bold() + Text(" ") + Text(note.body))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 4)
            if let date = note.createdAt { Text(date.relative).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 6)
    }

    private var symbol: String {
        let body = note.body.lowercased()
        if body.contains("commit") { return "smallcircle.filled.circle" }
        if body.contains("approved") { return "checkmark.seal" }
        if body.contains("merged") { return "arrow.triangle.merge" }
        if body.contains("label") { return "tag" }
        if body.contains("review") { return "eye" }
        if body.contains("assign") { return "person" }
        if body.contains("mentioned") { return "link" }
        return "info.circle"
    }
}

/// Sheet for writing a comment, reply or inline review note.
struct CommentComposer: View {
    let title: String
    var context: String?
    var send: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var previewing = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let context {
                    Text(context).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading).solidCard(cornerRadius: 10)
                }
                Picker("模式", selection: $previewing) {
                    Text("编写").tag(false)
                    Text("预览").tag(true)
                }
                .pickerStyle(.segmented)
                if previewing {
                    ScrollView { MarkdownView(text: text.isEmpty ? "_没有内容_" : text) }
                } else {
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .solidCard(cornerRadius: 12)
                        .accessibilityIdentifier("comment-editor")
                }
                if let error { InlineError(message: error) }
            }
            .padding()
            .navigationTitle(title)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        busy = true
                        error = nil
                        Task {
                            defer { busy = false }
                            do { try await send(text); Haptics.success(); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: { if busy { ProgressView() } else { Text("发送").bold() } }
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("send-comment")
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(!text.isEmpty)
    }
}
