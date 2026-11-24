import SwiftUI
import GitLabCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var adding: AddAccountView.Preset?
    @State private var appeared = false

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 28) {
                Spacer()
                AppMark(size: 112)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: 10) {
                    Text("Gitlabio").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("GitLab.com 与自建 GitLab 的原生客户端")
                        .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                GlassGroup(spacing: 10) {
                    VStack(alignment: .leading, spacing: 14) {
                        Feature(symbol: "arrow.triangle.pull", tint: Theme.purple, title: "审查合并请求", detail: "差异、行内评论、批准与合并")
                        Feature(symbol: "point.3.connected.trianglepath.dotted", tint: Theme.orange, title: "掌控 CI/CD", detail: "流水线图、实时日志、重试与手动作业")
                        Feature(symbol: "chevron.left.forwardslash.chevron.right", tint: Theme.mint, title: "浏览和编辑代码", detail: "语法高亮，多文件一次提交")
                        Feature(symbol: "lock.shield", tint: Theme.indigo, title: "自建实例", detail: "多账户、多实例，支持自签证书")
                    }
                    .padding(20)
                    .glassCard(cornerRadius: 28)
                }
                .padding(.horizontal)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                Spacer()
                VStack(spacing: 12) {
                    Button { adding = .gitlabCom } label: {
                        Label("连接 GitLab.com", systemImage: "globe").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())
                    .accessibilityIdentifier("connect-gitlab-com")
                    Button { adding = .selfManaged } label: {
                        Label("连接自建实例", systemImage: "server.rack").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle())
                    Button("先看看演示") { model.startDemo() }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                        .accessibilityIdentifier("start-demo")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                if let error = model.loadError { InlineError(message: error).padding(.horizontal) }
            }
            .frame(maxWidth: 560)
        }
        .sheet(item: $adding) { preset in AddAccountView(preset: preset) }
        .onAppear { withAnimation(.spring(duration: 0.8).delay(0.1)) { appeared = true } }
    }

    private struct Feature: View {
        let symbol: String
        let tint: Color
        let title: String
        let detail: String
        var body: some View {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The app icon artwork, shown on the welcome screen.
struct AppMark: View {
    var size: CGFloat = 96

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: Theme.orange.opacity(0.35), radius: size * 0.18, y: size * 0.08)
            .accessibilityHidden(true)
    }
}
