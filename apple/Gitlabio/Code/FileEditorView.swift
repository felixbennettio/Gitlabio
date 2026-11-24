import SwiftUI
import GitLabCore

struct FileEditorView: View {
    let project: Project
    let ref: String
    let path: String
    let original: String
    let lastCommitId: String

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var showingBasket = false
    @State private var confirmDiscard = false

    init(project: Project, ref: String, path: String, original: String, initial: String, lastCommitId: String) {
        self.project = project
        self.ref = ref
        self.path = path
        self.original = original
        self.lastCommitId = lastCommitId
        self._text = State(initialValue: initial)
    }

    var body: some View {
        let basket = session.basket(for: project)
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .technicalInput()
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("file-editor")
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 10) {
                        let counts = LineDiff.counts(old: original, new: text)
                        Label("\(text.split(separator: "\n", omittingEmptySubsequences: false).count) 行", systemImage: "text.alignleft")
                        if counts.additions + counts.deletions > 0 {
                            Text("+\(counts.additions)").foregroundStyle(Theme.opened)
                            Text("−\(counts.deletions)").foregroundStyle(Theme.closed)
                        }
                        Spacer()
                        Text(ref).font(.caption.monospaced())
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassCapsule()
                    .padding(.horizontal).padding(.bottom, 6)
                }
                .navigationTitle((path as NSString).lastPathComponent)
                .inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { if text == original || text == basket.change(for: path)?.text { dismiss() } else { confirmDiscard = true } }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Menu {
                            Button { stage(basket); dismiss() } label: { Label("加入变更篮，稍后一起提交", systemImage: "tray.and.arrow.down") }
                            Button { stage(basket); showingBasket = true } label: { Label("现在提交…", systemImage: "checkmark.circle") }
                        } label: {
                            Text("完成").bold()
                        } primaryAction: {
                            stage(basket)
                            showingBasket = true
                        }
                        .disabled(text == original && basket.change(for: path) == nil)
                        .accessibilityIdentifier("editor-done")
                    }
                }
                .confirmationDialog("放弃未暂存的修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("放弃修改", role: .destructive) { dismiss() }
                    Button("加入变更篮") { stage(basket); dismiss() }
                }
                .sheet(isPresented: $showingBasket, onDismiss: { if basket.change(for: path) == nil { dismiss() } }) {
                    ChangeBasketView(basket: basket)
                }
        }
        .interactiveDismissDisabled(text != original)
    }

    private func stage(_ basket: ChangeBasket) {
        basket.stage(.init(path: path, kind: .update, text: text, original: original, baseRef: ref, lastCommitId: lastCommitId))
    }
}

extension LineDiff {
    static func counts(old: String, new: String) -> (additions: Int, deletions: Int) {
        guard old != new else { return (0, 0) }
        let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
        var remaining = Dictionary(a.map { ($0, 1) }, uniquingKeysWith: +)
        var additions = 0
        for line in b {
            if let count = remaining[line], count > 0 { remaining[line] = count - 1 } else { additions += 1 }
        }
        return (additions, remaining.values.reduce(0, +))
    }
}

struct NewFileView: View {
    let project: Project
    let ref: String
    let directory: String

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("文件名，例如 docs/notes.md", text: $name).technicalInput()
                } header: {
                    Text(directory.isEmpty ? "位置：仓库根目录" : "位置：\(directory)/")
                }
                Section("内容") {
                    TextEditor(text: $text)
                        .font(.system(.callout, design: .monospaced))
                        .technicalInput()
                        .frame(minHeight: 260)
                }
            }
            .navigationTitle("新建文件")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入变更篮") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let path = directory.isEmpty ? trimmed : directory + "/" + trimmed
                        session.basket(for: project).stage(.init(path: path, kind: .create, text: text, original: nil, baseRef: ref))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.contains(".."))
                }
            }
        }
    }
}

/// Review staged changes and commit them in one go, optionally on a new branch with an MR.
struct ChangeBasketView: View {
    @Bindable var basket: ChangeBasket
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var newBranch = false
    @State private var branchName = ""
    @State private var openMR = true
    @State private var busy = false
    @State private var error: String?
    @State private var committed: Commit?
    @State private var createdMR: MergeRequest?
    @State private var preview: ChangeBasket.Change?

    private var base: String { basket.changes.first?.baseRef ?? basket.branch }
    private var target: String { newBranch ? branchName.trimmingCharacters(in: .whitespaces) : base }

    var body: some View {
        NavigationStack {
            Form {
                if let committed {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("已提交到 \(target)", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Theme.opened)
                            Text(committed.title).font(.subheadline)
                            Text(committed.shortId).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if let createdMR {
                                Label("已创建合并请求 \(createdMR.reference)", systemImage: "arrow.triangle.pull").foregroundStyle(Theme.purple)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section {
                        if basket.isEmpty {
                            Text("变更篮是空的。编辑或新建文件后，会暂存在这里一起提交。").foregroundStyle(.secondary)
                        }
                        ForEach(basket.changes) { change in
                            Button { preview = change } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: change.symbol).foregroundStyle(Theme.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text((change.path as NSString).lastPathComponent).foregroundStyle(.primary)
                                        Text("\(change.title) · \(change.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    let counts = change.previewDiff.lineCounts
                                    Text("+\(counts.additions) −\(counts.deletions)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                            .swipeActions { Button("撤销", role: .destructive) { basket.discard(change.path) } }
                        }
                    } header: {
                        Text("\(basket.count) 项更改 · 基于 \(base)")
                    }

                    if !basket.isEmpty {
                        Section("提交说明") {
                            TextField("简要描述这次更改", text: $message, axis: .vertical)
                                .lineLimit(2...6)
                                .accessibilityIdentifier("commit-message")
                        }
                        Section {
                            Toggle("提交到新分支", isOn: $newBranch.animation())
                            if newBranch {
                                TextField("新分支名", text: $branchName).technicalInput()
                                Toggle("同时创建合并请求", isOn: $openMR)
                            }
                        } footer: {
                            Text(newBranch ? "将从 \(base) 创建分支并提交。" : "直接提交到 \(base)。受保护分支可能拒绝直接推送。")
                        }
                        if let error { Section { InlineError(message: error).listRowInsets(EdgeInsets()) } }
                    }
                }
            }
            .navigationTitle(committed == nil ? "提交更改" : "完成")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(committed == nil ? "关闭" : "完成") { dismiss() } }
                if committed == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: commit) { if busy { ProgressView() } else { Text("提交").bold() } }
                            .disabled(busy || basket.isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty || (newBranch && target.isEmpty))
                            .accessibilityIdentifier("commit-button")
                    }
                }
            }
            .sheet(item: $preview) { change in
                NavigationStack {
                    ScrollView { DiffList(diffs: [change.previewDiff]).padding() }
                        .navigationTitle((change.path as NSString).lastPathComponent)
                        .inlineTitle()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { preview = nil } } }
                }
            }
            .onAppear {
                if message.isEmpty, basket.count == 1, let change = basket.changes.first {
                    let file = (change.path as NSString).lastPathComponent
                    switch change.kind {
                    case .create: message = "Add \(file)"
                    case .update: message = "Update \(file)"
                    case .delete: message = "Delete \(file)"
                    case .rename: message = "Rename \(file)"
                    }
                }
                if branchName.isEmpty { branchName = "\(session.account.username)/edit-\(Int(Date().timeIntervalSince1970) % 100000)" }
            }
        }
    }

    private func commit() {
        error = nil
        busy = true
        let message = message, target = target, base = base, openMR = newBranch && openMR, project = basket.project
        Task {
            defer { busy = false }
            do {
                let commit = try await basket.commit(using: session.client, message: message, targetBranch: target)
                committed = commit
                if openMR {
                    createdMR = try? await session.client.createMergeRequest(project.id, NewMergeRequest(source: target, target: base, title: commit.title))
                }
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}
