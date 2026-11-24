import SwiftUI
import Observation
import GitLabCore

@MainActor @Observable
final class PipelineModel {
    let projectID: Int
    let pipelineID: Int
    var pipeline: Pipeline?
    var stages: [PipelineStage] = []
    var error: Error?

    init(projectID: Int, pipelineID: Int) {
        self.projectID = projectID
        self.pipelineID = pipelineID
    }

    var isActive: Bool { pipeline?.status.isActive == true || stages.contains { $0.jobs.contains { $0.status.isActive } } }

    func load(_ client: GitLabClient) async {
        do {
            async let pipeline = client.pipeline(projectID, id: pipelineID)
            async let jobs = client.pipelineJobs(projectID, pipeline: pipelineID)
            self.pipeline = try await pipeline
            self.stages = PipelineStage.group(try await jobs)
            error = nil
        } catch { if pipeline == nil { self.error = error } }
    }
}

struct PipelineView: View {
    let projectID: Int
    let pipelineID: Int
    @Environment(Session.self) private var session
    @State private var model: PipelineModel
    @State private var runner = ActionRunner()

    init(projectID: Int, pipelineID: Int) {
        self.projectID = projectID
        self.pipelineID = pipelineID
        _model = State(initialValue: PipelineModel(projectID: projectID, pipelineID: pipelineID))
    }

    var body: some View {
        ScrollView {
            if let pipeline = model.pipeline {
                VStack(alignment: .leading, spacing: 22) {
                    summary(pipeline)
                    if model.stages.isEmpty {
                        EmptyStateView(title: "没有作业", symbol: "square.dashed")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "阶段", symbol: "square.split.3x1", count: model.stages.count)
                            StageGraph(stages: model.stages, projectID: projectID) { job, action in perform(action, on: job) }
                        }
                        let failed = model.stages.flatMap(\.jobs).filter { $0.status == .failed }
                        if !failed.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionTitle(title: "失败的作业", symbol: "xmark.octagon", count: failed.count)
                                VStack(spacing: 0) {
                                    ForEach(failed) { job in
                                        NavigationLink(value: Route.job(projectID: projectID, id: job.id)) {
                                            HStack(spacing: 12) {
                                                StatusIcon(status: job.status, size: 18)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(job.name).font(.subheadline.weight(.semibold))
                                                    Text("\(job.stage) · \(job.failureReason?.replacingOccurrences(of: "_", with: " ") ?? "失败")")
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Button { perform(.retry, on: job) } label: { Image(systemName: "arrow.clockwise") }
                                                    .buttonStyle(.borderless)
                                                    .accessibilityLabel("重试 \(job.name)")
                                            }
                                            .padding(14)
                                        }
                                        .buttonStyle(.plain)
                                        if job.id != failed.last?.id { Divider().padding(.leading, 44) }
                                    }
                                }
                                .glassCard(tint: Theme.color(for: .failed))
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            } else if let error = model.error {
                ErrorStateView(error: error) { await model.load(session.client) }
            } else {
                ProgressView().controlSize(.large).padding(.top, 120)
            }
        }
        .ambientBackground(model.pipeline.map { Theme.color(for: $0.status) } ?? Theme.orange)
        .navigationTitle("流水线 #\(String(pipelineID))")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let pipeline = model.pipeline {
                        if pipeline.status.canRetry {
                            Button { pipelineAction(.retry) } label: { Label("重试失败的作业", systemImage: "arrow.clockwise") }
                        }
                        if pipeline.status.canCancel {
                            Button(role: .destructive) { pipelineAction(.cancel) } label: { Label("取消流水线", systemImage: "stop.circle") }
                        }
                        if let url = pipeline.webUrl.flatMap(URL.init(string:)) {
                            Divider()
                            ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
                            Link(destination: url) { Label("在浏览器中打开", systemImage: "safari") }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(!session.account.canWrite || runner.isRunning)
            }
        }
        .actionErrors(runner)
        .refreshable { await model.load(session.client) }
        .task {
            await model.load(session.client)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if model.isActive { await model.load(session.client) }
            }
        }
    }

    private func summary(_ pipeline: Pipeline) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                StatusIcon(status: pipeline.status, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pipeline.status.title).font(.title2.weight(.bold)).foregroundStyle(Theme.color(for: pipeline.status))
                    if let name = pipeline.name { Text(name).font(.subheadline).lineLimit(2) }
                }
            }
            HStack(spacing: 8) {
                if let iid = pipeline.gitRef.mergeRequestIID {
                    NavigationLink(value: Route.mergeRequest(projectID: projectID, iid: iid)) { RefTag(ref: pipeline.ref) }
                        .buttonStyle(.plain)
                } else {
                    RefTag(ref: pipeline.ref)
                }
                if let sha = pipeline.sha {
                    NavigationLink(value: Route.commit(projectID: projectID, sha: sha)) {
                        Text(String(sha.prefix(8))).font(.caption.monospaced())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            HStack(spacing: 16) {
                if let user = pipeline.user {
                    HStack(spacing: 6) { Avatar(user: user, instance: session.instance, size: 20); Text(user.name).font(.caption) }
                }
                if !pipeline.sourceTitle.isEmpty { Meta(symbol: "bolt", text: pipeline.sourceTitle) }
                if let duration = pipeline.duration { Meta(symbol: "timer", text: duration.durationText) }
                if let date = pipeline.createdAt { Meta(symbol: "clock", text: date.relative) }
            }
            let jobs = model.stages.flatMap(\.jobs)
            if !jobs.isEmpty {
                let done = jobs.filter { $0.status.isFinished }.count
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(done), total: Double(jobs.count)).tint(Theme.color(for: pipeline.status))
                    Text("\(done)/\(jobs.count) 个作业已结束").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .glassCard(tint: Theme.color(for: pipeline.status))
    }

    private func pipelineAction(_ action: CIAction) {
        let client = session.client, project = projectID, id = pipelineID
        runner.run {
            model.pipeline = try await client.pipelineAction(project, id: id, action: action)
            await model.load(client)
        }
    }

    private func perform(_ action: CIAction, on job: Job) {
        let client = session.client, project = projectID
        runner.run {
            _ = try await client.jobAction(project, id: job.id, action: action)
            await model.load(client)
        }
    }
}

/// Horizontally scrolling stage columns with job cards, similar to GitLab's pipeline graph.
/// A single stage uses the full width instead of one narrow column.
struct StageGraph: View {
    let stages: [PipelineStage]
    let projectID: Int
    var onAction: (Job, CIAction) -> Void

    var body: some View {
        if stages.count == 1, let stage = stages.first {
            column(stage).frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                        column(stage).frame(width: 210, alignment: .topLeading)
                        if index < stages.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 26)
                                .padding(.top, 40)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func column(_ stage: PipelineStage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                StatusIcon(status: stage.status, size: 14)
                Text(stage.name).font(.subheadline.weight(.bold))
                Text("\(stage.jobs.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GlassGroup(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(stage.jobs) { job in
                        NavigationLink(value: Route.job(projectID: projectID, id: job.id)) {
                            JobCard(job: job, onAction: { onAction(job, $0) })
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if job.isManual { Button { onAction(job, .play) } label: { Label("运行", systemImage: "play.fill") } }
                            if job.status.canRetry { Button { onAction(job, .retry) } label: { Label("重试", systemImage: "arrow.clockwise") } }
                            if job.status.canCancel { Button(role: .destructive) { onAction(job, .cancel) } label: { Label("取消", systemImage: "stop.circle") } }
                        }
                    }
                }
            }
        }
    }
}

struct JobCard: View {
    let job: Job
    var onAction: (CIAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            StatusIcon(status: job.status, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Group {
                    if let duration = job.duration { Text(duration.durationText) }
                    else { Text(job.status.title) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if job.allowFailure == true && job.status == .failed {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).accessibilityLabel("允许失败")
            }
            if job.isManual {
                Button { onAction(.play) } label: { Image(systemName: "play.fill").font(.caption) }
                    .buttonStyle(.borderless).accessibilityLabel("运行 \(job.name)")
            } else if job.status == .failed || job.status == .canceled {
                Button { onAction(.retry) } label: { Image(systemName: "arrow.clockwise").font(.caption) }
                    .buttonStyle(.borderless).accessibilityLabel("重试 \(job.name)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, tint: job.status == .failed ? Theme.color(for: .failed) : nil, interactive: true)
    }
}
