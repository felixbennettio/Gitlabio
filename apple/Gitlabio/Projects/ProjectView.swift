import SwiftUI
import Observation
import GitLabCore

@MainActor @Observable
final class ProjectModel {
    var project: Project
    var readme: String?
    var readmeChecked = false
    var latestPipeline: Pipeline?
    var openMRs: Int?
    var branchCount: Int?
    var starred = false

    init(project: Project) { self.project = project }

    func load(_ client: GitLabClient) async {
        let id = project.id
        async let full = client.project(id)
        async let pipelines = client.pipelines(id, ref: project.defaultBranch)
        async let mrs = client.mergeRequests(project: id, state: .opened)
        async let branches = client.branches(id)
        if let full = try? await full { project = full }
        latestPipeline = (try? await pipelines)?.items.first
        if let page = try? await mrs { openMRs = page.total ?? page.items.count }
        if let page = try? await branches { branchCount = page.total ?? page.items.count }
        if let ref = project.defaultBranch {
            let path = project.readmePath ?? "README.md"
            if let file = try? await client.file(id, path: path, ref: ref), let text = try? file.text() { readme = text }
        }
        readmeChecked = true
    }
}

struct ProjectView: View {
    @Environment(Session.self) private var session
    @State private var model: ProjectModel

    init(project: Project) { _model = State(initialValue: ProjectModel(project: project)) }

    private var project: Project { model.project }
    private var ref: String { project.defaultBranch ?? "main" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GlassGroup(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        tile("代码", "chevron.left.forwardslash.chevron.right", Theme.indigo, .tree(project, ref: ref, path: ""))
                        tile("提交", "clock.arrow.circlepath", Theme.mint, .commits(project, ref: ref))
                        tile("分支", "arrow.triangle.branch", Theme.tangerine, .branches(project), badge: model.branchCount)
                        if project.mergeRequestsEnabled != false {
                            tile("合并请求", "arrow.triangle.pull", Theme.purple, .mergeRequests(project), badge: model.openMRs)
                        }
                        if project.issuesEnabled != false {
                            tile("Issue", "smallcircle.filled.circle", Theme.opened, .issues(project), badge: project.openIssuesCount)
                        }
                        if project.jobsEnabled != false {
                            tile("CI/CD", "point.3.connected.trianglepath.dotted", Theme.orange, .pipelines(project))
                        }
                    }
                }

                if let pipeline = model.latestPipeline {
                    NavigationLink(value: Route.pipeline(projectID: project.id, id: pipeline.id)) {
                        HStack(spacing: 12) {
                            StatusIcon(status: pipeline.status, size: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(ref) 上的最新流水线").font(.caption).foregroundStyle(.secondary)
                                Text("#\(String(pipeline.id)) · \(pipeline.status.title)").font(.headline)
                                if let date = pipeline.createdAt { Text(date.relative).font(.caption).foregroundStyle(.tertiary) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .glassCard(tint: Theme.color(for: pipeline.status), interactive: true)
                    }
                    .buttonStyle(.plain)
                }

                cloneCard

                if let readme = model.readme {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(project.readmePath.map { ($0 as NSString).lastPathComponent } ?? "README.md", systemImage: "book.closed.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        MarkdownView(text: readme, base: readmeBase)
                    }
                    .padding(18)
                    .glassCard()
                } else if !model.readmeChecked {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .ambientBackground(Color.seeded(project.name))
        .navigationTitle(project.name)
        .inlineTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.starred.toggle()
                    Haptics.tap()
                    let starred = model.starred, id = project.id, client = session.client
                    Task { try? await client.star(id, starred: starred) }
                } label: {
                    Image(systemName: model.starred ? "star.fill" : "star")
                }
                .accessibilityLabel(model.starred ? "取消星标" : "星标")
                if let url = project.webUrl.flatMap(URL.init(string:)) {
                    ShareLink(item: url)
                }
            }
        }
        .refreshable { await model.load(session.client) }
        .task { if !model.readmeChecked { await model.load(session.client) } }
    }

    private var readmeBase: URL? {
        project.webUrl.flatMap { URL(string: $0 + "/-/raw/\(ref)/") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProjectAvatar(project: project, instance: session.instance, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.title2.weight(.bold))
                    Text(project.namespacePath).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let description = project.description, !description.isEmpty {
                Text(description).font(.subheadline)
            }
            HStack(spacing: 14) {
                Meta(symbol: "star", text: "\(project.starCount ?? 0)")
                Meta(symbol: "tuningfork", text: "\(project.forksCount ?? 0)")
                Meta(symbol: "arrow.triangle.branch", text: ref)
                if let role = project.permissions?.roleName, (project.permissions?.level ?? 0) > 0 {
                    Meta(symbol: "person.badge.key", text: role)
                }
            }
            if let topics = project.topics, !topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(topics, id: \.self) { topic in
                        Text(topic).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 4).glassCapsule()
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private func tile(_ title: String, _ symbol: String, _ tint: Color, _ route: Route, badge: Int? = nil) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    if let badge, badge > 0 { Text("\(badge)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.secondary) }
                }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var cloneCard: some View {
        if project.httpUrlToRepo != nil || project.sshUrlToRepo != nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("克隆", systemImage: "square.and.arrow.down.on.square").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach([("HTTPS", project.httpUrlToRepo), ("SSH", project.sshUrlToRepo)], id: \.0) { kind, url in
                    if let url {
                        HStack {
                            Text(kind).font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                            Text(url).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { Clipboard.copy(url); Haptics.success() } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("复制 \(kind) 地址")
                        }
                    }
                }
            }
            .padding(16)
            .glassCard()
        }
    }
}
