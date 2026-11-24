import SwiftUI
import Observation
import GitLabCore

struct CommitsView: View {
    let project: Project
    @State var ref: String
    let path: String
    @Environment(Session.self) private var session
    @State private var loader: PagedLoader<Commit>?
    @State private var choosingRef = false

    init(project: Project, ref: String, path: String = "") {
        self.project = project
        self._ref = State(initialValue: ref)
        self.path = path
    }

    var body: some View {
        List {
            if let loader {
                let groups = Dictionary(grouping: loader.items) { Calendar.current.startOfDay(for: $0.date ?? .distantPast) }
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(groups[day]!) { commit in
                            NavigationLink(value: Route.commit(projectID: project.id, sha: commit.id)) { CommitRow(commit: commit) }
                                .task { await loader.loadMoreIfNeeded(commit) }
                        }
                    }
                }
                PagingFooter(loader: loader)
            }
        }
        .groupedList()
        .overlay { if let loader { PagedStateOverlay(loader: loader, emptyTitle: "没有提交", emptySymbol: "clock") } }
        .navigationTitle(path.isEmpty ? "提交" : (path as NSString).lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { choosingRef = true } label: { Label(ref, systemImage: "arrow.triangle.branch") }
            }
        }
        .sheet(isPresented: $choosingRef) { RefPicker(project: project, selection: $ref) }
        .refreshable { await loader?.refresh() }
        .task(id: ref) {
            let client = session.client, id = project.id, ref = ref, path = path
            let fetch: (Int) async throws -> Page<Commit> = { try await client.commits(id, ref: ref, path: path, page: $0) }
            if let loader { loader.replaceFetch(fetch) } else { loader = PagedLoader(fetch) }
            await loader?.loadFirst()
        }
    }
}

struct CommitRow: View {
    let commit: Commit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: commit.authorName, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    Text(commit.authorName).font(.caption).foregroundStyle(.secondary)
                    if let date = commit.date { Text(date.relative).font(.caption).foregroundStyle(.tertiary) }
                }
            }
            Spacer(minLength: 6)
            Text(commit.shortId)
                .font(.caption.monospaced())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 2)
    }
}

@MainActor @Observable
final class CommitDetailModel {
    var commit: Commit?
    var diffs: [FileDiff] = []
    var error: Error?

    func load(_ client: GitLabClient, project: Int, sha: String) async {
        do {
            async let commit = client.commit(project, sha: sha)
            async let diffs = client.commitDiff(project, sha: sha)
            self.commit = try await commit
            self.diffs = try await diffs.items
            error = nil
        } catch { self.error = error }
    }
}

struct CommitDetailView: View {
    let projectID: Int
    let sha: String
    @Environment(Session.self) private var session
    @State private var model = CommitDetailModel()

    var body: some View {
        ScrollView {
            if let commit = model.commit {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(commit.title).font(.title3.weight(.bold))
                        if let body = commit.body { Text(body).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                        HStack(spacing: 10) {
                            Avatar(name: commit.authorName, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(commit.authorName).font(.subheadline.weight(.semibold))
                                if let date = commit.date { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button { Clipboard.copy(commit.id); Haptics.success() } label: {
                                Label(commit.shortId, systemImage: "doc.on.doc").font(.caption.monospaced())
                            }
                            .glassButton()
                            .controlSize(.small)
                        }
                        if let stats = commit.stats {
                            HStack(spacing: 14) {
                                Meta(symbol: "doc", text: "\(model.diffs.count) 个文件")
                                Text("+\(stats.additions)").foregroundStyle(Theme.opened)
                                Text("−\(stats.deletions)").foregroundStyle(Theme.closed)
                            }
                            .font(.caption.weight(.semibold).monospacedDigit())
                        }
                        if let pipeline = commit.lastPipeline {
                            NavigationLink(value: Route.pipeline(projectID: projectID, id: pipeline.id)) {
                                HStack { StatusPill(status: pipeline.status); Text("流水线 #\(String(pipeline.id))").font(.caption); Spacer() }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .glassCard()
                    DiffList(diffs: model.diffs)
                }
                .padding()
            } else if let error = model.error {
                ErrorStateView(error: error) { await model.load(session.client, project: projectID, sha: sha) }
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .ambientBackground(Theme.mint)
        .navigationTitle("提交 \(String(sha.prefix(8)))")
        .inlineTitle()
        .toolbar {
            if let url = model.commit?.webUrl.flatMap(URL.init(string:)) {
                ToolbarItem(placement: .primaryAction) { ShareLink(item: url) }
            }
        }
        .task { if model.commit == nil { await model.load(session.client, project: projectID, sha: sha) } }
    }
}

struct BranchesView: View {
    let project: Project
    @Environment(Session.self) private var session
    @State private var loader: PagedLoader<Branch>?
    @State private var search = ""
    @State private var creating = false
    @State private var newName = ""
    @State private var deleting: Branch?
    @State private var runner = ActionRunner()

    var body: some View {
        List {
            if let loader {
                ForEach(loader.items) { branch in
                    NavigationLink(value: Route.tree(project, ref: branch.name, path: "")) { BranchRow(branch: branch) }
                        .task { await loader.loadMoreIfNeeded(branch) }
                        .swipeActions(edge: .trailing) {
                            if !branch.isDefault && !branch.isProtected {
                                Button(role: .destructive) { deleting = branch } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !branch.isDefault {
                                NavigationLink(value: Route.compare(project, from: project.defaultBranch ?? "main", to: branch.name)) {
                                    Label("对比", systemImage: "arrow.left.arrow.right")
                                }
                                .tint(Theme.purple)
                            }
                        }
                        .contextMenu {
                            NavigationLink(value: Route.commits(project, ref: branch.name)) { Label("提交历史", systemImage: "clock") }
                            NavigationLink(value: Route.pipelines(project)) { Label("流水线", systemImage: "point.3.connected.trianglepath.dotted") }
                            if !branch.isDefault {
                                NavigationLink(value: Route.compare(project, from: project.defaultBranch ?? "main", to: branch.name)) {
                                    Label("与默认分支对比", systemImage: "arrow.left.arrow.right")
                                }
                            }
                            Button { Clipboard.copy(branch.name) } label: { Label("复制名称", systemImage: "doc.on.doc") }
                        }
                }
                PagingFooter(loader: loader)
            }
        }
        .listStyle(.plain)
        .overlay { if let loader { PagedStateOverlay(loader: loader, emptyTitle: "没有分支", emptySymbol: "arrow.triangle.branch") } }
        .searchable(text: $search, prompt: "搜索分支")
        .navigationTitle("分支")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("新建分支", systemImage: "plus") }
            }
        }
        .alert("从 \(project.defaultBranch ?? "main") 新建分支", isPresented: $creating) {
            TextField("分支名", text: $newName).technicalInput()
            Button("创建") {
                let name = newName, client = session.client, id = project.id, from = project.defaultBranch ?? "main"
                runner.run {
                    _ = try await client.createBranch(id, name: name, from: from)
                    newName = ""
                    await loader?.refresh()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除分支「\(deleting?.name ?? "")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("删除分支", role: .destructive) {
                guard let branch = deleting else { return }
                let client = session.client, id = project.id
                runner.run {
                    try await client.deleteBranch(id, name: branch.name)
                    loader?.remove { $0.name == branch.name }
                }
            }
        } message: { Text("此操作不能撤销。未合并的提交可能丢失。") }
        .actionErrors(runner)
        .refreshable { await loader?.refresh() }
        .task(id: search) {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            let client = session.client, id = project.id, term = search
            let fetch: (Int) async throws -> Page<Branch> = { try await client.branches(id, search: term, page: $0) }
            if let loader { loader.replaceFetch(fetch) } else { loader = PagedLoader(fetch) }
            await loader?.loadFirst()
        }
    }
}

struct BranchRow: View {
    let branch: Branch
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.orange)
                Text(branch.name).font(.body.monospaced().weight(.medium)).lineLimit(1).truncationMode(.middle)
                if branch.isDefault {
                    Text("默认").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.orange, in: Capsule())
                }
                if branch.isProtected {
                    Label("受保护", systemImage: "lock.fill").labelStyle(.iconOnly).font(.caption).foregroundStyle(.secondary)
                }
                if branch.merged == true { Text("已合并").font(.caption2.bold()).foregroundStyle(Theme.merged) }
            }
            if let commit = branch.commit {
                Text(commit.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(commit.authorName)
                    if let date = commit.date { Text("·"); Text(date.relative) }
                }
                .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct CompareView: View {
    let project: Project
    let from: String
    let to: String
    @Environment(Session.self) private var session
    @State private var loader: Loader<Comparison>?
    @State private var creatingMR = false

    var body: some View {
        ScrollView {
            if let loader {
                LoadingContent(loader: loader) { comparison in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            BranchTag(name: from)
                            Image(systemName: "arrow.right")
                            BranchTag(name: to)
                            Spacer()
                        }
                        if comparison.commits.isEmpty {
                            EmptyStateView(title: "没有差异", symbol: "equal.circle", message: "\(to) 没有 \(from) 之外的提交。")
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(comparison.commits) { commit in
                                    NavigationLink(value: Route.commit(projectID: project.id, sha: commit.id)) { CommitRow(commit: commit).padding(12) }
                                        .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                            .glassCard()
                            DiffList(diffs: comparison.diffs)
                        }
                    }
                    .padding()
                }
            }
        }
        .ambientBackground(Theme.purple)
        .navigationTitle("对比")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingMR = true } label: { Label("创建合并请求", systemImage: "arrow.triangle.pull") }
            }
        }
        .sheet(isPresented: $creatingMR) { CreateMergeRequestView(project: project, source: to, target: from) }
        .onAppear {
            if loader == nil {
                let client = session.client, id = project.id, from = from, to = to
                loader = Loader { try await client.compare(id, from: from, to: to) }
            }
        }
    }
}
