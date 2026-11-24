import SwiftUI
import GitLabCore

// MARK: Avatars

struct Avatar: View {
    let name: String
    var url: URL?
    var size: CGFloat = 32
    var shape: AvatarShape = .circle

    enum AvatarShape { case circle, rounded }

    init(user: User?, instance: GitLabInstance?, size: CGFloat = 32) {
        self.name = user?.name ?? "?"
        self.url = instance?.resolve(user?.avatarUrl)
        self.size = size
    }

    init(name: String, url: URL? = nil, size: CGFloat = 32, shape: AvatarShape = .circle) {
        self.name = name
        self.url = url
        self.size = size
        self.shape = shape
    }

    var body: some View {
        let clip = shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        ZStack {
            placeholder
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(clip)
        .overlay { clip.stroke(.white.opacity(0.25), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        let color = Color.seeded(name)
        return ZStack {
            LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials).font(.system(size: size * 0.42, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "/" })
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String([a, b]).uppercased() }
        return String(name.prefix(1)).uppercased()
    }
}

struct AvatarStack: View {
    let users: [User]
    let instance: GitLabInstance?
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(users.prefix(4)) { user in
                Avatar(user: user, instance: instance, size: size)
                    .overlay(Circle().stroke(Color(white: 1, opacity: 0.9), lineWidth: 1.5))
            }
            if users.count > 4 {
                Text("+\(users.count - 4)").font(.caption2.bold()).padding(.leading, size * 0.4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(users.map(\.name).joined(separator: "、"))
    }
}

struct ProjectAvatar: View {
    let project: Project
    let instance: GitLabInstance?
    var size: CGFloat = 40

    var body: some View {
        Avatar(name: project.name, url: instance?.resolve(project.avatarUrl), size: size, shape: .rounded)
    }
}

// MARK: Status

struct StatusIcon: View {
    let status: CIStatus
    var size: CGFloat = 16
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: Theme.symbol(for: status))
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.color(for: status))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                guard status == .running, !reduceMotion else { return }
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { spin = true }
            }
            .accessibilityLabel(status.title)
    }
}

struct StatusPill: View {
    let status: CIStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            StatusIcon(status: status, size: compact ? 11 : 13)
            Text(status.title).font((compact ? Font.caption2 : .caption).weight(.semibold))
        }
        .foregroundStyle(Theme.color(for: status))
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 5)
        .background(Theme.color(for: status).opacity(0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Opened / merged / closed / draft badge for issues and merge requests.
struct StateBadge: View {
    let state: String
    var draft = false

    var body: some View {
        let (title, symbol, color): (String, String, Color) = {
            if draft && state == "opened" { return ("草稿", "pencil.circle.fill", .secondary) }
            switch state {
            case "opened": return ("打开", "circle.circle.fill", Theme.opened)
            case "merged": return ("已合并", "arrow.triangle.merge", Theme.merged)
            case "closed": return ("已关闭", "xmark.circle.fill", Theme.closed)
            case "locked": return ("已锁定", "lock.fill", .secondary)
            default: return (state, "circle", .secondary)
            }
        }()
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.gradient, in: Capsule())
    }
}

// MARK: Labels

struct LabelChip: View {
    let name: String
    var color: String?

    var body: some View {
        let tint = color.map(Color.init(hex:)) ?? .seeded(name)
        let parts = name.components(separatedBy: "::")
        if parts.count == 2 {
            HStack(spacing: 0) {
                Text(parts[0]).padding(.leading, 8).padding(.trailing, 5).foregroundStyle(.white).background(tint)
                Text(parts[1]).padding(.leading, 5).padding(.trailing, 8).foregroundStyle(tint)
            }
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 0)
            .frame(height: 20)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(tint, lineWidth: 1))
        } else {
            Text(name)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .foregroundStyle(tint)
                .background(tint.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
        }
    }
}

struct LabelRow: View {
    let labels: [String]
    var palette: [String: String] = [:]

    var body: some View {
        if !labels.isEmpty {
            FlowLayout(spacing: 5) {
                ForEach(labels, id: \.self) { LabelChip(name: $0, color: palette[$0]) }
            }
        }
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: Misc

struct Meta: View {
    let symbol: String
    let text: String
    var body: some View {
        Label { Text(text).lineLimit(1) } icon: { Image(systemName: symbol).imageScale(.small) }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

struct BranchTag: View {
    let name: String
    var body: some View {
        Label(name, systemImage: "arrow.triangle.branch")
            .font(.caption.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A pipeline or schedule ref: merge request refs read as `!12`, tags get a tag icon.
struct RefTag: View {
    let ref: String

    var body: some View {
        let git = GitRef(ref)
        let symbol = git.mergeRequestIID != nil ? "arrow.triangle.pull" : git.isTag ? "tag" : "arrow.triangle.branch"
        Label(git.mergeRequestIID.map { "合并请求 !\($0)" } ?? git.shortName, systemImage: symbol)
            .font(.caption.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A form row that opens a picker. Reads like a navigation row rather than a tinted button.
struct PickerRow: View {
    let title: String
    let value: String
    var monospaced = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text(value).font(monospaced ? .body.monospaced() : .body).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        // A list button tints its whole label; primary keeps .secondary/.tertiary grey.
        .tint(.primary)
    }
}

struct SectionTitle: View {
    let title: String
    var symbol: String?
    var count: Int?
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(Theme.orange) }
            Text(title).font(.title3.weight(.bold))
            if let count {
                Text("\(count)").font(.footnote.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyStateView: View {
    let title: String
    let symbol: String
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        }
    }
}

struct ErrorStateView: View {
    let error: Error
    var retry: (() async -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            if let retry {
                Button("重试") { Task { await retry() } }.buttonStyle(BrandButtonStyle())
            }
        }
    }
}

struct InlineError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .textSelection(.enabled)
    }
}

struct CountBadge: View {
    let count: Int
    var tint: Color = Theme.orange
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 18)
            .background(tint, in: Capsule())
    }
}

extension Date {
    var relative: String { formatted(.relative(presentation: .named)) }
}

extension Int {
    var durationText: String {
        let minutes = self / 60, seconds = self % 60
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分" }
        return minutes > 0 ? "\(minutes) 分 \(seconds) 秒" : "\(seconds) 秒"
    }
}

extension Double {
    var durationText: String { Int(self.rounded()).durationText }
}
