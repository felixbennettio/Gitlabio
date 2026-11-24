import SwiftUI
import Observation
import GitLabCore

@MainActor @Observable
final class JobLogModel {
    let projectID: Int
    var jobID: Int
    var job: Job?
    var log: JobLog?
    var rawSize = 0
    var error: Error?

    init(projectID: Int, jobID: Int) {
        self.projectID = projectID
        self.jobID = jobID
    }

    func load(_ client: GitLabClient) async {
        do {
            async let job = client.job(projectID, id: jobID)
            async let trace = client.jobTrace(projectID, id: jobID)
            self.job = try await job
            let data = (try? await trace) ?? Data()
            if data.count != rawSize || log == nil {
                rawSize = data.count
                log = JobLog(data)
            }
            error = nil
        } catch { if job == nil { self.error = error } }
    }
}

struct JobLogView: View {
    let projectID: Int
    let jobID: Int
    @Environment(Session.self) private var session
    @State private var model: JobLogModel
    @State private var collapsed: Set<String> = []
    @State private var follow = true
    @State private var search = ""
    @State private var runner = ActionRunner()

    init(projectID: Int, jobID: Int) {
        self.projectID = projectID
        self.jobID = jobID
        _model = State(initialValue: JobLogModel(projectID: projectID, jobID: jobID))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let job = model.job { header(job) }
            if let log = model.log {
                terminal(log)
            } else if let error = model.error {
                ErrorStateView(error: error) { await model.load(session.client) }
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
        .environment(\.colorScheme, .dark)
        .navigationTitle(model.job?.name ?? "作业")
        .inlineTitle()
        .searchable(text: $search, prompt: "在日志中查找")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let job = model.job {
                    if job.isManual {
                        Button { act(.play) } label: { Label("运行", systemImage: "play.fill") }
                    } else if job.status.canCancel {
                        Button { act(.cancel) } label: { Label("取消", systemImage: "stop.fill") }
                    } else if job.status.canRetry {
                        Button { act(.retry) } label: { Label("重试", systemImage: "arrow.clockwise") }
                            .accessibilityIdentifier("retry-job")
                    }
                }
                Menu {
                    Toggle(isOn: $follow) { Label("跟随最新输出", systemImage: "arrow.down.to.line") }
                    if let log = model.log {
                        Button { collapsed = Set(log.sections.keys) } label: { Label("折叠所有段落", systemImage: "rectangle.compress.vertical") }
                        Button { collapsed = [] } label: { Label("展开所有段落", systemImage: "rectangle.expand.vertical") }
                        Button { Clipboard.copy(log.lines.map(\.plainText).joined(separator: "\n")) } label: { Label("复制日志", systemImage: "doc.on.doc") }
                    }
                    if let url = model.job?.webUrl.flatMap(URL.init(string:)) {
                        Link(destination: url) { Label("在浏览器中打开", systemImage: "safari") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .actionErrors(runner)
        .task {
            await model.load(session.client)
            if let log = model.log, collapsed.isEmpty {
                collapsed = Set(log.sections.values.filter(\.collapsedByDefault).map(\.id))
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if model.job?.status.isActive == true { await model.load(session.client) }
            }
        }
    }

    private func act(_ action: CIAction) {
        let client = session.client, project = projectID, id = model.jobID
        runner.run {
            let job = try await client.jobAction(project, id: id, action: action)
            // Retrying creates a new job; follow it.
            if action == .retry, job.id != id {
                model.jobID = job.id
                model.job = job
                model.log = nil
                model.rawSize = 0
            }
            await model.load(client)
        }
    }

    private func header(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                StatusPill(status: job.status)
                Text(job.stage).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let duration = job.duration { Meta(symbol: "timer", text: duration.durationText) }
            }
            HStack(spacing: 12) {
                if let runner = job.runner?.description { Meta(symbol: "cpu", text: runner) }
                if let tags = job.tagList, !tags.isEmpty { Meta(symbol: "tag", text: tags.joined(separator: ", ")) }
                if let ref = job.ref { Meta(symbol: "arrow.triangle.branch", text: ref) }
            }
            if let reason = job.failureReason, job.status == .failed {
                Label(reason.replacingOccurrences(of: "_", with: " "), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.color(for: .failed))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCard(cornerRadius: 18, tint: Theme.color(for: job.status))
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
    }

    private func visibleLines(_ log: JobLog) -> [JobLog.Line] {
        if !search.isEmpty {
            return log.lines.filter { $0.plainText.localizedCaseInsensitiveContains(search) }
        }
        return log.lines.filter { line in
            guard let section = line.section, collapsed.contains(section) else { return true }
            return line.opensSection == section
        }
    }

    private func terminal(_ log: JobLog) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines(log)) { line in
                        LogLineView(line: line, section: line.opensSection.flatMap { log.sections[$0] },
                                    collapsed: line.opensSection.map(collapsed.contains) ?? false) {
                            guard let section = line.opensSection else { return }
                            withAnimation(.snappy) {
                                if collapsed.contains(section) { collapsed.remove(section) } else { collapsed.insert(section) }
                            }
                        }
                        .id(line.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .onChange(of: model.rawSize) {
                if follow && model.job?.status.isActive == true { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onAppear {
                if follow && model.job?.status.isActive == true { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

struct LogLineView: View {
    let line: JobLog.Line
    let section: JobLog.Section?
    let collapsed: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(line.id + 1)")
                .foregroundStyle(Color(white: 0.4))
                .frame(width: 44, alignment: .trailing)
            if section != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(white: 0.6))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10)
            }
            styled.fixedSize(horizontal: true, vertical: false)
            if let duration = section?.duration {
                Text(Int(duration).durationText)
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color(white: 0.2), in: Capsule())
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(section != nil ? Color.white.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if section != nil { toggle() } }
    }

    private var styled: Text {
        if line.spans.isEmpty { return Text(" ") }
        return line.spans.reduce(Text("")) { text, span in
            var piece = Text(span.text).foregroundColor(span.style.foreground.map(Theme.terminal) ?? Color(white: 0.88))
            if span.style.bold { piece = piece.bold() }
            if span.style.italic { piece = piece.italic() }
            if span.style.underline { piece = piece.underline() }
            return text + piece
        }
    }
}
