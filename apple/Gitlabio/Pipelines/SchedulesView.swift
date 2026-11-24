import SwiftUI
import GitLabCore

/// Pipeline schedules (GitLab's answer to a named, manually runnable workflow such as a nightly build).
struct PipelineSchedulesView: View {
    let project: Project
    @Environment(Session.self) private var session
    @State private var loader: PagedLoader<PipelineSchedule>?
    @State private var runner = ActionRunner()
    @State private var confirming: PipelineSchedule?
    @State private var startedTitle: String?

    var body: some View {
        List {
            if let startedTitle {
                Section {
                    NavigationLink(value: Route.pipelines(project)) {
                        Label("已开始运行「\(startedTitle)」，查看流水线", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.opened)
                    }
                }
            }
            if let loader {
                Section {
                    ForEach(loader.items) { schedule in
                        NavigationLink(value: Route.schedule(project, id: schedule.id)) { ScheduleRow(schedule: schedule) }
                            .swipeActions(edge: .trailing) {
                                if session.account.canWrite {
                                    Button { confirming = schedule } label: { Label("立即运行", systemImage: "play.fill") }.tint(Theme.orange)
                                }
                            }
                            .contextMenu {
                                if session.account.canWrite {
                                    Button { confirming = schedule } label: { Label("立即运行", systemImage: "play.fill") }
                                }
                            }
                            .task { await loader.loadMoreIfNeeded(schedule) }
                    }
                    PagingFooter(loader: loader)
                } footer: {
                    if !loader.items.isEmpty { Text("左滑可立即运行。立即运行不影响下一次计划时间。") }
                }
            }
        }
        .groupedList()
        .overlay {
            if let loader {
                PagedStateOverlay(loader: loader, emptyTitle: "没有流水线计划", emptySymbol: "calendar.badge.clock",
                                  emptyMessage: "在 GitLab 网页的「构建 → 流水线计划」里创建，比如每天凌晨的 nightly build；之后可以在这里随时运行。")
            }
        }
        .navigationTitle("流水线计划")
        .confirmationDialog("立即运行「\(confirming?.title ?? "")」？", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { schedule in
            Button("在 \(schedule.refName) 上运行") { play(schedule) }
            Button("取消", role: .cancel) {}
        } message: { _ in Text("会按计划里设置的分支、变量和输入创建一条新流水线。") }
        .actionErrors(runner)
        .refreshable { await loader?.refresh() }
        .task {
            guard loader == nil else { return }
            let client = session.client, id = project.id
            loader = PagedLoader { try await client.pipelineSchedules(id, page: $0) }
            await loader?.loadFirst()
        }
    }

    private func play(_ schedule: PipelineSchedule) {
        let client = session.client, id = project.id
        runner.run {
            try await client.playPipelineSchedule(id, id: schedule.id)
            startedTitle = schedule.title
        }
    }
}

struct ScheduleRow: View {
    let schedule: PipelineSchedule
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: schedule.active ? "calendar.badge.clock" : "calendar.badge.minus")
                .font(.title3)
                .foregroundStyle(schedule.active ? Theme.orange : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(schedule.title).font(.headline).lineLimit(2)
                    if !schedule.active {
                        Text("已停用").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    RefTag(ref: schedule.ref).layoutPriority(1)
                    if let cron = schedule.cron { Meta(symbol: "repeat", text: CronDescription.describe(cron)) }
                }
                HStack(spacing: 12) {
                    if schedule.active, let next = schedule.nextRunAt { Meta(symbol: "clock", text: "下次 \(next.relative)") }
                    if let owner = schedule.owner {
                        HStack(spacing: 4) {
                            Avatar(user: owner, instance: session.instance, size: 16)
                            Text(owner.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let status = schedule.lastPipeline?.status { StatusIcon(status: status, size: 18).padding(.top, 2) }
        }
        .padding(.vertical, 4)
        .opacity(schedule.active ? 1 : 0.7)
        .accessibilityElement(children: .combine)
    }
}

struct PipelineScheduleView: View {
    let project: Project
    let scheduleID: Int
    @Environment(Session.self) private var session
    @State private var loader: Loader<PipelineSchedule>?
    @State private var runner = ActionRunner()
    @State private var confirming = false
    @State private var started = false

    var body: some View {
        ZStack {
            Color.clear
            if let loader {
                LoadingContent(loader: loader) { content($0) }
            }
        }
        .ambientBackground()
        .navigationTitle(loader?.value?.title ?? "流水线计划")
        .inlineTitle()
        .actionErrors(runner)
        .confirmationDialog("立即运行这个计划？", isPresented: $confirming, titleVisibility: .visible) {
            Button("运行") { play() }
            Button("取消", role: .cancel) {}
        } message: { Text("不影响下一次计划时间。") }
        .onAppear {
            if loader == nil {
                let client = session.client, project = project.id, id = scheduleID
                loader = Loader { try await client.pipelineSchedule(project, id: id) }
            }
        }
    }

    private func content(_ schedule: PipelineSchedule) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.title).foregroundStyle(Theme.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(schedule.title).font(.title3.weight(.bold))
                            Text(schedule.active ? "已启用" : "已停用").font(.subheadline).foregroundStyle(schedule.active ? Theme.opened : .secondary)
                        }
                    }
                    RefTag(ref: schedule.ref)
                    if let cron = schedule.cron {
                        info("频率", "\(CronDescription.describe(cron))（\(schedule.cronTimezone ?? "UTC")）")
                        info("Cron", cron, monospaced: true)
                    }
                    if schedule.active, let next = schedule.nextRunAt {
                        info("下次运行", next.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let owner = schedule.owner { info("所有者", owner.name) }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(tint: Theme.orange)

                if session.account.canWrite {
                    Button { confirming = true } label: {
                        Label(started ? "已开始运行" : "立即运行", systemImage: started ? "checkmark" : "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())
                    .disabled(runner.isRunning)
                    .accessibilityIdentifier("play-schedule")
                    if started {
                        NavigationLink(value: Route.pipelines(project)) { Label("查看流水线", systemImage: "arrow.right.circle") }
                            .frame(maxWidth: .infinity)
                    }
                }

                if let last = schedule.lastPipeline {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "上次运行", symbol: "clock.arrow.circlepath")
                        NavigationLink(value: Route.pipeline(projectID: project.id, id: last.id)) {
                            HStack(spacing: 12) {
                                StatusIcon(status: last.status ?? .unknown, size: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("流水线 #\(String(last.id))").font(.headline)
                                    Text([last.status?.title, last.sha.map { String($0.prefix(8)) }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }

                let variables = schedule.variables ?? []
                let inputs = schedule.inputs ?? []
                if !inputs.isEmpty || !variables.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "运行参数", symbol: "slider.horizontal.3", count: inputs.count + variables.count)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(inputs, id: \.name) { input in parameter(input.name, input.value?.text ?? "", kind: "输入") }
                            ForEach(variables, id: \.key) { variable in
                                parameter(variable.key, variable.value ?? "", kind: variable.variableType == "file" ? "文件变量" : "变量")
                            }
                        }
                        .glassCard()
                    }
                } else if schedule.variables == nil {
                    Text("只有维护者和计划所有者能看到计划的变量和输入。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .refreshable { await loader?.load(force: true) }
    }

    private func info(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).font(monospaced ? .subheadline.monospaced() : .subheadline).textSelection(.enabled)
        }
    }

    private func parameter(_ key: String, _ value: String, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(key).font(.subheadline.monospaced().weight(.semibold))
                Spacer()
                Text(kind).font(.caption2).foregroundStyle(.secondary)
            }
            Text(value.isEmpty ? "（空）" : value).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func play() {
        let client = session.client, project = project.id, id = scheduleID
        runner.run {
            try await client.playPipelineSchedule(project, id: id)
            started = true
        }
    }
}
