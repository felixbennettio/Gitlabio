import SwiftUI
import Observation
import GitLabCore

@MainActor @Observable
final class FileModel {
    enum Content { case text(String), image(Data), binary(Int), tooLarge(Int) }
    var file: RepositoryFile?
    var content: Content?
    var error: Error?

    func load(_ client: GitLabClient, project: Int, path: String, ref: String) async {
        do {
            let file = try await client.file(project, path: path, ref: ref)
            self.file = file
            let ext = (path as NSString).pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "ico"].contains(ext), let data = file.data {
                content = .image(data)
            } else {
                do { content = .text(try file.text()) }
                catch GitLabError.fileTooLarge { content = .tooLarge(file.size) }
                catch { content = .binary(file.size) }
            }
            self.error = nil
        } catch {
            self.error = error
        }
    }
}

struct FileView: View {
    let project: Project
    let ref: String
    let path: String

    @Environment(Session.self) private var session
    @State private var model = FileModel()
    @State private var wrap = false
    @State private var rendered = true
    @State private var editing = false
    @State private var confirmDelete = false

    private var name: String { (path as NSString).lastPathComponent }
    private var isMarkdown: Bool { ["md", "markdown"].contains((path as NSString).pathExtension.lowercased()) }

    var body: some View {
        let basket = session.basket(for: project)
        let staged = basket.change(for: path)
        Group {
            if let content = model.content {
                switch content {
                case .text(let original):
                    let text = staged?.text ?? original
                    if isMarkdown && rendered {
                        ScrollView {
                            MarkdownView(text: text, base: project.webUrl.flatMap { URL(string: $0 + "/-/raw/\(ref)/" + (path as NSString).deletingLastPathComponent + "/") })
                                .padding()
                        }
                    } else {
                        SourceCodeView(text: text, fileName: name, wrap: wrap)
                    }
                case .image(let data):
                    ScrollView([.horizontal, .vertical]) {
                        if let image = Image(data: data) {
                            image.resizable().scaledToFit().padding()
                        } else {
                            EmptyStateView(title: "无法预览图片", symbol: "photo")
                        }
                    }
                case .binary(let size):
                    EmptyStateView(title: "二进制文件", symbol: "doc.fill", message: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                case .tooLarge(let size):
                    EmptyStateView(title: "文件过大", symbol: "doc.badge.ellipsis",
                                   message: "\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))，超过应用内预览上限。")
                }
            } else if let error = model.error {
                ErrorStateView(error: error) { await model.load(session.client, project: project.id, path: path, ref: ref) }
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let staged {
                HStack(spacing: 8) {
                    Image(systemName: staged.symbol)
                    Text("已暂存（\(staged.title)），尚未提交").font(.footnote.weight(.semibold))
                    Spacer()
                    Button("撤销") { basket.discard(path) }.font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.orange)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glassCapsule(tint: Theme.orange)
                .padding(.horizontal).padding(.top, 6)
            }
        }
        .navigationTitle(name)
        .inlineTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if case .text = model.content, model.file != nil, staged?.kind != .delete {
                    Button { editing = true } label: { Label("编辑", systemImage: "square.and.pencil") }
                        .accessibilityIdentifier("edit-file")
                }
                Menu {
                    if isMarkdown {
                        Toggle(isOn: $rendered) { Label("渲染 Markdown", systemImage: "doc.richtext") }
                    }
                    Toggle(isOn: $wrap) { Label("自动换行", systemImage: "text.word.spacing") }
                    if case .text(let text) = model.content {
                        Button { Clipboard.copy(staged?.text ?? text); Haptics.success() } label: { Label("复制内容", systemImage: "doc.on.doc") }
                    }
                    Button { Clipboard.copy(path) } label: { Label("复制路径", systemImage: "link") }
                    NavigationLink(value: Route.commits(project, ref: ref, path: path)) {
                        Label("文件历史", systemImage: "clock.arrow.circlepath")
                    }
                    if let url = project.webUrl.flatMap({ URL(string: $0 + "/-/blob/\(ref)/\(path)") }) {
                        ShareLink(item: url) { Label("分享链接", systemImage: "square.and.arrow.up") }
                        Link(destination: url) { Label("在浏览器中打开", systemImage: "safari") }
                    }
                    if model.file != nil {
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label("删除文件…", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("将删除「\(name)」加入变更篮？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("加入删除", role: .destructive) {
                guard let file = model.file else { return }
                basket.stage(.init(path: path, kind: .delete, text: nil, original: try? file.text(), baseRef: ref, lastCommitId: file.lastCommitId))
            }
        } message: {
            Text("删除会和其他暂存的更改一起提交。")
        }
        .sheet(isPresented: $editing) {
            if let file = model.file, case .text(let original) = model.content {
                FileEditorView(project: project, ref: ref, path: path, original: original, initial: staged?.text ?? original,
                               lastCommitId: file.lastCommitId)
            }
        }
        .task { if model.content == nil { await model.load(session.client, project: project.id, path: path, ref: ref) } }
    }
}
