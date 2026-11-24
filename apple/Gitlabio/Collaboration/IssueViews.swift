import SwiftUI
import Observation
import GitLabCore

struct IssuesView: View {
    let project: Project
    @Environment(Session.self) private var session
    @State private var state: WorkItemState = .opened
    @State private var filter: WorkItemFilter = .all
    @State private var search = ""
    @State private var label: String?
    @State private var labels: [ProjectLabel] = []
    @State private var loader: PagedLoader<Issue>?
    @State private var creating = false

    var body: some View {
        let palette = Dictionary(labels.map { ($0.name, $0.color) }, uniquingKeysWith: { a, _ in a })
        List {
            Section {
                Picker("状态", selection: $state) {
                    Text("打开").tag(WorkItemState.opened)
                    Text("已关闭").tag(WorkItemState.closed)
                    Text("全部").tag(WorkItemState.all)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if let label {
                    HStack {
                        LabelChip(name: label, color: palette[label])
                        Spacer()
                        Button("清除") { self.label = nil }.font(.caption)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            if let loader {
                Section {
                    ForEach(loader.items) { issue in
                        NavigationLink(value: Route.issue(projectID: issue.projectId, iid: issue.iid)) { IssueRow(issue: issue) }
                            .task { await loader.loadMoreIfNeeded(issue) }
                    }
                    PagingFooter(loader: loader)
                } header: {
                    if let total = loader.total { Text("\(total) 个 Issue") }
                }
            }
        }
        .groupedList()
        .overlay { if let loader { PagedStateOverlay(loader: loader, emptyTitle: "没有 Issue", emptySymbol: "smallcircle.filled.circle") } }
        .searchable(text: $search, prompt: "搜索 Issue")
        .navigationTitle("Issue")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(WorkItemFilter.allCases.filter { $0 != .reviewRequested }) { Text($0.title).tag($0) }
                    }
                    if !labels.isEmpty {
                        Menu("按标签") {
                            ForEach(labels) { item in Button(item.name) { label = item.name } }
                        }
                    }
                } label: { Label("筛选", systemImage: "line.3.horizontal.decrease") }
                Button { creating = true } label: { Label("新建", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $creating) { IssueEditorView(project: project, issue: nil) { _ in await loader?.refresh() } }
        .refreshable { await loader?.refresh() }
        .task { if labels.isEmpty { labels = (try? await session.client.labels(project.id).items) ?? [] } }
        .task(id: "\(state.rawValue)|\(filter.rawValue)|\(search)|\(label ?? "")") {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let client = session.client, id = project.id, state = state, filter = filter, term = search, labels = label.map { [$0] } ?? []
            let fetch: (Int) async throws -> Page<Issue> = {
                try await client.issues(project: id, state: state, filter: filter, search: term, labels: labels, page: $0)
            }
            if let loader { loader.replaceFetch(fetch) } else { loader = PagedLoader(fetch) }
            await loader?.loadFirst()
        }
    }
}

@MainActor @Observable
final class IssueModel {
    let projectID: Int
    let iid: Int
    var issue: Issue?
    var project: Project?
    var discussions: [Discussion] = []
    var labels: [ProjectLabel] = []
    var error: Error?

    init(projectID: Int, iid: Int) {
        self.projectID = projectID
        self.iid = iid
    }

    func load(_ client: GitLabClient) async {
        do {
            async let issue = client.issue(projectID, iid: iid)
            async let discussions = client.discussions(projectID, kind: .issues, iid: iid)
            async let labels = client.labels(projectID)
            async let project = client.project(projectID)
            self.issue = try await issue
            self.discussions = (try? await discussions.items) ?? []
            self.labels = (try? await labels.items) ?? []
            self.project = try? await project
            error = nil
        } catch { self.error = error }
    }
}

struct IssueView: View {
    @Environment(Session.self) private var session
    @State private var model: IssueModel
    @State private var commenting = false
    @State private var editing = false
    @State private var runner = ActionRunner()

    init(projectID: Int, iid: Int) { _model = State(initialValue: IssueModel(projectID: projectID, iid: iid)) }

    var body: some View {
        ScrollView {
            if let issue = model.issue {
                let palette = Dictionary(model.labels.map { ($0.name, $0.color) }, uniquingKeysWith: { a, _ in a })
                let base = model.project?.webUrl.flatMap { URL(string: $0 + "/") }
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            StateBadge(state: issue.state)
                            if issue.confidential == true {
                                Label("机密", systemImage: "eye.slash.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            }
                            Text(issue.references?.full ?? issue.reference).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(issue.title).font(.title2.weight(.bold)).textSelection(.enabled)
                        HStack(spacing: 8) {
                            Avatar(user: issue.author, instance: session.instance, size: 24)
                            Text(issue.author?.name ?? "").font(.subheadline.weight(.semibold))
                            if let date = issue.createdAt { Text("创建于 \(date.relative)").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                    .padding(.top, 6)

                    if let description = issue.description, !description.isEmpty {
                        MarkdownView(text: description, base: base).padding(16).glassCard()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        infoRow("指派给") {
                            if let assignees = issue.assignees, !assignees.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(assignees) { user in
                                        HStack(spacing: 6) { Avatar(user: user, instance: session.instance, size: 22); Text(user.name).font(.subheadline) }
                                    }
                                }
                            } else { Text("无").font(.subheadline).foregroundStyle(.tertiary) }
                        }
                        if let labels = issue.labels, !labels.isEmpty {
                            infoRow("标签") { LabelRow(labels: labels, palette: palette) }
                        }
                        if let milestone = issue.milestone { infoRow("里程碑") { Label(milestone.title, systemImage: "flag").font(.subheadline) } }
                        if let due = issue.dueDate { infoRow("截止日期") { Label(due, systemImage: "calendar").font(.subheadline) } }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassCard()

                    SectionTitle(title: "讨论", symbol: "bubble.left.and.bubble.right", count: model.discussions.filter { !$0.isSystem }.count)
                    DiscussionTimeline(discussions: model.discussions, kind: .issues, projectID: model.projectID, iid: model.iid, base: base) {
                        await model.load(session.client)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            } else if let error = model.error {
                ErrorStateView(error: error) { await model.load(session.client) }
            } else {
                ProgressView().controlSize(.large).padding(.top, 120)
            }
        }
        .ambientBackground(Theme.mint)
        .navigationTitle(model.issue?.reference ?? "#\(model.iid)")
        .inlineTitle()
        .safeAreaInset(edge: .bottom) {
            if let issue = model.issue {
                GlassGroup {
                    HStack(spacing: 10) {
                        Button { commenting = true } label: { Label("评论", systemImage: "text.bubble.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(BrandButtonStyle())
                        Button {
                            let client = session.client, id = model.projectID, iid = model.iid
                            let update: WorkItemUpdate = issue.state == "closed" ? .reopen : .close
                            runner.run { model.issue = try await client.updateIssue(id, iid: iid, update) }
                        } label: {
                            Label(issue.state == "closed" ? "重新打开" : "关闭", systemImage: issue.state == "closed" ? "arrow.uturn.backward.circle" : "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                    .disabled(runner.isRunning || !session.account.canWrite)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = true } label: { Label("编辑", systemImage: "pencil") }
                    if let url = model.issue?.webUrl.flatMap(URL.init(string:)) {
                        ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
                        Link(destination: url) { Label("在浏览器中打开", systemImage: "safari") }
                        Button { Clipboard.copy(url.absoluteString) } label: { Label("复制链接", systemImage: "link") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $commenting) {
            CommentComposer(title: "评论 \(model.issue?.reference ?? "")") { body in
                _ = try await session.client.startDiscussion(model.projectID, kind: .issues, iid: model.iid, body: body)
                await model.load(session.client)
            }
        }
        .sheet(isPresented: $editing) {
            if let project = model.project, let issue = model.issue {
                IssueEditorView(project: project, issue: issue) { updated in model.issue = updated }
            }
        }
        .actionErrors(runner)
        .refreshable { await model.load(session.client) }
        .task { if model.issue == nil { await model.load(session.client) } }
    }

    private func infoRow(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Create or edit an issue: title, description, labels, assignees, confidentiality.
struct IssueEditorView: View {
    let project: Project
    let issue: Issue?
    var onSave: (Issue) async -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var selectedLabels: Set<String> = []
    @State private var assignees: Set<Int> = []
    @State private var confidential = false
    @State private var labels: [ProjectLabel] = []
    @State private var members: [Member] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $title).font(.headline)
                    TextField("描述（支持 Markdown）", text: $description, axis: .vertical).lineLimit(5...14)
                }
                if !labels.isEmpty {
                    Section("标签") {
                        FlowLayout(spacing: 6) {
                            ForEach(labels) { label in
                                Button {
                                    if selectedLabels.contains(label.name) { selectedLabels.remove(label.name) } else { selectedLabels.insert(label.name) }
                                } label: {
                                    LabelChip(name: label.name, color: label.color)
                                        .opacity(selectedLabels.contains(label.name) ? 1 : 0.4)
                                        .overlay(alignment: .topTrailing) {
                                            if selectedLabels.contains(label.name) {
                                                Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(Theme.orange).offset(x: 4, y: -4)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !members.isEmpty {
                    Section("指派给") {
                        ForEach(members) { member in
                            Button {
                                if assignees.contains(member.id) { assignees.remove(member.id) } else { assignees.insert(member.id) }
                            } label: {
                                HStack {
                                    Avatar(user: member.user, instance: session.instance, size: 26)
                                    Text(member.name).foregroundStyle(.primary)
                                    Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if assignees.contains(member.id) { Image(systemName: "checkmark").foregroundStyle(Theme.orange) }
                                }
                            }
                        }
                    }
                }
                Section { Toggle("机密 Issue", isOn: $confidential) } footer: { Text("只有项目成员能看到机密 Issue。") }
                if let error { Section { InlineError(message: error).listRowInsets(EdgeInsets()) } }
            }
            .navigationTitle(issue == nil ? "新建 Issue" : "编辑 Issue")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { if busy { ProgressView() } else { Text(issue == nil ? "创建" : "保存").bold() } }
                        .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                if let issue {
                    title = issue.title
                    description = issue.description ?? ""
                    selectedLabels = Set(issue.labels ?? [])
                    assignees = Set((issue.assignees ?? []).map(\.id))
                    confidential = issue.confidential ?? false
                }
                labels = (try? await session.client.labels(project.id).items) ?? []
                members = (try? await session.client.members(project.id).items) ?? []
            }
        }
    }

    private func save() {
        busy = true
        error = nil
        let fields = WorkItemUpdate(title: title, description: description, labels: Array(selectedLabels).sorted(),
                                    assigneeIds: Array(assignees), confidential: confidential)
        let client = session.client, id = project.id, existing = issue
        Task {
            defer { busy = false }
            do {
                let saved = if let existing { try await client.updateIssue(id, iid: existing.iid, fields) } else { try await client.createIssue(id, fields) }
                Haptics.success()
                await onSave(saved)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
