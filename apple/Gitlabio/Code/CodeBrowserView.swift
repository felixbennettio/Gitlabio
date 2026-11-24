import SwiftUI
import GitLabCore

struct CodeBrowserView: View {
    let project: Project
    @State var ref: String
    let path: String

    @Environment(Session.self) private var session
    @State private var loader: PagedLoader<TreeEntry>?
    @State private var choosingRef = false
    @State private var showingBasket = false
    @State private var creatingFile = false

    init(project: Project, ref: String, path: String) {
        self.project = project
        self._ref = State(initialValue: ref)
        self.path = path
    }

    var body: some View {
        let basket = session.basket(for: project)
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Button { choosingRef = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(ref).font(.subheadline.monospaced().weight(.semibold)).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .glassCapsule(tint: Theme.orange, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换分支，当前 \(ref)")
                    if !path.isEmpty { Breadcrumbs(project: project, ref: ref, path: path) }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            if let loader {
                Section {
                    if !path.isEmpty {
                        let parent = (path as NSString).deletingLastPathComponent
                        NavigationLink(value: Route.tree(project, ref: ref, path: parent)) {
                            Label("..", systemImage: "arrow.turn.left.up").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(loader.items) { entry in
                        entryRow(entry, basket: basket)
                            .task { await loader.loadMoreIfNeeded(entry) }
                    }
                    PagingFooter(loader: loader)
                }
            }
        }
        .groupedList()
        .overlay {
            if let loader {
                PagedStateOverlay(loader: loader, emptyTitle: "空目录", emptySymbol: "folder",
                                  emptyMessage: project.emptyRepo == true ? "这个仓库还没有任何提交。" : nil)
            }
        }
        .navigationTitle(path.isEmpty ? project.name : (path as NSString).lastPathComponent)
        .inlineTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button { creatingFile = true } label: { Label("新建文件", systemImage: "doc.badge.plus") }
                    NavigationLink(value: Route.commits(project, ref: ref, path: path)) {
                        Label(path.isEmpty ? "提交历史" : "此目录的历史", systemImage: "clock.arrow.circlepath")
                    }
                    if let url = project.webUrl.flatMap({ URL(string: $0 + "/-/tree/\(ref)/\(path)") }) {
                        Link(destination: url) { Label("在浏览器中打开", systemImage: "safari") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                if !basket.isEmpty {
                    Button { showingBasket = true } label: {
                        Label("\(basket.count) 项更改", systemImage: "tray.full.fill")
                    }
                    .badge(basket.count)
                    .accessibilityIdentifier("basket-button")
                }
            }
        }
        .sheet(isPresented: $choosingRef) { RefPicker(project: project, selection: $ref) }
        .sheet(isPresented: $showingBasket) { ChangeBasketView(basket: basket) }
        .sheet(isPresented: $creatingFile) { NewFileView(project: project, ref: ref, directory: path) }
        .refreshable { await loader?.refresh() }
        .task(id: ref) {
            let client = session.client, id = project.id, ref = ref, path = path
            let fetch: (Int) async throws -> Page<TreeEntry> = { try await client.tree(id, ref: ref, path: path, page: $0) }
            if let loader { loader.replaceFetch(fetch) } else { loader = PagedLoader(fetch) }
            await loader?.loadFirst()
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: TreeEntry, basket: ChangeBasket) -> some View {
        if entry.isDirectory {
            NavigationLink(value: Route.tree(project, ref: ref, path: entry.path)) {
                Label { Text(entry.name) } icon: { Image(systemName: "folder.fill").foregroundStyle(Theme.indigo) }
            }
        } else if entry.isSubmodule {
            Label { Text(entry.name).foregroundStyle(.secondary) } icon: { Image(systemName: "shippingbox").foregroundStyle(.secondary) }
        } else {
            NavigationLink(value: Route.file(project, ref: ref, path: entry.path)) {
                HStack {
                    Label { Text(entry.name) } icon: { FileIcon(name: entry.name) }
                    if let change = basket.change(for: entry.path) {
                        Spacer()
                        Image(systemName: change.symbol).foregroundStyle(Theme.orange).accessibilityLabel("已暂存：\(change.title)")
                    }
                }
            }
        }
    }
}

struct FileIcon: View {
    let name: String
    var body: some View {
        let (symbol, color) = Self.style(for: name)
        Image(systemName: symbol).foregroundStyle(color)
    }

    static func style(for name: String) -> (String, Color) {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        if lower.hasPrefix("readme") { return ("book.closed.fill", Theme.orange) }
        if lower == ".gitlab-ci.yml" { return ("point.3.connected.trianglepath.dotted", Theme.orange) }
        if lower.hasPrefix("license") || lower.hasPrefix("licence") { return ("checkmark.seal.fill", Theme.mint) }
        if lower == "dockerfile" { return ("shippingbox.fill", .blue) }
        switch ext {
        case "swift": return ("swift", Color(hex: "#F05138"))
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "ico": return ("photo.fill", .pink)
        case "md", "markdown", "txt", "rst": return ("doc.text.fill", .secondary)
        case "json", "yml", "yaml", "toml", "plist", "xml", "ini": return ("curlybraces", Theme.purple)
        case "zip", "gz", "tar", "jar", "aar", "ipa", "apk": return ("doc.zipper", .brown)
        case "sh", "bash", "zsh": return ("terminal.fill", .green)
        case "pdf": return ("doc.richtext.fill", .red)
        default: return ("doc.fill", .secondary)
        }
    }
}

struct Breadcrumbs: View {
    let project: Project
    let ref: String
    let path: String

    var body: some View {
        let parts = path.split(separator: "/").map(String.init)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                NavigationLink(value: Route.tree(project, ref: ref, path: "")) {
                    Image(systemName: "house.fill").font(.caption)
                }
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    let prefix = parts[0...index].joined(separator: "/")
                    if index == parts.count - 1 {
                        Text(part).font(.caption.weight(.semibold))
                    } else {
                        NavigationLink(value: Route.tree(project, ref: ref, path: prefix)) { Text(part).font(.caption) }
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

/// Branch / tag picker sheet.
struct RefPicker: View {
    let project: Project
    @Binding var selection: String
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var branches: PagedLoader<Branch>?
    @State private var tags: [Tag] = []

    var body: some View {
        NavigationStack {
            List {
                if let branches {
                    Section("分支") {
                        ForEach(branches.items) { branch in
                            Button { selection = branch.name; dismiss() } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(branch.name).font(.body.monospaced()).foregroundStyle(.primary)
                                            if branch.isDefault { Text("默认").font(.caption2.bold()).foregroundStyle(Theme.orange) }
                                            if branch.isProtected { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                                        }
                                        if let commit = branch.commit {
                                            Text(commit.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if branch.name == selection { Image(systemName: "checkmark").foregroundStyle(Theme.orange) }
                                }
                            }
                            .tint(.primary)
                            .task { await branches.loadMoreIfNeeded(branch) }
                        }
                    }
                }
                if !tags.isEmpty && search.isEmpty {
                    Section("标签") {
                        ForEach(tags) { tag in
                            Button { selection = tag.name; dismiss() } label: {
                                HStack {
                                    Label(tag.name, systemImage: "tag").foregroundStyle(.primary)
                                    Spacer()
                                    if tag.name == selection { Image(systemName: "checkmark").foregroundStyle(Theme.orange) }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索分支")
            .navigationTitle("切换分支或标签")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: search) {
                let client = session.client, id = project.id, term = search
                let fetch: (Int) async throws -> Page<Branch> = { try await client.branches(id, search: term, page: $0) }
                if let branches { branches.replaceFetch(fetch) } else { branches = PagedLoader(fetch) }
                await branches?.loadFirst()
                if tags.isEmpty { tags = (try? await client.tags(id).items) ?? [] }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
