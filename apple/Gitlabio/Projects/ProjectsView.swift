import SwiftUI
import GitLabCore

struct ProjectsView: View {
    @Environment(Session.self) private var session
    @State private var scope: ProjectScope = .membership
    @State private var order: ProjectOrder = .lastActivityAt
    @State private var search = ""
    @State private var loader: PagedLoader<Project>?

    var body: some View {
        List {
            if let loader {
                ForEach(loader.items) { project in
                    NavigationLink(value: Route.project(project)) { ProjectRow(project: project) }
                        .task { await loader.loadMoreIfNeeded(project) }
                        .swipeActions(edge: .trailing) {
                            Button {
                                Task { try? await session.client.star(project.id, starred: true) }
                            } label: { Label("星标", systemImage: "star") }
                            .tint(.yellow)
                        }
                        .contextMenu {
                            if let url = project.webUrl.flatMap(URL.init(string:)) {
                                ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
                                Link(destination: url) { Label("在浏览器中打开", systemImage: "safari") }
                            }
                            if let clone = project.httpUrlToRepo {
                                Button { Clipboard.copy(clone) } label: { Label("复制 HTTPS 克隆地址", systemImage: "doc.on.doc") }
                            }
                        }
                }
                PagingFooter(loader: loader)
            }
        }
        .listStyle(.plain)
        .overlay {
            if let loader {
                PagedStateOverlay(loader: loader, emptyTitle: search.isEmpty ? "没有项目" : "没有匹配的项目",
                                  emptySymbol: "square.stack.3d.up.slash",
                                  emptyMessage: scope == .starred ? "在项目上左滑即可添加星标。" : nil)
            }
        }
        .navigationTitle("项目")
        .searchable(text: $search, prompt: "搜索项目")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("范围", selection: $scope) {
                        ForEach(ProjectScope.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("排序", selection: $order) {
                        ForEach(ProjectOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("筛选", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(ProjectScope.allCases) { item in
                            Button { withAnimation(.snappy) { scope = item } } label: {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(scope == item ? .white : .primary)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background { if scope == item { Capsule().fill(Theme.orange.gradient) } }
                                    .glassCapsule(interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
        .refreshable { await loader?.refresh() }
        .task(id: "\(scope.rawValue)|\(order.rawValue)|\(search)") {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let client = session.client, scope = scope, order = order, term = search
            let fetch: (Int) async throws -> Page<Project> = { try await client.projects(scope: scope, search: term, order: order, page: $0) }
            if let loader { loader.replaceFetch(fetch) } else { loader = PagedLoader(fetch) }
            await loader?.loadFirst()
        }
    }
}

struct ProjectRow: View {
    let project: Project
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProjectAvatar(project: project, instance: session.instance, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name).font(.headline).lineLimit(1)
                    visibilityIcon
                }
                Text(project.namespacePath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let description = project.description, !description.isEmpty {
                    Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    if let stars = project.starCount { Meta(symbol: "star", text: "\(stars)") }
                    if let forks = project.forksCount, forks > 0 { Meta(symbol: "tuningfork", text: "\(forks)") }
                    if let date = project.lastActivityAt { Meta(symbol: "clock", text: date.relative) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var visibilityIcon: some View {
        switch project.visibility {
        case "private": Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("私有")
        case "internal": Image(systemName: "building.2.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("内部")
        default: EmptyView()
        }
    }
}
