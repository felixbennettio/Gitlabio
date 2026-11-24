import SwiftUI
import GitLabCore

struct PipelinesView: View {
    let project: Project
    @Environment(Session.self) private var session
    @State private var loader: PagedLoader<Pipeline>?
    @State private var status: CIStatus?
    @State private var ref = ""
    @State private var running = false
    @State private var choosingRef = false
    @State private var openedForScreenshot = false

    var body: some View {
        List {
            if let loader {
                ForEach(loader.items) { pipeline in
                    NavigationLink(value: Route.pipeline(projectID: project.id, id: pipeline.id)) { PipelineRow(pipeline: pipeline) }
                        .task { await loader.loadMoreIfNeeded(pipeline) }
                }
                PagingFooter(loader: loader)
            }
        }
        .listStyle(.plain)
        .overlay {
            if let loader {
                PagedStateOverlay(loader: loader, emptyTitle: "没有流水线", emptySymbol: "point.3.connected.trianglepath.dotted",
                                  emptyMessage: "推送提交或手动运行一次流水线。")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { choosingRef = true } label: {
                            Label(ref.isEmpty ? "所有分支" : ref, systemImage: "arrow.triangle.branch")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .glassCapsule(tint: ref.isEmpty ? nil : Theme.orange, interactive: true)
                        }
                        if !ref.isEmpty {
                            Button { ref = "" } label: { Image(systemName: "xmark").font(.caption.bold()).padding(9).glassCapsule(interactive: true) }
                        }
                        ForEach([CIStatus.running, .failed, .success, .manual], id: \.self) { item in
                            Button { withAnimation(.snappy) { status = status == item ? nil : item } } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: Theme.symbol(for: item)).foregroundStyle(Theme.color(for: item))
                                    Text(item.title)
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .glassCapsule(tint: status == item ? Theme.color(for: item) : nil, interactive: true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("流水线")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.schedules(project)) { Label("流水线计划", systemImage: "calendar.badge.clock") }
                    .accessibilityIdentifier("pipeline-schedules")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { running = true } label: { Label("运行流水线", systemImage: "play.fill") }
                    .disabled(!session.account.canWrite)
                    .accessibilityIdentifier("run-pipeline")
            }
        }
        .sheet(isPresented: $running) { RunPipelineView(project: project, initialRef: ref.isEmpty ? nil : ref) { _ in await loader?.refresh() } }
        .sheet(isPresented: $choosingRef) { RefPicker(project: project, selection: $ref) }
        .refreshable { await loader?.refresh() }
        .onAppear {
            // Screenshot route for the run form; only in demo mode.
            if session.isDemo, LaunchOptions.screen == "run-pipeline", !openedForScreenshot { openedForScreenshot = true; running = true }
        }
        .task(id: "\(status?.rawValue ?? "")|\(ref)") {
            let client = session.client, id = project.id, status = status, ref = ref
            let fetch: (Int) async throws -> Page<Pipeline> = { try await client.pipelines(id, ref: ref, status: status, page: $0) }
            if let loader { loader.replaceFetch(fetch) } else { loader = PagedLoader(fetch) }
            await loader?.loadFirst()
            // Keep the list fresh while something is running.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let loader, loader.items.contains(where: { $0.status.isActive }) else { continue }
                await loader.refresh()
            }
        }
    }
}

struct PipelineRow: View {
    let pipeline: Pipeline
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(status: pipeline.status, size: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("#\(String(pipeline.id))").font(.headline.monospacedDigit())
                    StatusPill(status: pipeline.status, compact: true)
                    Spacer(minLength: 0)
                    if let date = pipeline.createdAt { Text(date.relative).font(.caption).foregroundStyle(.secondary) }
                }
                if let name = pipeline.name { Text(name).font(.subheadline).lineLimit(2) }
                HStack(spacing: 8) {
                    RefTag(ref: pipeline.ref)
                    if let sha = pipeline.sha { Text(String(sha.prefix(8))).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                HStack(spacing: 12) {
                    if let user = pipeline.user {
                        HStack(spacing: 4) { Avatar(user: user, instance: session.instance, size: 16); Text(user.name).font(.caption).foregroundStyle(.secondary) }
                    }
                    if !pipeline.sourceTitle.isEmpty { Meta(symbol: "bolt", text: pipeline.sourceTitle) }
                    if let duration = pipeline.duration { Meta(symbol: "timer", text: duration.durationText) }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
