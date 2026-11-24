import SwiftUI
import GitLabCore

struct InboxView: View {
    @Environment(Session.self) private var session
    @State private var loader: PagedLoader<Todo>?
    @State private var kind: Kind = .all
    @State private var runner = ActionRunner()

    enum Kind: String, CaseIterable, Identifiable {
        case all = "全部", reviews = "审查", mentions = "提及", assigned = "指派", ci = "流水线"
        var id: String { rawValue }
        func matches(_ todo: Todo) -> Bool {
            switch self {
            case .all: return true
            case .reviews: return ["review_requested", "approval_required", "review_submitted"].contains(todo.actionName)
            case .mentions: return ["mentioned", "directly_addressed"].contains(todo.actionName)
            case .assigned: return todo.actionName == "assigned"
            case .ci: return ["build_failed", "unmergeable"].contains(todo.actionName)
            }
        }
    }

    var body: some View {
        List {
            if let loader {
                let items = loader.items.filter(kind.matches)
                ForEach(items) { todo in
                    NavigationLink(value: route(for: todo)) { TodoRow(todo: todo) }
                        .task { await loader.loadMoreIfNeeded(todo) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { markDone(todo) } label: { Label("完成", systemImage: "checkmark") }.tint(Theme.opened)
                        }
                }
                PagingFooter(loader: loader)
            }
        }
        .listStyle(.plain)
        .overlay {
            if let loader {
                if loader.hasLoaded && loader.items.filter(kind.matches).isEmpty && loader.error == nil {
                    EmptyStateView(title: "待办已清空", symbol: "tray", message: "新的审查请求、提及和失败的流水线会出现在这里。")
                } else {
                    PagedStateOverlay(loader: loader, emptyTitle: "待办已清空", emptySymbol: "tray")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Kind.allCases) { item in
                            Button { withAnimation(.snappy) { kind = item } } label: {
                                Text(item.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(kind == item ? .white : .primary)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background { if kind == item { Capsule().fill(Theme.orange.gradient) } }
                                    .glassCapsule(interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("待办")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let client = session.client
                    runner.run {
                        try await client.markAllTodosDone()
                        loader?.remove { _ in true }
                        session.todoCount = 0
                    }
                } label: { Label("全部完成", systemImage: "checkmark.circle") }
                .disabled(loader?.items.isEmpty ?? true)
            }
        }
        .actionErrors(runner)
        .refreshable { await loader?.refresh(); await session.refreshTodoCount() }
        .task {
            if loader == nil {
                let client = session.client
                loader = PagedLoader { try await client.todos(page: $0) }
            }
            await loader?.loadFirst()
        }
    }

    private func route(for todo: Todo) -> Route {
        let project = todo.target?.projectId ?? todo.project?.id ?? 0
        switch todo.targetType {
        case "MergeRequest": return .mergeRequest(projectID: project, iid: todo.target?.iid ?? 0)
        case "Issue", "WorkItem": return .issue(projectID: project, iid: todo.target?.iid ?? 0)
        default: return .projectID(project)
        }
    }

    private func markDone(_ todo: Todo) {
        withAnimation { loader?.remove { $0.id == todo.id } }
        session.todoCount = max(0, session.todoCount - 1)
        let client = session.client
        runner.run { try await client.markTodoDone(todo.id) }
    }
}

struct TodoRow: View {
    let todo: Todo
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(user: todo.author, instance: session.instance, size: 38)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(tint, in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                (Text(todo.author?.name ?? "GitLab").bold() + Text(" \(todo.actionDescription)").foregroundStyle(.secondary))
                    .font(.subheadline)
                Text(todo.target?.title ?? todo.body).font(.body.weight(.medium)).lineLimit(2)
                if todo.actionName == "mentioned" || todo.actionName == "directly_addressed", todo.body != todo.target?.title {
                    Text(todo.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                HStack(spacing: 6) {
                    Text(reference).font(.caption.monospaced())
                    if let date = todo.createdAt { Text("·"); Text(date.relative) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var reference: String {
        let project = todo.project?.pathWithNamespace ?? ""
        switch todo.targetType {
        case "MergeRequest": return "\(project)!\(todo.target?.iid ?? 0)"
        case "Issue": return "\(project)#\(todo.target?.iid ?? 0)"
        default: return project
        }
    }

    private var symbol: String {
        switch todo.actionName {
        case "review_requested", "approval_required", "review_submitted": return "eye.fill"
        case "mentioned", "directly_addressed": return "at"
        case "assigned": return "person.fill"
        case "build_failed": return "xmark"
        case "unmergeable": return "exclamationmark"
        default: return "bell.fill"
        }
    }

    private var tint: Color {
        switch todo.actionName {
        case "review_requested", "approval_required", "review_submitted": return Theme.purple
        case "mentioned", "directly_addressed": return Theme.orange
        case "assigned": return Theme.mint
        case "build_failed", "unmergeable": return Theme.closed
        default: return .gray
        }
    }
}
