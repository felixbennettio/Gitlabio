import SwiftUI
import GitLabCore

struct SearchView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case projects = "项目", mergeRequests = "合并请求", issues = "Issue"
        var id: String { rawValue }
    }

    @Environment(Session.self) private var session
    @State private var text = ""
    @State private var scope: Scope = .projects
    @State private var projects: [Project] = []
    @State private var mergeRequests: [MergeRequest] = []
    @State private var issues: [Issue] = []
    @State private var searching = false
    @State private var error: Error?

    var body: some View {
        List {
            if text.trimmingCharacters(in: .whitespaces).count < 2 {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("搜索 \(session.instance.displayName)", systemImage: "magnifyingglass").font(.headline)
                        Text("在你能访问的项目、合并请求和 Issue 中查找。至少输入 2 个字符。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                switch scope {
                case .projects:
                    ForEach(projects) { project in NavigationLink(value: Route.project(project)) { ProjectRow(project: project) } }
                case .mergeRequests:
                    ForEach(mergeRequests) { mr in
                        NavigationLink(value: Route.mergeRequest(projectID: mr.projectId, iid: mr.iid)) { MergeRequestRow(mr: mr, showProject: true) }
                    }
                case .issues:
                    ForEach(issues) { issue in
                        NavigationLink(value: Route.issue(projectID: issue.projectId, iid: issue.iid)) { IssueRow(issue: issue, showProject: true) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if searching { ProgressView() }
            else if let error { ErrorStateView(error: error) }
            else if text.count >= 2 && isEmpty { ContentUnavailableView.search(text: text) }
        }
        .navigationTitle("搜索")
        .searchable(text: $text, prompt: "项目、合并请求、Issue")
        .searchScopes($scope) {
            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .task(id: "\(scope.rawValue)|\(text)") {
            let term = text.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                switch scope {
                case .projects: projects = try await session.client.projects(scope: .all, search: term).items
                case .mergeRequests: mergeRequests = try await session.client.searchMergeRequests(term).items
                case .issues: issues = try await session.client.searchIssues(term).items
                }
                error = nil
            } catch is CancellationError {
            } catch { self.error = error }
        }
    }

    private var isEmpty: Bool {
        switch scope {
        case .projects: return projects.isEmpty
        case .mergeRequests: return mergeRequests.isEmpty
        case .issues: return issues.isEmpty
        }
    }
}
