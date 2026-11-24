import SwiftUI
import UniformTypeIdentifiers
import GitLabCore

struct AddAccountView: View {
    enum Preset: String, Identifiable {
        case gitlabCom, selfManaged
        var id: String { rawValue }
    }

    var preset: Preset = .gitlabCom
    /// When set, the sheet updates this account's token instead of adding a new one.
    var existing: Account?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var instanceText = ""
    @State private var token = ""
    @State private var trust: TrustPolicy = .system
    @State private var busy = false
    @State private var error: String?
    @State private var reviewing: GitLabInstance?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: preset == .gitlabCom && existing == nil ? "globe" : "server.rack")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(existing == nil ? "连接 GitLab" : "更新令牌").font(.headline)
                            Text("使用个人访问令牌登录。令牌只保存在本机钥匙串中，只会发送给你填写的实例。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("实例地址") {
                    TextField("https://gitlab.example.com", text: $instanceText)
                        .technicalInput(url: true)
                        .disabled(existing != nil)
                        .accessibilityIdentifier("instance-field")
                    if trust.isCustom {
                        Label("已信任此实例的自定义证书", systemImage: "checkmark.shield.fill").foregroundStyle(Theme.opened).font(.footnote)
                    }
                }

                Section {
                    SecureField("glpat-…", text: $token)
                        .technicalInput()
                        .accessibilityIdentifier("token-field")
                    Button {
                        if let url = tokenCreationURL { openURL(url) }
                    } label: {
                        Label("在 GitLab 中创建令牌", systemImage: "key.fill")
                    }
                    .disabled(tokenCreationURL == nil)
                } header: {
                    Text("个人访问令牌")
                } footer: {
                    Text("需要 `api` 范围才能评论、合并、提交和控制流水线；只浏览可使用 `read_api`。实际权限仍受你的项目角色和分支保护限制。")
                }

                if let error {
                    Section { InlineError(message: error).listRowInsets(EdgeInsets()) }
                }

                Section {
                    Button(action: connect) {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text(existing == nil ? "验证并连接" : "验证并更新").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || token.trimmingCharacters(in: .whitespaces).isEmpty || instanceText.isEmpty)
                    .accessibilityIdentifier("connect-button")
                }
            }
            .navigationTitle(existing == nil ? "添加账户" : "更新令牌")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { token = ""; dismiss() }.disabled(busy)
                }
            }
            .sheet(item: $reviewing) { instance in
                CertificateReviewView(instance: instance) { policy in
                    trust = policy
                    connect()
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear {
            if let existing {
                instanceText = existing.instance.url.absoluteString
                trust = existing.trust
            } else if instanceText.isEmpty {
                instanceText = preset == .gitlabCom ? "https://gitlab.com" : "https://"
            }
        }
    }

    private var tokenCreationURL: URL? {
        guard let instance = try? GitLabInstance(instanceText) else { return nil }
        return URL(string: instance.url.absoluteString + "/-/user_settings/personal_access_tokens?name=Gitlabio&scopes=api,read_user")
    }

    private func connect() {
        error = nil
        let instance: GitLabInstance
        do { instance = try GitLabInstance(instanceText) } catch { self.error = error.localizedDescription; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.signIn(instance: instance, token: token, trust: trust)
                token = ""
                Haptics.success()
                dismiss()
            } catch GitLabError.untrustedCertificate {
                reviewing = instance
            } catch {
                self.error = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

extension GitLabInstance: @retroactive Identifiable {
    public var id: URL { url }
}

/// Shows the server certificate so the user can verify its fingerprint before trusting it,
/// or import the organisation's CA certificate instead.
struct CertificateReviewView: View {
    let instance: GitLabInstance
    var onTrust: (TrustPolicy) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var result: CertificateProbe.Result?
    @State private var error: String?
    @State private var importing = false
    @State private var importedCA: [CertificateSummary] = []
    @State private var confirmed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("证书不受系统信任", systemImage: "exclamationmark.shield.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text("\(instance.host) 出示的证书无法通过系统验证。只有在你确认这是你自己或所在组织的服务器时才继续，并通过可信渠道（例如管理员）核对下方 SHA-256 指纹。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if let result {
                    Section("服务器证书链") {
                        ForEach(Array(result.chain.enumerated()), id: \.offset) { index, certificate in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(index == 0 ? "服务器证书" : "签发者 \(index)").font(.caption).foregroundStyle(.secondary)
                                Text(certificate.subject).font(.subheadline.weight(.semibold))
                                Text(certificate.formattedFingerprint)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if let leaf = result.chain.first {
                        Section {
                            Toggle("我已核对指纹与管理员提供的一致", isOn: $confirmed)
                            Button {
                                onTrust(.custom(.init(host: instance.host, pinnedLeafSHA256: [leaf.sha256])))
                                dismiss()
                            } label: {
                                Label("仅信任此服务器证书", systemImage: "pin.fill")
                            }
                            .disabled(!confirmed)
                        } footer: {
                            Text("固定后，只接受指纹完全一致的证书。服务器更换证书后需要重新确认。")
                        }
                    }
                } else if let error {
                    Section { InlineError(message: error) }
                } else {
                    Section { HStack { ProgressView(); Text("正在读取证书…").foregroundStyle(.secondary) } }
                }

                Section {
                    Button { importing = true } label: { Label("导入组织 CA 证书（.pem / .cer / .crt）", systemImage: "square.and.arrow.down") }
                    ForEach(importedCA) { certificate in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(certificate.subject).font(.subheadline.weight(.semibold))
                            Text(certificate.formattedFingerprint).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    if !importedCA.isEmpty {
                        Button {
                            onTrust(.custom(.init(host: instance.host, anchors: importedCA.map(\.der))))
                            dismiss()
                        } label: {
                            Label("使用这些 CA 验证 \(instance.host)", systemImage: "checkmark.shield")
                        }
                    }
                } header: {
                    Text("或导入 CA")
                } footer: {
                    Text("导入的 CA 只用于这一实例，仍会校验证书链和主机名。Gitlabio 不提供忽略证书错误的选项。")
                }
            }
            .navigationTitle("核对证书")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task {
                do { result = try await CertificateProbe.inspect(instance) }
                catch { self.error = "无法读取证书：\(error.localizedDescription)" }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.x509Certificate, .data, .text], allowsMultipleSelection: true) { outcome in
                guard case .success(let urls) = outcome else { return }
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) { importedCA += CertificateSummary.parse(data) }
                }
                if importedCA.isEmpty { error = "所选文件不是有效的证书。" }
            }
        }
    }
}
