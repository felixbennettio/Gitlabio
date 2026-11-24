import SwiftUI
import GitLabCore

/// Every pushable screen. Each tab's NavigationStack resolves routes with `RouteView`.
enum Route: Hashable {
    case project(Project)
    case projectID(Int)
    case tree(Project, ref: String, path: String)
    case file(Project, ref: String, path: String)
    case commits(Project, ref: String, path: String = "")
    case commit(projectID: Int, sha: String)
    case branches(Project)
    case compare(Project, from: String, to: String)
    case mergeRequests(Project)
    case mergeRequest(projectID: Int, iid: Int)
    case issues(Project)
    case issue(projectID: Int, iid: Int)
    case pipelines(Project)
    case schedules(Project)
    case schedule(Project, id: Int)
    case pipeline(projectID: Int, id: Int)
    case job(projectID: Int, id: Int)
    case todos
    case myWork(WorkKind)

    enum WorkKind: String, Hashable { case reviews, assignedMergeRequests, assignedIssues, createdMergeRequests }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .project(let project): ProjectView(project: project)
        case .projectID(let id): ProjectLoaderView(projectID: id)
        case .tree(let project, let ref, let path): CodeBrowserView(project: project, ref: ref, path: path)
        case .file(let project, let ref, let path): FileView(project: project, ref: ref, path: path)
        case .commits(let project, let ref, let path): CommitsView(project: project, ref: ref, path: path)
        case .commit(let projectID, let sha): CommitDetailView(projectID: projectID, sha: sha)
        case .branches(let project): BranchesView(project: project)
        case .compare(let project, let from, let to): CompareView(project: project, from: from, to: to)
        case .mergeRequests(let project): MergeRequestsView(project: project)
        case .mergeRequest(let projectID, let iid): MergeRequestView(projectID: projectID, iid: iid)
        case .issues(let project): IssuesView(project: project)
        case .issue(let projectID, let iid): IssueView(projectID: projectID, iid: iid)
        case .pipelines(let project): PipelinesView(project: project)
        case .schedules(let project): PipelineSchedulesView(project: project)
        case .schedule(let project, let id): PipelineScheduleView(project: project, scheduleID: id)
        case .pipeline(let projectID, let id): PipelineView(projectID: projectID, pipelineID: id)
        case .job(let projectID, let id): JobLogView(projectID: projectID, jobID: id)
        case .todos: InboxView()
        case .myWork(let kind): MyWorkView(kind: kind)
        }
    }
}

extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }
}

/// Resolves a project by id before showing it (used from notifications, to-dos and search).
struct ProjectLoaderView: View {
    let projectID: Int
    @Environment(Session.self) private var session
    @State private var loader: Loader<Project>?

    var body: some View {
        // A ZStack with a permanent child, so onAppear fires before the loader exists.
        ZStack {
            Color.clear
            if let loader {
                LoadingContent(loader: loader) { ProjectView(project: $0) }
            }
        }
        .onAppear {
            if loader == nil {
                let client = session.client, id = projectID
                loader = Loader { try await client.project(id) }
            }
        }
    }
}
