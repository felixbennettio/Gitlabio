import SwiftUI
import Observation
import GitLabCore

@MainActor @Observable
final class MergeRequestModel {
    let projectID: Int
    let iid: Int
    var mr: MergeRequest?
    var approvals: Approvals?
    var discussions: [Discussion] = []
    var diffs: [FileDiff]?
    var commits: [Commit]?
    var pipelines: [Pipeline]?
    var error: Error?

    init(projectID: Int, iid: Int) {
        self.projectID = projectID
        self.iid = iid
    }

    func load(_ client: GitLabClient) async {
        do {
            async let mr = client.mergeRequest(projectID, iid: iid)
            async let approvals = client.approvals(projectID, iid: iid)
            async let discussions = client.discussions(projectID, kind: .mergeRequests, iid: iid)
            self.mr = try await mr
            self.approvals = try? await approvals
            self.discussions = (try? await discussions.items) ?? []
            error = nil
        } catch {
            self.error = error
        }
    }

    func reloadDiscussions(_ client: GitLabClient) async {
        var all: [Discussion] = []
        var page: Int? = 1
        while let current = page, current <= 5 {
            guard let result = try? await client.discussions(projectID, kind: .mergeRequests, iid: iid, page: current) else { break }
            all += result.items
            page = result.next
        }
        discussions = all
    }

    func loadDiffs(_ client: GitLabClient) async {
        guard diffs == nil else { return }
        var all: [FileDiff] = []
        var page: Int? = 1
        while let current = page, current <= 10 {
            guard let result = try? await client.mergeRequestDiffs(projectID, iid: iid, page: current) else { break }
            all += result.items
            page = result.next
        }
        diffs = all
    }

    func loadCommits(_ client: GitLabClient) async {
        guard commits == nil else { return }
        commits = (try? await client.mergeRequestCommits(projectID, iid: iid).items) ?? []
    }

    func loadPipelines(_ client: GitLabClient) async {
        guard pipelines == nil else { return }
        pipelines = (try? await client.mergeRequestPipelines(projectID, iid: iid).items) ?? []
    }

    var unresolvedThreads: Int { discussions.filter { $0.isResolvable && !$0.isResolved }.count }
}

struct MergeRequestView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case overview = "概览", discussion = "讨论", changes = "变更", commits = "提交", pipelines = "流水线"
        var id: String { rawValue }
    }

    @Environment(Session.self) private var session
    @State private var model: MergeRequestModel
    @State private var pane: Pane = .overview
    @State private var commenting = false
    @State private var inlineTarget: (FileDiff, DiffLine)?
    @State private var merging = false
    @State private var runner = ActionRunner()
    @State private var confirmClose = false

    init(projectID: Int, iid: Int) {
        _model = State(initialValue: MergeRequestModel(projectID: projectID, iid: iid))
        if let screen = LaunchOptions.screen, screen.hasPrefix("mr-") {
            _pane = State(initialValue: Pane.allCases.first { "mr-\($0)" == screen } ?? .overview)
        }
    }

    var body: some View {
        ScrollView {
            if let mr = model.mr {
                VStack(alignment: .leading, spacing: 18) {
                    header(mr)
                    Picker("内容", selection: $pane) {
                        ForEach(Pane.allCases) { pane in
                            Text(title(for: pane)).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    content(mr)
                }
                .padding(.horizontal)
                .padding(.bottom, 110)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            } else if let error = model.error {
                ErrorStateView(error: error) { await model.load(session.client) }
            } else {
                ProgressView().controlSize(.large).padding(.top, 120)
            }
        }
        .ambientBackground(Theme.purple)
        .navigationTitle(model.mr?.reference ?? "!\(model.iid)")
        .inlineTitle()
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            if let mr = model.mr, mr.state == "opened" { actionBar(mr) }
        }
        .sheet(isPresented: $commenting) {
            CommentComposer(title: "评论 \(model.mr?.reference ?? "")") { body in
                _ = try await session.client.startDiscussion(model.projectID, kind: .mergeRequests, iid: model.iid, body: body)
                await model.reloadDiscussions(session.client)
            }
        }
        .sheet(isPresented: Binding(get: { inlineTarget != nil }, set: { if !$0 { inlineTarget = nil } })) {
            if let (diff, line) = inlineTarget, let refs = model.mr?.diffRefs {
                CommentComposer(title: "行内评论", context: "\(diff.path):\(line.newLine ?? line.oldLine ?? 0)\n\(line.text)") { body in
                    let position = NotePosition(refs: refs, oldPath: diff.oldPath, newPath: diff.newPath,
                                                oldLine: line.kind == .addition ? nil : line.oldLine,
                                                newLine: line.kind == .deletion ? nil : line.newLine)
                    _ = try await session.client.startDiscussion(model.projectID, kind: .mergeRequests, iid: model.iid, body: body, position: position)
                    await model.reloadDiscussions(session.client)
                }
            }
        }
        .sheet(isPresented: $merging) {
            if let mr = model.mr {
                MergeSheet(mr: mr) { merged in model.mr = merged; await model.reloadDiscussions(session.client) }
            }
        }
        .confirmationDialog("关闭这个合并请求？", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("关闭合并请求", role: .destructive) { update(.close) }
        }
        .actionErrors(runner)
        .refreshable {
            await model.load(session.client)
            model.diffs = nil; model.commits = nil; model.pipelines = nil
            await loadPane()
        }
        .task { if model.mr == nil { await model.load(session.client) } }
        .task(id: pane) { await loadPane() }
    }

    private func loadPane() async {
        switch pane {
        case .changes: await model.loadDiffs(session.client)
        case .commits: await model.loadCommits(session.client)
        case .pipelines: await model.loadPipelines(session.client)
        case .discussion: await model.reloadDiscussions(session.client)
        case .overview: break
        }
    }

    private func title(for pane: Pane) -> String {
        switch pane {
        case .discussion:
            let count = model.discussions.filter { !$0.isSystem }.count
            return count > 0 ? "讨论 \(count)" : "讨论"
        case .changes: return model.mr?.changesCount.map { "变更 \($0)" } ?? "变更"
        default: return pane.rawValue
        }
    }

    // MARK: Header

    private func header(_ mr: MergeRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StateBadge(state: mr.state, draft: mr.isDraft)
                Text(mr.references?.full ?? mr.reference).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            Text(mr.title).font(.title2.weight(.bold)).textSelection(.enabled)
            HStack(spacing: 8) {
                Avatar(user: mr.author, instance: session.instance, size: 24)
                Text(mr.author?.name ?? "").font(.subheadline.weight(.semibold))
                if let date = mr.createdAt { Text("创建于 \(date.relative)").font(.subheadline).foregroundStyle(.secondary) }
            }
            HStack(spacing: 6) {
                BranchTag(name: mr.sourceBranch)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                BranchTag(name: mr.targetBranch)
                Spacer()
                Button { Clipboard.copy(mr.sourceBranch); Haptics.success() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).font(.caption).accessibilityLabel("复制源分支名")
            }
        }
        .padding(.top, 6)
    }

    // MARK: Panes

    @ViewBuilder
    private func content(_ mr: MergeRequest) -> some View {
        switch pane {
        case .overview: overview(mr)
        case .discussion:
            VStack(spacing: 14) {
                if model.unresolvedThreads > 0 {
                    Label("\(model.unresolvedThreads) 个未解决的讨论", systemImage: "exclamationmark.bubble")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DiscussionTimeline(discussions: model.discussions, kind: .mergeRequests, projectID: model.projectID, iid: model.iid,
                                   base: projectBase(mr)) { await model.reloadDiscussions(session.client) }
                Button { commenting = true } label: { Label("写评论", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                    .buttonStyle(SoftButtonStyle())
            }
        case .changes:
            if let diffs = model.diffs {
                if diffs.isEmpty { EmptyStateView(title: "没有变更", symbol: "doc") }
                else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("长按代码行可以发表行内评论", systemImage: "hand.tap").font(.caption).foregroundStyle(.secondary)
                        DiffList(diffs: diffs, onComment: mr.diffRefs == nil ? nil : { diff, line in inlineTarget = (diff, line) })
                    }
                }
            } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
        case .commits:
            if let commits = model.commits {
                VStack(spacing: 0) {
                    ForEach(commits) { commit in
                        NavigationLink(value: Route.commit(projectID: model.projectID, sha: commit.id)) { CommitRow(commit: commit).padding(12) }
                            .buttonStyle(.plain)
                        if commit.id != commits.last?.id { Divider().padding(.leading, 58) }
                    }
                }
                .glassCard()
            } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
        case .pipelines:
            if let pipelines = model.pipelines {
                if pipelines.isEmpty { EmptyStateView(title: "没有流水线", symbol: "point.3.connected.trianglepath.dotted") }
                VStack(spacing: 10) {
                    ForEach(pipelines) { pipeline in
                        NavigationLink(value: Route.pipeline(projectID: model.projectID, id: pipeline.id)) {
                            PipelineRow(pipeline: pipeline).padding(14).glassCard(interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
        }
    }

    private func projectBase(_ mr: MergeRequest) -> URL? {
        guard let web = mr.webUrl, let range = web.range(of: "/-/merge_requests") else { return nil }
        return URL(string: String(web[..<range.lowerBound]) + "/")
    }

    private func overview(_ mr: MergeRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Merge readiness
            VStack(alignment: .leading, spacing: 14) {
                if let pipeline = mr.headPipeline {
                    NavigationLink(value: Route.pipeline(projectID: model.projectID, id: pipeline.id)) {
                        HStack(spacing: 12) {
                            StatusIcon(status: pipeline.status, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("流水线 #\(String(pipeline.id)) \(pipeline.status.title)").font(.subheadline.weight(.semibold))
                                if let date = pipeline.createdAt { Text(date.relative).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                if let approvals = model.approvals {
                    HStack(spacing: 12) {
                        Image(systemName: approvals.approved == true ? "checkmark.seal.fill" : "seal")
                            .font(.title3).foregroundStyle(approvals.approved == true ? Theme.opened : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            let given = approvals.approvedBy?.count ?? 0
                            let required = approvals.approvalsRequired ?? 0
                            Text(required > 0 ? "已批准 \(given)/\(required)" : (given > 0 ? "已获 \(given) 个批准" : "尚无批准"))
                                .font(.subheadline.weight(.semibold))
                            if let left = approvals.approvalsLeft, left > 0 { Text("还需要 \(left) 个批准").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        AvatarStack(users: approvals.approvedBy?.map(\.user) ?? [], instance: session.instance, size: 24)
                    }
                    Divider()
                }
                HStack(spacing: 12) {
                    Image(systemName: mr.isMergeable ? "checkmark.circle.fill" : (mr.state == "merged" ? "arrow.triangle.merge" : "exclamationmark.circle.fill"))
                        .font(.title3)
                        .foregroundStyle(mr.isMergeable ? Theme.opened : (mr.state == "merged" ? Theme.merged : .orange))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mr.state == "merged" ? "已合并" : (mr.isMergeable ? "可以合并" : "暂不能合并")).font(.subheadline.weight(.semibold))
                        if mr.state == "opened", let blocker = mr.mergeBlocker { Text(blocker).font(.caption).foregroundStyle(.secondary) }
                        if let merged = mr.mergedAt { Text("合并于 \(merged.relative)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
                if let tasks = mr.taskCompletionStatus, tasks.count > 0 {
                    Divider()
                    HStack {
                        Image(systemName: "checklist").foregroundStyle(Theme.orange)
                        Text("任务 \(tasks.completedCount)/\(tasks.count)").font(.subheadline.weight(.semibold))
                        ProgressView(value: Double(tasks.completedCount), total: Double(tasks.count)).tint(Theme.opened)
                    }
                }
            }
            .padding(16)
            .glassCard()

            if let description = mr.description, !description.isEmpty {
                MarkdownView(text: description, base: projectBase(mr))
                    .padding(16)
                    .glassCard()
            }

            VStack(alignment: .leading, spacing: 14) {
                people("指派给", mr.assignees ?? [])
                people("审查者", mr.reviewers ?? [])
                if let labels = mr.labels, !labels.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("标签").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        LabelRow(labels: labels)
                    }
                }
                if let milestone = mr.milestone {
                    LabeledContent("里程碑") { Label(milestone.title, systemImage: "flag") }.font(.subheadline)
                }
            }
            .padding(16)
            .glassCard()
        }
    }

    private func people(_ title: String, _ users: [User]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if users.isEmpty {
                Text("无").font(.subheadline).foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(users) { user in
                        HStack(spacing: 6) {
                            Avatar(user: user, instance: session.instance, size: 22)
                            Text(user.name).font(.subheadline)
                        }
                        .padding(.trailing, 4)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func actionBar(_ mr: MergeRequest) -> some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                if let approvals = model.approvals, approvals.userCanApprove == true || approvals.userHasApproved == true {
                    let approved = approvals.userHasApproved == true
                    Button {
                        let client = session.client, id = model.projectID, iid = model.iid
                        runner.run {
                            try await client.approve(id, iid: iid, approve: !approved)
                            model.approvals = try? await client.approvals(id, iid: iid)
                        }
                    } label: {
                        Label(approved ? "撤销批准" : "批准", systemImage: approved ? "hand.thumbsdown" : "hand.thumbsup.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("approve-button")
                }
                Button { merging = true } label: {
                    Label("合并", systemImage: "arrow.triangle.merge").frame(maxWidth: .infinity)
                }
                .buttonStyle(BrandButtonStyle(tint: Theme.opened))
                .disabled(!session.account.canWrite)
                .accessibilityIdentifier("merge-button")
            }
            .disabled(runner.isRunning)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let mr = model.mr {
                    Button { commenting = true } label: { Label("评论", systemImage: "text.bubble") }
                    if mr.state == "opened" {
                        Button { update(WorkItemUpdate(title: mr.isDraft ? mr.title.replacingOccurrences(of: "Draft: ", with: "") : "Draft: \(mr.title)")) } label: {
                            Label(mr.isDraft ? "标记为就绪" : "标记为草稿", systemImage: "pencil.circle")
                        }
                        Button {
                            let client = session.client, id = model.projectID, iid = model.iid
                            runner.run { try await client.rebase(id, iid: iid) }
                        } label: { Label("变基", systemImage: "arrow.up.and.down.text.horizontal") }
                        Button(role: .destructive) { confirmClose = true } label: { Label("关闭", systemImage: "xmark.circle") }
                    } else if mr.state == "closed" {
                        Button { update(.reopen) } label: { Label("重新打开", systemImage: "arrow.uturn.backward.circle") }
                    }
                    Divider()
                    Button { Clipboard.copy(mr.sourceBranch) } label: { Label("复制源分支", systemImage: "arrow.triangle.branch") }
                    if let url = mr.webUrl.flatMap(URL.init(string:)) {
                        ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
                        Link(destination: url) { Label("在浏览器中打开", systemImage: "safari") }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }

    private func update(_ update: WorkItemUpdate) {
        let client = session.client, id = model.projectID, iid = model.iid
        runner.run { model.mr = try await client.updateMergeRequest(id, iid: iid, update) }
    }
}

struct MergeSheet: View {
    let mr: MergeRequest
    var onMerged: (MergeRequest) async -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var squash = false
    @State private var removeSource = true
    @State private var whenPipelineSucceeds = false
    @State private var message = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        BranchTag(name: mr.sourceBranch)
                        Image(systemName: "arrow.right")
                        BranchTag(name: mr.targetBranch)
                    }
                    if let blocker = mr.mergeBlocker {
                        Label(blocker, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.subheadline)
                    }
                }
                Section("选项") {
                    Toggle("压缩为一个提交", isOn: $squash)
                    Toggle("合并后删除源分支", isOn: $removeSource)
                    if let pipeline = mr.headPipeline, pipeline.status.isActive {
                        Toggle("流水线成功后自动合并", isOn: $whenPipelineSucceeds)
                    }
                }
                Section("合并提交说明（可选）") {
                    TextField("默认使用 GitLab 生成的说明", text: $message, axis: .vertical).lineLimit(2...6)
                }
                if let error { Section { InlineError(message: error).listRowInsets(EdgeInsets()) } }
            }
            .navigationTitle("合并 \(mr.reference)")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        busy = true
                        error = nil
                        let options = MergeOptions(squash: squash, removeSourceBranch: removeSource, message: message.isEmpty ? nil : message,
                                                   whenPipelineSucceeds: whenPipelineSucceeds ? true : nil, sha: mr.sha)
                        Task {
                            defer { busy = false }
                            do {
                                let merged = try await session.client.merge(mr.projectId, iid: mr.iid, options: options)
                                Haptics.success()
                                await onMerged(merged)
                                dismiss()
                            } catch { self.error = error.localizedDescription; Haptics.warning() }
                        }
                    } label: { if busy { ProgressView() } else { Text(whenPipelineSucceeds ? "设置自动合并" : "合并").bold() } }
                    .disabled(busy)
                }
            }
            .onAppear { squash = mr.squash ?? false; removeSource = mr.forceRemoveSourceBranch ?? true }
        }
        .presentationDetents([.medium, .large])
    }
}
