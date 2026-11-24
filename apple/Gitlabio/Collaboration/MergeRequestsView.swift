import SwiftUI
import GitLabCore

struct MergeRequestsView: View {
    let project: Project
    @Environment(Session.self) private var session
    @State private var state: WorkItemState = .opened
    @State private var filter: WorkItemFilter = .all
    @State private var search = ""
    @State private var loader: PagedLoader<MergeRequest>?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $state) {
                    Text("打开").tag(WorkItemState.opened)
                    Text("已合并").tag(WorkItemState.merged)
                    Text("已关闭").tag(WorkItemState.closed)
                    Text("全部").tag(WorkItemState.all)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if let loader {
                Section {
                    ForEach(loader.items) { mr in
                        NavigationLink(value: Route.mergeRequest(projectID: mr.projectId, iid: mr.iid)) { MergeRequestRow(mr: mr) }
                            .task { await loader.loadMoreIfNeeded(mr) }
                    }
                    PagingFooter(loader: loader)
                } header: {
                    if let total = loader.total { Text("\(total) 个合并请求") }
                }
            }
        }
        .groupedList()
        .overlay { if let loader { PagedStateOverlay(loader: loader, emptyTitle: "没有合并请求", emptySymbol: "arrow.triangle.pull") } }
        .searchable(text: $search, prompt: "搜索合并请求")
        .navigationTitle("合并请求")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(WorkItemFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Label("筛选", systemImage: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") }
                Button { creating = true } label: { Label("新建", systemImage: "plus") }
                    .disabled(!session.account.canWrite)
            }
        }
        .sheet(isPresented: $creating) { CreateMergeRequestView(project: project) }
        .refreshable { await loader?.refresh() }
        .task(id: "\(state.rawValue)|\(filter.rawValue)|\(search)") {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let client = session.client, id = project.id, state = state, filter = filter, term = search, me = session.account.username
            let fetch: (Int) async throws -> Page<MergeRequest> = {
                try await client.mergeRequests(project: id, state: state, filter: filter, search: term, username: me, page: $0)
            }
            if let loader { loader.replaceFetch(fetch) } else { loader = PagedLoader(fetch) }
            await loader?.loadFirst()
        }
    }
}

struct CreateMergeRequestView: View {
    let project: Project
    var source: String = ""
    var target: String = ""

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var sourceBranch = ""
    @State private var targetBranch = ""
    @State private var title = ""
    @State private var description = ""
    @State private var removeSource = true
    @State private var squash = false
    @State private var draft = false
    @State private var pickingSource = false
    @State private var pickingTarget = false
    @State private var busy = false
    @State private var error: String?
    @State private var created: MergeRequest?

    var body: some View {
        NavigationStack {
            Form {
                Section("分支") {
                    PickerRow(title: "源分支", value: sourceBranch.isEmpty ? "选择" : sourceBranch) { pickingSource = true }
                    PickerRow(title: "目标分支", value: targetBranch) { pickingTarget = true }
                }
                Section("内容") {
                    TextField("标题", text: $title)
                    Toggle("标记为草稿", isOn: $draft)
                    TextField("描述（支持 Markdown）", text: $description, axis: .vertical).lineLimit(4...12)
                }
                Section("合并选项") {
                    Toggle("合并后删除源分支", isOn: $removeSource)
                    Toggle("合并时压缩提交", isOn: $squash)
                }
                if let error { Section { InlineError(message: error).listRowInsets(EdgeInsets()) } }
                if let created {
                    Section {
                        NavigationLink(value: Route.mergeRequest(projectID: created.projectId, iid: created.iid)) {
                            Label("已创建 \(created.reference)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.opened)
                        }
                    }
                }
            }
            .navigationTitle("新建合并请求")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(created == nil ? "取消" : "完成") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: create) { if busy { ProgressView() } else { Text("创建").bold() } }
                        .disabled(busy || created != nil || sourceBranch.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $pickingSource) { RefPicker(project: project, selection: $sourceBranch) }
            .sheet(isPresented: $pickingTarget) { RefPicker(project: project, selection: $targetBranch) }
            .onAppear {
                if sourceBranch.isEmpty { sourceBranch = source }
                if targetBranch.isEmpty { targetBranch = target.isEmpty ? (project.defaultBranch ?? "main") : target }
            }
            .onChange(of: sourceBranch) { _, value in
                if title.isEmpty {
                    title = value.split(separator: "/").last.map { $0.replacingOccurrences(of: "-", with: " ").capitalized } ?? value
                }
            }
            .routeDestinations()
        }
    }

    private func create() {
        error = nil
        busy = true
        var request = NewMergeRequest(source: sourceBranch, target: targetBranch, title: draft ? "Draft: \(title)" : title,
                                      description: description.isEmpty ? nil : description, removeSourceBranch: removeSource, squash: squash)
        request.assigneeIds = [session.account.userID]
        let client = session.client, id = project.id
        Task {
            defer { busy = false }
            do { created = try await client.createMergeRequest(id, request); Haptics.success() }
            catch { self.error = error.localizedDescription }
        }
    }
}
