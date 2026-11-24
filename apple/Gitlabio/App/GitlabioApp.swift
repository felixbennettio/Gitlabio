import SwiftUI
import GitLabCore

@main
struct GitlabioApp: App {
    @State private var model = AppModel()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif

    init() {
        if LaunchOptions.demo { _model = State(initialValue: Self.demoModel()) }
    }

    private static func demoModel() -> AppModel {
        let model = AppModel(defaults: UserDefaults(suiteName: "gitlabio.demo") ?? .standard)
        model.startDemo()
        if let appearance = LaunchOptions.appearance { model.appearance = appearance }
        return model
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.appearance.colorScheme)
                .tint(Theme.orange)
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        #endif
    }
}

/// Launch arguments used by demo mode and the UI screenshot tests.
enum LaunchOptions {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var demo: Bool { arguments.contains("-GitlabioDemo") }
    static func value(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    static var appearance: AppearancePreference? { value("-GitlabioAppearance").flatMap(AppearancePreference.init(rawValue:)) }
    /// Screen to open directly, e.g. `mr`, `pipeline`, `job`, `file`.
    static var screen: String? { value("-GitlabioScreen") }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    private let links = DeepLinks.shared

    var body: some View {
        Group {
            if let session = model.session {
                MainTabs()
                    .environment(session)
                    .id(session.account.id)
            } else {
                OnboardingView()
            }
        }
        .animation(.smooth, value: model.session?.account.id)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, model.notificationsEnabled { BackgroundRefresh.schedule() }
        }
        .onChange(of: links.accountID) { _, id in
            // A notification for another account switches to it first.
            if let id, id != model.activeAccount?.id, let account = model.accounts.first(where: { $0.id == id }) {
                model.activate(account)
            }
        }
    }
}

enum AppTab: Hashable { case home, projects, inbox, me, search }

struct MainTabs: View {
    @Environment(Session.self) private var session
    @State private var tab: AppTab = .home
    @State private var homePath: [Route] = []
    @State private var projectsPath: [Route] = []
    @State private var inboxPath: [Route] = []
    @State private var searchPath: [Route] = []

    var body: some View {
        TabView(selection: $tab) {
            Tab("首页", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $homePath) { HomeView().routeDestinations() }
            }
            Tab("项目", systemImage: "square.stack.3d.up.fill", value: AppTab.projects) {
                NavigationStack(path: $projectsPath) { ProjectsView().routeDestinations() }
            }
            Tab("待办", systemImage: "tray.full.fill", value: AppTab.inbox) {
                NavigationStack(path: $inboxPath) { InboxView().routeDestinations() }
            }
            .badge(session.todoCount)
            Tab("我", systemImage: "person.crop.circle.fill", value: AppTab.me) {
                NavigationStack { MeView().routeDestinations() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) { SearchView().routeDestinations() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(MinimizingTabBar())
        .onAppear(perform: applyScreenshotRoute)
        .onAppear(perform: openPendingLink)
        .onChange(of: DeepLinks.shared.pending) { _, _ in openPendingLink() }
    }

    private func openPendingLink() {
        let links = DeepLinks.shared
        guard let route = links.pending, links.accountID == nil || links.accountID == session.account.id else { return }
        links.pending = nil
        links.accountID = nil
        tab = .inbox
        inboxPath.append(route)
    }

    /// Deep-links straight to a screen for demo screenshots.
    private func applyScreenshotRoute() {
        guard session.isDemo, let screen = LaunchOptions.screen else { return }
        var project = Project(id: 101, name: "Mobile App", pathWithNamespace: "aurora/mobile-app",
                              description: "Aurora 的 iOS 与 Android 客户端：SwiftUI、Compose 与共享设计令牌。")
        project.webUrl = "https://gitlab.demo.invalid/aurora/mobile-app"
        project.readmeUrl = "https://gitlab.demo.invalid/aurora/mobile-app/-/blob/main/README.md"
        switch screen {
        case "projects": tab = .projects
        case "inbox": tab = .inbox
        case "me": tab = .me
        case "search": tab = .search
        case "project": tab = .projects; projectsPath = [.projectID(101)]
        case "code": tab = .projects; projectsPath = [.tree(project, ref: "main", path: "")]
        case "file": tab = .projects; projectsPath = [.file(project, ref: "main", path: "Sources/Pipelines/PipelineGraph.swift")]
        case "readme": tab = .projects; projectsPath = [.file(project, ref: "main", path: "README.md")]
        case "mrs": tab = .projects; projectsPath = [.mergeRequests(project)]
        case "mr", "mr-discussion", "mr-changes", "mr-commits", "mr-pipelines":
            tab = .home; homePath = [.mergeRequest(projectID: 101, iid: 318)]
        case "issue": tab = .home; homePath = [.issue(projectID: 101, iid: 42)]
        case "pipelines": tab = .projects; projectsPath = [.pipelines(project)]
        case "pipeline": tab = .projects; projectsPath = [.pipeline(projectID: 101, id: 4125)]
        case "job": tab = .projects; projectsPath = [.job(projectID: 101, id: 41254)]
        case "commit": tab = .projects; projectsPath = [.commit(projectID: 101, sha: "3fa9c210")]
        case "branches": tab = .projects; projectsPath = [.branches(project)]
        case "schedules": tab = .projects; projectsPath = [.schedules(project)]
        case "schedule": tab = .projects; projectsPath = [.schedule(project, id: 11)]
        case "run-pipeline": tab = .projects; projectsPath = [.pipelines(project)]
        default: break
        }
    }
}

private struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
