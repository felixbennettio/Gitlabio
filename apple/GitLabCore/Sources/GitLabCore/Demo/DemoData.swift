import Foundation

/// Fictional sample data for the demo instance. Timestamps are relative to launch time.
final class DemoData: Sendable {
    let me = User(id: 1, username: "mira", name: "Mira Chen")
    let leo = User(id: 2, username: "leo.park", name: "Leo Park")
    let ana = User(id: 3, username: "ana", name: "Ana Souza")
    let sam = User(id: 4, username: "sam.k", name: "Sam Kowalski")
    let bot = User(id: 5, username: "release-bot", name: "Release Bot")

    let projects: [Project]
    let branches: [Branch]
    let tags: [Tag]
    let commits: [Commit]
    let mergeRequests: [MergeRequest]
    let issues: [Issue]
    let pipelines: [Pipeline]
    let todos: [Todo]
    let events: [Event]
    let labels: [ProjectLabel]
    let milestones: [Milestone]
    let diffs: [FileDiff]
    let mergeRequestDiscussions: [Discussion]
    let issueDiscussions: [Discussion]
    let members: [Member]
    let allJobs: [Job]

    static func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }

    init() {
        func project(_ id: Int, _ path: String, _ description: String, stars: Int, forks: Int, issues: Int,
                     minutes: Double, visibility: String = "private", topics: [String] = [], level: Int = 40) -> Project {
            var value = Project(id: id, name: String(path.split(separator: "/").last!).replacingOccurrences(of: "-", with: " ").capitalized,
                                pathWithNamespace: path, description: description, defaultBranch: "main")
            value.path = String(path.split(separator: "/").last!)
            value.nameWithNamespace = path.replacingOccurrences(of: "/", with: " / ")
            value.webUrl = "https://gitlab.demo.invalid/" + path
            value.starCount = stars
            value.forksCount = forks
            value.openIssuesCount = issues
            value.lastActivityAt = Self.ago(minutes)
            value.createdAt = Self.ago(60 * 24 * 400)
            value.visibility = visibility
            value.topics = topics
            value.readmeUrl = value.webUrl! + "/-/blob/main/README.md"
            value.httpUrlToRepo = value.webUrl! + ".git"
            value.sshUrlToRepo = "git@gitlab.demo.invalid:" + path + ".git"
            value.namespace = Namespace(id: id * 10, name: String(path.split(separator: "/").first!).capitalized,
                                        path: String(path.split(separator: "/").first!), kind: "group")
            value.permissions = ProjectPermissions(projectAccess: .init(accessLevel: level))
            value.issuesEnabled = true
            value.mergeRequestsEnabled = true
            value.jobsEnabled = true
            value.emptyRepo = false
            return value
        }
        projects = [
            project(101, "aurora/mobile-app", "Aurora 的 iOS 与 Android 客户端：SwiftUI、Compose 与共享设计令牌。", stars: 128, forks: 14, issues: 23, minutes: 6, topics: ["ios", "android", "swiftui"]),
            project(102, "aurora/api-gateway", "边缘网关：鉴权、限流、请求追踪。", stars: 64, forks: 9, issues: 11, minutes: 48, topics: ["go", "grpc"]),
            project(103, "aurora/design-system", "跨平台组件库与 Figma 令牌同步。", stars: 41, forks: 3, issues: 6, minutes: 180, visibility: "internal", topics: ["design"]),
            project(104, "infra/terraform-modules", "可复用的 Terraform 模块：VPC、Kubernetes、观测栈。", stars: 22, forks: 5, issues: 2, minutes: 60 * 26, topics: ["terraform"], level: 30),
            project(105, "mira/dotfiles", "个人 shell、编辑器与终端配置。", stars: 7, forks: 0, issues: 0, minutes: 60 * 24 * 6, visibility: "public", level: 50),
            project(106, "aurora/data-pipeline", "事件采集与批处理作业（Python / Airflow）。", stars: 18, forks: 2, issues: 9, minutes: 60 * 5, topics: ["python"])
        ]

        var c: [Commit] = []
        let commitSpecs: [(String, String, User, Double)] = [
            ("feat(pipeline): show stage graph with live job status", "Render jobs grouped by stage and refresh running jobs every few seconds.\n\nCloses #42", me, 9),
            ("fix(auth): refresh expired session before retrying request", "", leo, 55),
            ("chore(deps): bump swift-collections to 1.2.0", "", bot, 140),
            ("feat(editor): stage multiple files into a single commit", "Adds the change basket and commit sheet.", me, 60 * 4),
            ("docs: describe self-signed certificate trust", "", ana, 60 * 9),
            ("refactor(network): move pagination into APIClient", "", sam, 60 * 22),
            ("test: cover diff parser edge cases", "", me, 60 * 30),
            ("fix(ci): cache Gradle wrapper between jobs", "", leo, 60 * 47)
        ]
        for (index, spec) in commitSpecs.enumerated() {
            let hex = String(0x3fa9c210 + index * 0x1111111, radix: 16)
            var commit = Commit(id: hex + "9e4b7d2c1a0f8e6d5c4b3a291807f6e5", title: spec.0,
                                message: spec.1.isEmpty ? spec.0 : spec.0 + "\n\n" + spec.1,
                                authorName: spec.2.name, authorEmail: spec.2.username + "@demo.invalid", date: Self.ago(spec.3))
            commit.stats = CommitStats(additions: 12 + index * 17, deletions: 3 + index * 4)
            commit.webUrl = "https://gitlab.demo.invalid/aurora/mobile-app/-/commit/" + commit.id
            commit.parentIds = []
            c.append(commit)
        }
        commits = c

        branches = [
            Branch(name: "main", isProtected: true, isDefault: true, commit: c[0]),
            Branch(name: "feat/pipeline-graph", commit: c[0]),
            Branch(name: "fix/session-refresh", commit: c[1]),
            Branch(name: "feat/change-basket", commit: c[3]),
            Branch(name: "release/2.4", isProtected: true, commit: c[5]),
            Branch(name: "renovate/swift-collections-1.x", commit: c[2])
        ]
        tags = [Tag(name: "v2.4.0", message: "Spring release", commit: c[5]), Tag(name: "v2.3.2", commit: c[7])]

        labels = [
            ProjectLabel(id: 1, name: "bug", color: "#dc2626", textColor: "#ffffff"),
            ProjectLabel(id: 2, name: "feature", color: "#6d28d9", textColor: "#ffffff"),
            ProjectLabel(id: 3, name: "ios", color: "#0ea5e9", textColor: "#ffffff"),
            ProjectLabel(id: 4, name: "android", color: "#16a34a", textColor: "#ffffff"),
            ProjectLabel(id: 5, name: "priority::high", color: "#ea580c", textColor: "#ffffff"),
            ProjectLabel(id: 6, name: "needs design", color: "#db2777", textColor: "#ffffff"),
            ProjectLabel(id: 7, name: "good first issue", color: "#65a30d", textColor: "#ffffff")
        ]
        let spring = Milestone(id: 1, title: "2.5 — Spring")
        milestones = [spring, Milestone(id: 2, title: "2.6")]
        members = [me, leo, ana, sam].map { Member(id: $0.id, username: $0.username, name: $0.name, avatarUrl: nil, accessLevel: 40) }

        func pipeline(_ id: Int, _ status: CIStatus, _ ref: String, _ commit: Commit, source: String, user: User,
                      minutes: Double, duration: Int?) -> Pipeline {
            var value = Pipeline(id: id, iid: id - 4000, projectId: 101, status: status, ref: ref, sha: commit.id, source: source,
                                 user: user, createdAt: Self.ago(minutes), duration: duration)
            value.webUrl = "https://gitlab.demo.invalid/aurora/mobile-app/-/pipelines/\(id)"
            value.startedAt = Self.ago(minutes - 0.5)
            value.finishedAt = status.isFinished ? Self.ago(minutes - Double(duration ?? 0) / 60) : nil
            value.name = commit.title
            return value
        }
        pipelines = [
            pipeline(4127, .running, "feat/pipeline-graph", c[0], source: "merge_request_event", user: me, minutes: 4, duration: nil),
            pipeline(4126, .success, "main", c[1], source: "push", user: leo, minutes: 52, duration: 412),
            pipeline(4125, .failed, "fix/session-refresh", c[1], source: "merge_request_event", user: leo, minutes: 70, duration: 288),
            pipeline(4124, .success, "main", c[2], source: "push", user: bot, minutes: 138, duration: 397),
            pipeline(4123, .manual, "release/2.4", c[5], source: "web", user: ana, minutes: 60 * 20, duration: 655),
            pipeline(4122, .canceled, "feat/change-basket", c[3], source: "push", user: me, minutes: 60 * 4, duration: 61)
        ]

        var jobs: [Job] = []
        let jobSpecs: [(String, String, CIStatus, Double?)] = [
            ("lint", "build", .success, 41), ("ios:build", "build", .success, 236), ("android:build", "build", .success, 198),
            ("unit:core", "test", .success, 64), ("ios:ui-tests", "test", .running, nil), ("android:instrumented", "test", .pending, nil),
            ("testflight", "deploy", .manual, nil), ("play:internal", "deploy", .manual, nil)
        ]
        for pipeline in pipelines {
            for (index, spec) in jobSpecs.enumerated() {
                var status = spec.2
                switch pipeline.status {
                case .success: status = spec.1 == "deploy" ? .manual : .success
                case .failed: status = spec.0 == "ios:ui-tests" ? .failed : (spec.1 == "deploy" ? .skipped : .success)
                case .canceled: status = spec.1 == "build" ? .success : .canceled
                case .manual: status = spec.1 == "deploy" ? .manual : .success
                default: break
                }
                var job = Job(id: pipeline.id * 10 + index, name: spec.0, status: status, stage: spec.1,
                              duration: status == .success || status == .failed ? (spec.3 ?? 120) : nil,
                              allowFailure: spec.0 == "lint", startedAt: status == .pending || status == .manual ? nil : Self.ago(3))
                job.pipeline = .init(id: pipeline.id, ref: pipeline.ref, status: pipeline.status)
                job.ref = pipeline.ref
                job.webUrl = "https://gitlab.demo.invalid/aurora/mobile-app/-/jobs/\(job.id)"
                job.runner = Runner(id: 7, description: spec.0.hasPrefix("ios") || spec.0 == "testflight" ? "ci-macos" : "ci-linux")
                job.tagList = spec.0.hasPrefix("ios") || spec.0 == "testflight" ? ["macos"] : ["linux"]
                job.user = pipeline.user
                job.failureReason = status == .failed ? "script_failure" : nil
                jobs.append(job)
            }
        }
        allJobs = jobs

        func mr(_ iid: Int, _ title: String, _ description: String, source: String, author: User, assignees: [User],
                reviewers: [User], labels: [String], minutes: Double, notes: Int, status: String, draft: Bool = false,
                state: String = "opened") -> MergeRequest {
            var value = MergeRequest(id: 5000 + iid, iid: iid, projectId: 101, title: title, description: description, state: state,
                                     sourceBranch: source, targetBranch: "main", author: author, createdAt: Self.ago(minutes + 60 * 24))
            value.updatedAt = Self.ago(minutes)
            value.assignees = assignees
            value.reviewers = reviewers
            value.labels = labels
            value.userNotesCount = notes
            value.upvotes = notes / 2
            value.draft = draft
            value.detailedMergeStatus = status
            value.mergeStatus = status == "mergeable" ? "can_be_merged" : "cannot_be_merged"
            value.hasConflicts = status == "conflict"
            value.references = References(short: "!\(iid)", full: "aurora/mobile-app!\(iid)")
            value.webUrl = "https://gitlab.demo.invalid/aurora/mobile-app/-/merge_requests/\(iid)"
            value.diffRefs = DiffRefs(baseSha: c[7].id, headSha: c[0].id, startSha: c[7].id)
            value.changesCount = "4"
            value.sha = c[0].id
            value.milestone = spring
            value.taskCompletionStatus = TaskCompletion(count: 4, completedCount: 3)
            return value
        }
        mergeRequests = [
            mr(318, "Pipeline 详情：按阶段展示作业图并实时刷新",
               "## 改动\n\n- 新增 **按 stage 分列** 的作业图\n- 运行中的作业每 5 秒刷新\n- 日志支持 ANSI 颜色与折叠段\n\n## 检查清单\n\n- [x] 单元测试\n- [x] 深浅色截图\n- [x] VoiceOver 标签\n- [ ] iPad 横屏\n\nCloses #42",
               source: "feat/pipeline-graph", author: me, assignees: [me], reviewers: [leo, ana], labels: ["feature", "ios"],
               minutes: 8, notes: 6, status: "ci_still_running"),
            mr(317, "修复会话过期后请求未刷新令牌", "过期的 OAuth 会话现在会先刷新再重试一次请求。\n\n复现步骤见 #57。",
               source: "fix/session-refresh", author: leo, assignees: [leo], reviewers: [me], labels: ["bug", "priority::high"],
               minutes: 70, notes: 3, status: "mergeable"),
            mr(315, "Draft: 变更篮——多文件暂存后一次提交", "在应用内编辑多个文件后统一提交，可选新建分支并直接创建合并请求。",
               source: "feat/change-basket", author: me, assignees: [me], reviewers: [sam], labels: ["feature"],
               minutes: 60 * 4, notes: 11, status: "draft_status", draft: true),
            mr(312, "chore(deps): update swift-collections to 1.2.0", "此合并请求由 Renovate 自动创建。",
               source: "renovate/swift-collections-1.x", author: bot, assignees: [], reviewers: [me], labels: [],
               minutes: 140, notes: 0, status: "mergeable"),
            mr(309, "Android：Material You 动态取色", "按系统壁纸生成配色方案，并保留品牌强调色。",
               source: "feat/dynamic-color", author: ana, assignees: [ana], reviewers: [me, leo], labels: ["android", "needs design"],
               minutes: 60 * 30, notes: 8, status: "discussions_not_resolved"),
            mr(301, "发布 2.4.0", "", source: "release/2.4", author: sam, assignees: [sam], reviewers: [], labels: [],
               minutes: 60 * 24 * 9, notes: 2, status: "not_open", state: "merged")
        ]

        func issue(_ iid: Int, _ title: String, _ description: String, author: User, assignees: [User], labels: [String],
                   minutes: Double, notes: Int, state: String = "opened") -> Issue {
            var value = Issue(id: 7000 + iid, iid: iid, projectId: 101, title: title, description: description, state: state,
                              author: author, labels: labels, createdAt: Self.ago(minutes + 60 * 48))
            value.updatedAt = Self.ago(minutes)
            value.assignees = assignees
            value.userNotesCount = notes
            value.upvotes = notes
            value.references = References(short: "#\(iid)", full: "aurora/mobile-app#\(iid)")
            value.webUrl = "https://gitlab.demo.invalid/aurora/mobile-app/-/issues/\(iid)"
            value.milestone = iid % 2 == 0 ? spring : nil
            return value
        }
        issues = [
            issue(57, "会话过期后列表一直转圈", "### 现象\n\n令牌过期后，项目列表不会提示重新登录。\n\n### 期望\n\n显示明确的错误并引导更新令牌。",
                  author: sam, assignees: [leo], labels: ["bug", "priority::high"], minutes: 30, notes: 4),
            issue(42, "Pipeline 详情页展示作业依赖关系", "希望像网页端一样按阶段查看作业，并能直接重试失败的作业。",
                  author: ana, assignees: [me], labels: ["feature", "ios"], minutes: 12, notes: 7),
            issue(55, "iPad 上的代码视图支持并排 diff", "", author: leo, assignees: [me], labels: ["feature", "needs design"], minutes: 60 * 6, notes: 2),
            issue(53, "深色模式下标签对比度不足", "部分浅色标签在深色背景下难以辨认。", author: me, assignees: [ana], labels: ["bug", "good first issue"],
                  minutes: 60 * 26, notes: 1),
            issue(48, "支持自签证书的自建实例", "公司内网 GitLab 使用私有 CA。", author: sam, assignees: [], labels: ["feature"],
                  minutes: 60 * 72, notes: 9, state: "closed")
        ]

        let project101 = projects[0]
        todos = [
            Todo(id: 1, project: project101, author: leo, actionName: "review_requested", targetType: "MergeRequest",
                 target: TodoTarget(id: 5317, iid: 317, title: mergeRequests[1].title, state: "opened", webUrl: mergeRequests[1].webUrl, projectId: 101),
                 body: mergeRequests[1].title, createdAt: Self.ago(70)),
            Todo(id: 2, project: project101, author: ana, actionName: "mentioned", targetType: "Issue",
                 target: TodoTarget(id: 7042, iid: 42, title: issues[1].title, state: "opened", webUrl: issues[1].webUrl, projectId: 101),
                 body: "@mira 作业图的空状态可以参考网页端吗？", createdAt: Self.ago(15)),
            Todo(id: 3, project: project101, author: me, actionName: "build_failed", targetType: "MergeRequest",
                 target: TodoTarget(id: 5317, iid: 317, title: mergeRequests[1].title, state: "opened", webUrl: mergeRequests[1].webUrl, projectId: 101),
                 body: "流水线 #4125 失败：ios:ui-tests", createdAt: Self.ago(66)),
            Todo(id: 4, project: projects[1], author: sam, actionName: "assigned", targetType: "Issue",
                 target: TodoTarget(id: 7101, iid: 12, title: "限流规则热更新", state: "opened", webUrl: nil, projectId: 102),
                 body: "限流规则热更新", createdAt: Self.ago(60 * 5)),
            Todo(id: 5, project: project101, author: leo, actionName: "approval_required", targetType: "MergeRequest",
                 target: TodoTarget(id: 5312, iid: 312, title: mergeRequests[3].title, state: "opened", webUrl: nil, projectId: 101),
                 body: mergeRequests[3].title, createdAt: Self.ago(60 * 9))
        ]

        events = [
            Event(id: 1, projectId: 101, actionName: "pushed to", targetType: nil, targetIid: nil, targetTitle: nil, createdAt: Self.ago(9),
                  author: me, pushData: PushData(commitCount: 2, action: "pushed", refType: "branch", ref: "feat/pipeline-graph", commitTitle: c[0].title)),
            Event(id: 2, projectId: 101, actionName: "commented on", targetType: "MergeRequest", targetIid: 318, targetTitle: mergeRequests[0].title,
                  createdAt: Self.ago(20), author: ana),
            Event(id: 3, projectId: 101, actionName: "opened", targetType: "MergeRequest", targetIid: 317, targetTitle: mergeRequests[1].title,
                  createdAt: Self.ago(75), author: leo),
            Event(id: 4, projectId: 102, actionName: "accepted", targetType: "MergeRequest", targetIid: 88, targetTitle: "限流中间件支持按租户配置",
                  createdAt: Self.ago(60 * 3), author: sam),
            Event(id: 5, projectId: 101, actionName: "closed", targetType: "Issue", targetIid: 48, targetTitle: issues[4].title,
                  createdAt: Self.ago(60 * 8), author: me)
        ]

        diffs = [
            FileDiff(oldPath: "Sources/Pipelines/PipelineGraph.swift", newPath: "Sources/Pipelines/PipelineGraph.swift", diff: """
            @@ -12,14 +12,22 @@ struct PipelineGraph: View {
                 let stages: [PipelineStage]
            -    @State private var timer: Timer?
            +    @State private var refreshTask: Task<Void, Never>?
            +    var onRetry: (Job) -> Void = { _ in }

                 var body: some View {
            -        ScrollView(.horizontal) {
            -            HStack { ForEach(stages) { StageColumn(stage: $0) } }
            +        ScrollView(.horizontal, showsIndicators: false) {
            +            HStack(alignment: .top, spacing: 16) {
            +                ForEach(stages) { stage in
            +                    StageColumn(stage: stage, onRetry: onRetry)
            +                }
            +            }
            +            .padding(.horizontal)
                     }
            +        .task { await refreshWhileRunning() }
                 }
            \u{20}
            -    func start() { timer = .scheduledTimer(withTimeInterval: 5, repeats: true) { _ in reload() } }
            +    private func refreshWhileRunning() async {
            +        while !Task.isCancelled, stages.contains(where: { $0.status.isActive }) {
            +            try? await Task.sleep(for: .seconds(5))
            +        }
            +    }
             }
            """),
            FileDiff(oldPath: "Sources/Pipelines/JobLogView.swift", newPath: "Sources/Pipelines/JobLogView.swift", diff: """
            @@ -1,6 +1,9 @@
             import SwiftUI
            +import GitLabCore

             struct JobLogView: View {
            -    let text: String
            +    let log: JobLog
            +    @State private var follow = true
            +    @State private var collapsed: Set<String> = []
             }
            """),
            FileDiff(oldPath: "Tests/PipelineStageTests.swift", newPath: "Tests/PipelineStageTests.swift", diff: """
            @@ -0,0 +1,12 @@
            +import Testing
            +@testable import App
            +
            +@Test func groupsJobsByStageInPipelineOrder() {
            +    let jobs = [Job.fixture(stage: "test"), Job.fixture(stage: "build")]
            +    let stages = PipelineStage.group(jobs)
            +    #expect(stages.map(\\.name) == ["test", "build"])
            +}
            """, newFile: true),
            FileDiff(oldPath: "Sources/Pipelines/LegacyPipelineList.swift", newPath: "Sources/Pipelines/LegacyPipelineList.swift", diff: """
            @@ -1,5 +0,0 @@
            -import SwiftUI
            -
            -struct LegacyPipelineList: View {
            -    var body: some View { Text("Pipelines") }
            -}
            """, deletedFile: true)
        ]

        func note(_ id: Int, _ body: String, _ author: User, _ minutes: Double, system: Bool = false, resolvable: Bool = false,
                  resolved: Bool = false, position: NotePosition? = nil) -> Note {
            var value = Note(id: id, body: body, author: author, createdAt: Self.ago(minutes), system: system)
            value.resolvable = resolvable
            value.resolved = resolved
            value.position = position
            return value
        }
        let refs = DiffRefs(baseSha: c[7].id, headSha: c[0].id, startSha: c[7].id)
        mergeRequestDiscussions = [
            Discussion(id: "d1", notes: [note(11, "added 2 commits", me, 60 * 3, system: true)]),
            Discussion(id: "d2", notes: [
                note(12, "这里改成 `Task` 之后，离开页面时会自动取消吗？", leo, 60 * 2, resolvable: true,
                     position: NotePosition(refs: refs, oldPath: "Sources/Pipelines/PipelineGraph.swift",
                                            newPath: "Sources/Pipelines/PipelineGraph.swift", oldLine: nil, newLine: 14)),
                note(13, "会的，`.task` 修饰器在视图消失时取消任务。我补了一个测试。", me, 60 * 1.5, resolvable: true)
            ], individualNote: false),
            Discussion(id: "d3", notes: [note(14, "深色模式截图看起来很棒 🎉 横向滚动在 iPad 上也正常。", ana, 25)]),
            Discussion(id: "d4", notes: [note(15, "requested review from @leo.park and @ana", me, 60 * 20, system: true)]),
            Discussion(id: "d5", notes: [
                note(16, "失败作业的重试按钮能不能放到卡片右上角？现在要点两次。", sam, 18, resolvable: true, resolved: true),
                note(17, "已调整，长按卡片也可以直接重试。", me, 12, resolvable: true, resolved: true)
            ], individualNote: false)
        ]
        issueDiscussions = [
            Discussion(id: "i1", notes: [note(21, "我先做 iPhone 版本，iPad 并排视图另开 issue。", me, 60 * 5)]),
            Discussion(id: "i2", notes: [note(22, "mentioned in merge request !318", me, 60 * 4, system: true)]),
            Discussion(id: "i3", notes: [note(23, "作业图的空状态可以参考网页端吗？", ana, 15)])
        ]
    }

    func approvals(for mr: MergeRequest) -> Approvals {
        Approvals(approvedBy: mr.iid == 317 ? [ana] : mr.iid == 318 ? [leo] : [], required: 2,
                  userHasApproved: false, userCanApprove: mr.author != me)
    }

    func jobs(pipeline: Int) -> [Job] { allJobs.filter { $0.pipeline?.id == pipeline } }

    // MARK: Repository content

    func tree(_ project: Int, path: String) -> [TreeEntry] {
        let entries: [String: [(String, String)]] = [
            "": [("Sources", "tree"), ("Tests", "tree"), ("docs", "tree"), (".gitlab-ci.yml", "blob"), ("Package.swift", "blob"),
                 ("README.md", "blob"), ("LICENSE", "blob"), (".gitignore", "blob")],
            "Sources": [("App", "tree"), ("Pipelines", "tree"), ("Networking", "tree")],
            "Sources/App": [("AppModel.swift", "blob"), ("RootView.swift", "blob")],
            "Sources/Pipelines": [("PipelineGraph.swift", "blob"), ("JobLogView.swift", "blob")],
            "Sources/Networking": [("APIClient.swift", "blob"), ("TrustPolicy.swift", "blob")],
            "Tests": [("PipelineStageTests.swift", "blob")],
            "docs": [("architecture.md", "blob"), ("screenshot.png", "blob")]
        ]
        return (entries[path] ?? []).map { name, type in
            let full = path.isEmpty ? name : path + "/" + name
            return TreeEntry(id: String(full.hashValue, radix: 16), name: name, type: type, path: full)
        }
    }

    func file(_ project: Int, _ path: String) -> String? {
        switch path {
        case "README.md":
            return """
            # Aurora Mobile

            Aurora 的 **iOS** 与 **Android** 客户端。界面使用 SwiftUI 与 Jetpack Compose，业务逻辑按平台原生实现。

            ## 快速开始

            ```bash
            git clone git@gitlab.demo.invalid:aurora/mobile-app.git
            cd mobile-app && make bootstrap
            ```

            ## 模块

            | 模块 | 说明 |
            | --- | --- |
            | `Sources/App` | 应用入口与导航 |
            | `Sources/Pipelines` | CI/CD 视图 |
            | `Sources/Networking` | API 客户端与证书信任 |

            ## 贡献

            1. 从 `main` 创建分支
            2. 提交合并请求并请求审查
            3. 流水线通过后合并

            > 所有改动都需要至少两位审查者批准。
            """
        case ".gitlab-ci.yml":
            return """
            stages: [build, test, deploy]

            default:
              interruptible: true

            ios:build:
              stage: build
              tags: [macos]
              script:
                - xcodebuild build -scheme Aurora -destination 'generic/platform=iOS Simulator'

            unit:core:
              stage: test
              tags: [linux]
              script:
                - swift test --parallel
              coverage: '/Coverage: \\d+\\.\\d+%/'

            testflight:
              stage: deploy
              tags: [macos]
              when: manual
              rules:
                - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
            """
        case "Package.swift":
            return """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "Aurora",
                platforms: [.iOS(.v18)],
                products: [.library(name: "AuroraKit", targets: ["AuroraKit"])],
                dependencies: [
                    .package(url: "https://github.com/apple/swift-collections", from: "1.2.0")
                ],
                targets: [
                    .target(name: "AuroraKit", dependencies: [.product(name: "Collections", package: "swift-collections")]),
                    .testTarget(name: "AuroraKitTests", dependencies: ["AuroraKit"])
                ]
            )
            """
        case "Sources/Pipelines/PipelineGraph.swift":
            return """
            import SwiftUI

            /// Jobs grouped by stage, refreshed while any job is still running.
            struct PipelineGraph: View {
                let stages: [PipelineStage]
                @State private var refreshTask: Task<Void, Never>?
                var onRetry: (Job) -> Void = { _ in }

                var body: some View {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(stages) { stage in
                                StageColumn(stage: stage, onRetry: onRetry)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .task { await refreshWhileRunning() }
                }

                private func refreshWhileRunning() async {
                    while !Task.isCancelled, stages.contains(where: { $0.status.isActive }) {
                        try? await Task.sleep(for: .seconds(5)) // poll every 5 s
                    }
                }
            }
            """
        case "Sources/Networking/APIClient.swift":
            return """
            import Foundation

            enum APIError: Error { case unauthorized, server(Int) }

            final class APIClient {
                private let session: URLSession
                private let baseURL: URL

                init(baseURL: URL, session: URLSession = .shared) {
                    self.baseURL = baseURL
                    self.session = session
                }

                func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
                    let (data, response) = try await session.data(from: baseURL.appending(path: path))
                    guard let http = response as? HTTPURLResponse else { throw APIError.server(-1) }
                    if http.statusCode == 401 { throw APIError.unauthorized }
                    return try JSONDecoder().decode(T.self, from: data)
                }
            }
            """
        case "docs/architecture.md":
            return "# 架构\n\n应用分为三层：界面、领域模型和网络。\n\n- 界面只依赖领域模型\n- 网络层负责分页、错误映射与证书信任\n"
        case "LICENSE": return "MIT License\n\nCopyright (c) 2026 Aurora\n\nPermission is hereby granted, free of charge, to any person obtaining a copy..."
        case ".gitignore": return ".build/\nDerivedData/\n*.xcuserstate\n# Secrets\n.env\n"
        default:
            if path.hasSuffix(".swift") {
                return "import SwiftUI\n\nstruct \((path as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")): View {\n    var body: some View {\n        Text(\"Hello, Aurora\")\n            .font(.title)\n    }\n}\n"
            }
            return nil
        }
    }

    func trace(job: Int) -> String {
        let esc = "\u{1B}"
        let failed = allJobs.first { $0.id == job }?.status == .failed
        var log = """
        \(esc)[0KRunning with gitlab-runner 18.5.0 (demo)
        \(esc)[0K  on ci-macos \(esc)[0;m
        section_start:1761700000:prepare_executor\r\(esc)[0K\(esc)[0K\(esc)[36;1mPreparing the "shell" executor\(esc)[0;m
        \(esc)[0KUsing Shell (bash) executor...\(esc)[0;m
        section_end:1761700002:prepare_executor\r\(esc)[0K
        section_start:1761700002:get_sources[collapsed=true]\r\(esc)[0K\(esc)[0K\(esc)[36;1mGetting source from Git repository\(esc)[0;m
        \(esc)[32;1mFetching changes with git depth set to 20...\(esc)[0;m
        Initialized empty Git repository in /builds/aurora/mobile-app/.git/
        \(esc)[32;1mChecking out 3fa9c210 as detached HEAD (ref is feat/pipeline-graph)...\(esc)[0;m
        section_end:1761700009:get_sources\r\(esc)[0K
        section_start:1761700009:step_script\r\(esc)[0K\(esc)[0K\(esc)[36;1mExecuting "step_script" stage of the job script\(esc)[0;m
        \(esc)[32;1m$ swift test --parallel\(esc)[0;m
        Building for debugging...
        [1/42] Compiling AuroraKit APIClient.swift
        [12/42] Compiling AuroraKit PipelineGraph.swift
        [42/42] Linking AuroraKitPackageTests
        Build complete! (38.12s)
        ◇ Test run started.
        \(esc)[32m✔\(esc)[0m Test groupsJobsByStageInPipelineOrder() passed after 0.002 seconds.
        \(esc)[32m✔\(esc)[0m Test parsesUnifiedDiffHunks() passed after 0.001 seconds.
        \(esc)[32m✔\(esc)[0m Test mapsUnauthorizedToSignIn() passed after 0.004 seconds.
        \(esc)[33mwarning:\(esc)[0m 'init(url:)' is deprecated: use init(baseURL:)
        """
        if failed {
            log += """

            \(esc)[31m✘\(esc)[0m Test snapshotPipelineGraphDarkMode() failed after 1.204 seconds.
            \(esc)[31;1m  Expectation failed: (image.difference → 0.031) < 0.01\(esc)[0m
            \(esc)[31m✘\(esc)[0m Test run with 48 tests failed after 9.881 seconds with 1 issue.
            section_end:1761700120:step_script\r\(esc)[0K
            \(esc)[31;1mERROR: Job failed: exit status 1\(esc)[0;m
            """
        } else {
            log += """

            \(esc)[32m✔\(esc)[0m Test run with 48 tests passed after 9.881 seconds.
            Coverage: 84.20%
            section_end:1761700120:step_script\r\(esc)[0K
            \(esc)[32;1mJob succeeded\(esc)[0;m
            """
        }
        return log
    }
}

// MARK: Schedules and run form

extension DemoData {
    var schedules: [PipelineSchedule] {
        let nightly = pipelines.first { $0.ref == "main" && $0.source == "push" }
        return [
            PipelineSchedule(id: 11, description: "Nightly build", ref: "main", cron: "0 2 * * *", cronTimezone: "Asia/Shanghai",
                             nextRunAt: Self.ago(-60 * 9), active: true, owner: me,
                             lastPipeline: nightly.map { .init(id: $0.id, sha: $0.sha, ref: $0.ref, status: $0.status) },
                             variables: [.init(key: "BUILD_FLAVOR", value: "nightly", variableType: "env_var"),
                                         .init(key: "UPLOAD_TESTFLIGHT", value: "true", variableType: "env_var")],
                             inputs: [.init(name: "environment", value: .string("staging"))]),
            PipelineSchedule(id: 12, description: "Weekly release candidate", ref: "release/2.4", cron: "0 9 * * 1",
                             cronTimezone: "Asia/Shanghai", nextRunAt: Self.ago(-60 * 24 * 3), active: true, owner: ana,
                             lastPipeline: .init(id: 4123, sha: commits[5].id, ref: "release/2.4", status: .manual)),
            PipelineSchedule(id: 13, description: "Dependency audit", ref: "main", cron: "30 6 1 * *", cronTimezone: "UTC",
                             nextRunAt: nil, active: false, owner: leo)
        ]
    }

    var runForm: RunPipelineForm {
        RunPipelineForm(inputs: [
            CIInputSpec(name: "environment", type: .string, description: "Where the build is deployed",
                        default: .string("staging"), options: [.string("staging"), .string("production")]),
            CIInputSpec(name: "run_ui_tests", type: .boolean, description: "Run the simulator UI tests", default: .bool(true)),
            CIInputSpec(name: "shards", type: .number, description: "Parallel test shards", default: .number(2)),
            CIInputSpec(name: "release_notes", type: .string, description: "Shown to testers", required: true)
        ], variables: [
            CIConfigVariable(key: "UPLOAD_TESTFLIGHT", value: "false", valueOptions: ["false", "true"],
                             description: "Upload the tested iOS build to TestFlight (protected refs only)"),
            CIConfigVariable(key: "BUILD_FLAVOR", value: "release", description: "App flavour to build")
        ])
    }
}
