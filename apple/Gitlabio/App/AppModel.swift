import Foundation
import Observation
import SwiftUI
import GitLabCore

/// The signed-in account and its API client. Views read it from the environment.
@MainActor @Observable
final class Session {
    let account: Account
    let client: GitLabClient
    var user: User?
    var todoCount = 0
    var isDemo: Bool
    /// Pending edits per project, committed together from the change basket. Not observed itself
    /// (baskets are created lazily during view updates); each basket is observable.
    @ObservationIgnored private var baskets: [Int: ChangeBasket] = [:]

    init(account: Account, client: GitLabClient, isDemo: Bool = false) {
        self.account = account
        self.client = client
        self.isDemo = isDemo
    }

    var instance: GitLabInstance { client.instance }
    var me: User { user ?? User(id: account.userID, username: account.username, name: account.name, avatarUrl: account.avatarUrl) }

    func basket(for project: Project) -> ChangeBasket {
        if let basket = baskets[project.id] { return basket }
        let basket = ChangeBasket(project: project)
        baskets[project.id] = basket
        return basket
    }

    func refreshTodoCount() async {
        if let page = try? await client.todos(page: 1) { todoCount = page.total ?? page.items.count }
    }
}

@MainActor @Observable
final class AppModel {
    private(set) var accounts: [Account] = []
    private(set) var session: Session?
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    var loadError: String?

    private let defaults: UserDefaults

    private enum Keys {
        static let accounts = "accounts.v2"
        static let active = "accounts.active"
        static let appearance = "appearance"
        static let notifications = "notifications.enabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        if let data = defaults.data(forKey: Keys.accounts) {
            do { accounts = try JSONDecoder().decode([Account].self, from: data) }
            catch { loadError = "账户列表已损坏，请重新添加账户。" }
        }
        let active = defaults.string(forKey: Keys.active).flatMap(UUID.init(uuidString:))
        if let account = accounts.first(where: { $0.id == active }) ?? accounts.first { activate(account) }
    }

    var activeAccount: Account? { session?.account }

    // MARK: Demo

    func startDemo() {
        let account = Account(id: UUID(), instance: DemoTransport.instance, userID: 1, username: "mira", name: "Mira Chen",
                              scopes: ["api"])
        session = Session(account: account, client: DemoTransport.client(), isDemo: true)
        Task { await session?.refreshTodoCount() }
    }

    func endDemo() {
        session = nil
        if let account = accounts.first { activate(account) }
    }

    // MARK: Accounts

    func activate(_ account: Account) {
        do {
            let token = try Keychain.token(for: account.id)
            let client = GitLabClient(instance: account.instance, token: token, trust: account.trust)
            session = Session(account: account, client: client)
            defaults.set(account.id.uuidString, forKey: Keys.active)
            loadError = nil
            Task { [weak self] in await self?.refreshActiveUser() }
        } catch {
            session = nil
            loadError = error.localizedDescription
        }
    }

    /// Verifies a token against the instance and stores the account (or updates an existing one).
    @discardableResult
    func signIn(instance: GitLabInstance, token: String, trust: TrustPolicy) async throws -> Account {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GitLabError.invalidInput("请填写访问令牌。") }
        let client = GitLabClient(instance: instance, token: token, trust: trust)
        let user = try await client.currentUser()
        let info = try? await client.tokenInfo()
        let existing = accounts.first { $0.instance == instance && $0.userID == user.id }
        let account = Account(id: existing?.id ?? UUID(), instance: instance, userID: user.id, username: user.username,
                              name: user.name, avatarUrl: user.avatarUrl, trust: trust, scopes: info?.scopes,
                              tokenExpiresAt: info?.expiresAt, addedAt: existing?.addedAt ?? Date())
        try Keychain.save(token, for: account.id)
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        persist()
        activate(account)
        return account
    }

    func remove(_ account: Account) {
        Keychain.delete(account.id)
        accounts.removeAll { $0.id == account.id }
        persist()
        if session?.account.id == account.id {
            session = nil
            defaults.removeObject(forKey: Keys.active)
            if let next = accounts.first { activate(next) }
        }
    }

    func updateTrust(_ trust: TrustPolicy, for account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].trust = trust
        persist()
        if session?.account.id == account.id { activate(accounts[index]) }
    }

    private func refreshActiveUser() async {
        guard let session, !session.isDemo else { return }
        do {
            let user = try await session.client.currentUser()
            session.user = user
            if let index = accounts.firstIndex(where: { $0.id == session.account.id }),
               accounts[index].name != user.name || accounts[index].avatarUrl != user.avatarUrl {
                accounts[index].name = user.name
                accounts[index].avatarUrl = user.avatarUrl
                persist()
            }
            await session.refreshTodoCount()
        } catch {
            // Offline or expired token: screens show their own errors.
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) { defaults.set(data, forKey: Keys.accounts) }
    }
}
