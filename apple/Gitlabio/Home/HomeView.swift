import SwiftUI
import Observation
import GitLabCore

@MainActor @Observable
final class HomeModel {
    var reviews: [MergeRequest] = []
    var assignedMRs: [MergeRequest] = []
    var issues: [Issue] = []
    var events: [Event] = []
    var reviewTotal = 0
    var mrTotal = 0
    var issueTotal = 0
    var error: Error?
    var loaded = false

    func load(_ session: Session) async {
        let client = session.client
        let username = session.account.username
        async let reviews = client.mergeRequests(filter: .reviewRequested, username: username)
        async let mrs = client.mergeRequests(filter: .assignedToMe)
        async let issues = client.issues(filter: .assignedToMe)
        async let events = client.events()
        do {
            let (r, m, i) = try await (reviews, mrs, issues)
            self.reviews = r.items
            self.reviewTotal = r.total ?? r.items.count
            self.assignedMRs = m.items
            self.mrTotal = m.total ?? m.items.count
            self.issues = i.items
            self.issueTotal = i.total ?? i.items.count
            self.events = (try? await events.items) ?? []
            error = nil
        } catch {
            self.error = error
        }
        loaded = true
        await session.refreshTodoCount()
    }
}

struct HomeView: View {
    @Environment(Session.self) private var session
    @State private var model = HomeModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                GlassGroup(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        NavigationLink(value: Route.myWork(.reviews)) {
                            StatTile(title: "待我审查", value: model.reviewTotal, symbol: "eye.fill", tint: Theme.purple)
                        }
                        NavigationLink(value: Route.myWork(.assignedMergeRequests)) {
                            StatTile(title: "我的合并请求", value: model.mrTotal, symbol: "arrow.triangle.pull", tint: Theme.orange)
                        }
                        NavigationLink(value: Route.myWork(.assignedIssues)) {
                            StatTile(title: "指派给我的 Issue", value: model.issueTotal, symbol: "smallcircle.filled.circle", tint: Theme.mint)
                        }
                        NavigationLink(value: Route.todos) {
                            StatTile(title: "待办", value: session.todoCount, symbol: "checklist", tint: Theme.indigo)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let error = model.error, model.reviews.isEmpty && model.assignedMRs.isEmpty {
                    ErrorStateView(error: error) { await model.load(session) }
                } else if !model.loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    section("待我审查", symbol: "eye", items: model.reviews, route: .myWork(.reviews), empty: "没有等待你审查的合并请求")
                    section("指派给我的合并请求", symbol: "arrow.triangle.pull", items: model.assignedMRs,
                            route: .myWork(.assignedMergeRequests), empty: "没有指派给你的合并请求")
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink(value: Route.myWork(.assignedIssues)) {
                            SectionTitle(title: "我的 Issue", symbol: "smallcircle.filled.circle", count: model.issueTotal)
                        }
                        .buttonStyle(.plain)
                        if model.issues.isEmpty {
                            EmptyCard(text: "没有指派给你的 Issue")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(model.issues.prefix(4)) { issue in
                                    NavigationLink(value: Route.issue(projectID: issue.projectId, iid: issue.iid)) {
                                        IssueRow(issue: issue).padding(14)
                                    }
                                    .buttonStyle(.plain)
                                    if issue.id != model.issues.prefix(4).last?.id { Divider().padding(.leading, 14) }
                                }
                            }
                            .glassCard()
                        }
                    }
                    if !model.events.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: "最近动态", symbol: "clock.arrow.circlepath")
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(model.events.prefix(6)) { EventRow(event: $0) }
                            }
                            .padding(16)
                            .glassCard()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground()
        .navigationTitle("首页")
        .refreshable { await model.load(session) }
        .task { if !model.loaded { await model.load(session) } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(user: session.me, instance: session.instance, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting).font(.subheadline).foregroundStyle(.secondary)
                Text(session.me.name).font(.title2.weight(.bold))
                Label(session.instance.displayName, systemImage: session.instance.isGitLabCom ? "globe" : "server.rack")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if session.isDemo {
                Text("演示").font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 5).glassCapsule(tint: Theme.orange)
            }
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, items: [MergeRequest], route: Route, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: route) {
                HStack {
                    SectionTitle(title: title, symbol: symbol, count: items.count)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            if items.isEmpty {
                EmptyCard(text: empty)
            } else {
                VStack(spacing: 0) {
                    ForEach(items.prefix(4)) { mr in
                        NavigationLink(value: Route.mergeRequest(projectID: mr.projectId, iid: mr.iid)) {
                            MergeRequestRow(mr: mr, showProject: true).padding(14)
                        }
                        .buttonStyle(.plain)
                        if mr.id != items.prefix(4).last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .glassCard()
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: Int
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Text(title).font(.footnote.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 22, tint: tint, interactive: true)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyCard: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.seal")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassCard()
    }
}

struct EventRow: View {
    let event: Event
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(user: event.author, instance: session.instance, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                (Text(event.author?.name ?? "有人").bold() + Text(" ") + Text(actionText).foregroundStyle(.secondary))
                    .font(.subheadline)
                if let title = event.targetTitle ?? event.pushData?.commitTitle {
                    Text(title).font(.subheadline).lineLimit(2)
                }
                if let date = event.createdAt {
                    Text(date.relative).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var actionText: String {
        if let push = event.pushData {
            let count = push.commitCount ?? 0
            return "推送了 \(count) 个提交到 \(push.ref ?? "")"
        }
        let target: String = {
            switch event.targetType {
            case "MergeRequest": return "合并请求 !\(event.targetIid ?? 0)"
            case "Issue": return "Issue #\(event.targetIid ?? 0)"
            case "Note", "DiffNote", "DiscussionNote": return "评论"
            default: return event.targetType ?? ""
            }
        }()
        switch event.actionName {
        case "opened": return "创建了 \(target)"
        case "closed": return "关闭了 \(target)"
        case "accepted", "merged": return "合并了 \(target)"
        case "commented on": return "评论了 \(target)"
        case "approved": return "批准了 \(target)"
        case "joined": return "加入了项目"
        case "created": return "创建了 \(target)"
        default: return "\(event.actionName) \(target)"
        }
    }
}

/// Lists for the dashboard shortcuts.
struct MyWorkView: View {
    let kind: Route.WorkKind
    @Environment(Session.self) private var session
    @State private var mrs: PagedLoader<MergeRequest>?
    @State private var issues: PagedLoader<Issue>?
    @State private var state: WorkItemState = .opened

    var body: some View {
        List {
            if let mrs {
                ForEach(mrs.items) { mr in
                    NavigationLink(value: Route.mergeRequest(projectID: mr.projectId, iid: mr.iid)) {
                        MergeRequestRow(mr: mr, showProject: true)
                    }
                    .task { await mrs.loadMoreIfNeeded(mr) }
                }
                PagingFooter(loader: mrs)
            }
            if let issues {
                ForEach(issues.items) { issue in
                    NavigationLink(value: Route.issue(projectID: issue.projectId, iid: issue.iid)) { IssueRow(issue: issue, showProject: true) }
                        .task { await issues.loadMoreIfNeeded(issue) }
                }
                PagingFooter(loader: issues)
            }
        }
        .overlay {
            if let mrs { PagedStateOverlay(loader: mrs, emptyTitle: "没有内容", emptySymbol: "tray") }
            if let issues { PagedStateOverlay(loader: issues, emptyTitle: "没有内容", emptySymbol: "tray") }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("状态", selection: $state) {
                    Text("打开").tag(WorkItemState.opened)
                    if kind != .assignedIssues { Text("已合并").tag(WorkItemState.merged) }
                    Text("已关闭").tag(WorkItemState.closed)
                    Text("全部").tag(WorkItemState.all)
                }
                .pickerStyle(.menu)
            }
        }
        .refreshable { await mrs?.refresh(); await issues?.refresh() }
        .task(id: state) {
            configure()
            await mrs?.loadFirst()
            await issues?.loadFirst()
        }
    }

    private var title: String {
        switch kind {
        case .reviews: return "待我审查"
        case .assignedMergeRequests: return "指派给我的合并请求"
        case .createdMergeRequests: return "我创建的合并请求"
        case .assignedIssues: return "指派给我的 Issue"
        }
    }

    private func configure() {
        let client = session.client, username = session.account.username, state = state
        switch kind {
        case .reviews:
            mrs = PagedLoader { try await client.mergeRequests(state: state, filter: .reviewRequested, username: username, page: $0) }
        case .assignedMergeRequests:
            mrs = PagedLoader { try await client.mergeRequests(state: state, filter: .assignedToMe, page: $0) }
        case .createdMergeRequests:
            mrs = PagedLoader { try await client.mergeRequests(state: state, filter: .createdByMe, page: $0) }
        case .assignedIssues:
            issues = PagedLoader { try await client.issues(state: state, filter: .assignedToMe, page: $0) }
        }
    }
}
