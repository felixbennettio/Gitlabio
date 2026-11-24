import Foundation
import Observation
import UserNotifications
import GitLabCore
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// GitLab does not push to third-party clients, so Gitlabio polls the to-do list in the
/// background (when iOS grants refresh time) and posts local notifications for new items.
enum BackgroundRefresh {
    static let identifier = "io.routeforge.gitlabio.refresh"
    private static let seenKey = "notifications.seenTodos"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func schedule() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    static func cancel() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        #endif
    }

    /// Fetches pending to-dos for every account and notifies about ones not seen before.
    static func run() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "notifications.enabled") else { return }
        schedule()
        guard let data = defaults.data(forKey: "accounts.v2"),
              let accounts = try? JSONDecoder().decode([Account].self, from: data) else { return }
        var seen = defaults.dictionary(forKey: seenKey) as? [String: [Int]] ?? [:]
        var total = 0
        for account in accounts {
            guard let token = try? Keychain.token(for: account.id) else { continue }
            let client = GitLabClient(instance: account.instance, token: token, trust: account.trust)
            guard let page = try? await client.todos() else { continue }
            total += page.total ?? page.items.count
            let key = account.id.uuidString
            let known = Set(seen[key] ?? [])
            let isFirstRun = seen[key] == nil
            for todo in page.items where !known.contains(todo.id) && !isFirstRun {
                await post(todo, account: account, multipleAccounts: accounts.count > 1)
            }
            seen[key] = page.items.map(\.id)
        }
        defaults.set(seen, forKey: seenKey)
        try? await UNUserNotificationCenter.current().setBadgeCount(total)
    }

    static func post(_ todo: Todo, account: Account, multipleAccounts: Bool) async {
        let content = UNMutableNotificationContent()
        let project = todo.project?.nameWithNamespace ?? todo.project?.name ?? ""
        content.title = "\(todo.author?.name ?? "GitLab") \(todo.actionDescription)"
        content.subtitle = multipleAccounts ? "\(project) · \(account.instance.displayName)" : project
        content.body = todo.target?.title ?? todo.body
        content.sound = .default
        content.threadIdentifier = "\(account.id.uuidString)-\(todo.project?.id ?? 0)"
        var info: [String: Any] = ["account": account.id.uuidString, "type": todo.targetType]
        if let projectID = todo.target?.projectId ?? todo.project?.id { info["project"] = projectID }
        if let iid = todo.target?.iid { info["iid"] = iid }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: "todo-\(account.id.uuidString)-\(todo.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Holds a route requested from outside the UI (a tapped notification).
@MainActor @Observable
final class DeepLinks {
    static let shared = DeepLinks()
    var pending: Route?
    var accountID: UUID?
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let project = info["project"] as? Int else { return }
        let iid = info["iid"] as? Int
        let type = info["type"] as? String
        let account = (info["account"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            DeepLinks.shared.accountID = account
            switch (type, iid) {
            case ("MergeRequest", let iid?): DeepLinks.shared.pending = .mergeRequest(projectID: project, iid: iid)
            case ("Issue", let iid?): DeepLinks.shared.pending = .issue(projectID: project, iid: iid)
            default: DeepLinks.shared.pending = .projectID(project)
            }
        }
    }
}
#endif
