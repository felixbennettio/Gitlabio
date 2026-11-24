import SwiftUI
import GitLabCore

struct MeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Session.self) private var session
    @State private var adding = false
    @State private var updatingToken: Account?
    @State private var removing: Account?
    @State private var version: ServerVersion?

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                HStack(spacing: 16) {
                    Avatar(user: session.me, instance: session.instance, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.me.name).font(.title3.weight(.bold))
                        Text(session.account.handle).font(.subheadline).foregroundStyle(.secondary)
                        Label(session.instance.displayName, systemImage: session.instance.isGitLabCom ? "globe" : "server.rack")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                if let version { LabeledContent("GitLab 版本", value: version.version) }
                if let scopes = session.account.scopes {
                    LabeledContent("令牌范围") { Text(scopes.joined(separator: ", ")).font(.caption.monospaced()) }
                    if !session.account.canWrite {
                        Label("当前令牌只读：评论、合并、提交和流水线控制不可用。", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if let expires = session.account.tokenExpiresAt { LabeledContent("令牌到期", value: expires) }
            }

            if session.isDemo {
                Section {
                    Label("你正在使用演示数据，所有更改都不会发送到任何服务器。", systemImage: "sparkles").font(.subheadline)
                    Button("退出演示") { model.endDemo() }.foregroundStyle(Theme.orange)
                }
            }

            Section("账户") {
                ForEach(model.accounts) { account in
                    Button { if account.id != session.account.id { model.activate(account) } } label: {
                        HStack(spacing: 12) {
                            Avatar(name: account.name, url: account.instance.resolve(account.avatarUrl), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name).foregroundStyle(.primary)
                                Text("\(account.handle) · \(account.instance.displayName)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if account.trust.isCustom { Image(systemName: "lock.shield").foregroundStyle(.secondary).accessibilityLabel("自定义证书信任") }
                            if account.id == session.account.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.orange) }
                        }
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button(role: .destructive) { removing = account } label: { Label("移除", systemImage: "trash") }
                        Button { updatingToken = account } label: { Label("更新令牌", systemImage: "key") }.tint(.blue)
                    }
                    .contextMenu {
                        Button { updatingToken = account } label: { Label("更新令牌", systemImage: "key") }
                        if account.trust.isCustom {
                            Button { model.updateTrust(.system, for: account) } label: { Label("移除自定义证书信任", systemImage: "lock.open") }
                        }
                        Button(role: .destructive) { removing = account } label: { Label("移除账户", systemImage: "trash") }
                    }
                }
                Button { adding = true } label: { Label("添加账户", systemImage: "plus.circle.fill") }
            }

            Section {
                Picker(selection: $model.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                } label: { Label("外观", systemImage: "circle.lefthalf.filled") }
                Toggle(isOn: Binding(get: { model.notificationsEnabled }, set: { enabled in
                    Task {
                        if enabled {
                            model.notificationsEnabled = await BackgroundRefresh.requestAuthorization()
                            if model.notificationsEnabled { BackgroundRefresh.schedule() }
                        } else {
                            model.notificationsEnabled = false
                            BackgroundRefresh.cancel()
                        }
                    }
                })) {
                    Label("待办通知", systemImage: "bell.badge")
                }
            } header: {
                Text("设置")
            } footer: {
                Text("GitLab 不向第三方应用推送通知。开启后，Gitlabio 会在系统允许时于后台检查待办，并发送本地通知；时间间隔由 iOS 决定。")
            }

            Section("关于") {
                LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"))")
                Label("Gitlabio 与 GitLab Inc. 无关联。GitLab 是 GitLab Inc. 的商标。", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .groupedList()
        .navigationTitle("我")
        .sheet(isPresented: $adding) { AddAccountView(preset: .selfManaged) }
        .sheet(item: $updatingToken) { account in AddAccountView(preset: .selfManaged, existing: account) }
        .confirmationDialog("移除账户「\(removing?.handle ?? "")」？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("移除并删除本机令牌", role: .destructive) { if let removing { model.remove(removing) }; removing = nil }
        } message: { Text("这只会删除本机保存的令牌，不会吊销 GitLab 上的令牌。") }
        .task { version = try? await session.client.version() }
    }
}
