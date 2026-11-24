import Foundation
import Testing
@testable import GitLabCore

@Suite struct DiffParserTests {
    let diff = """
    @@ -10,4 +10,5 @@ func render()
     let a = 1
    -let b = 2
    +let b = 3
    +let c = 4
     return a
    \\ No newline at end of file
    @@ -40,2 +41,2 @@
    -old
    +new
    """

    @Test func parsesHunksAndLineNumbers() {
        let hunks = DiffParser.parse(diff)
        #expect(hunks.count == 2)
        #expect(hunks[0].section == "func render()")
        let lines = hunks[0].lines
        #expect(lines.map(\.kind) == [.context, .deletion, .addition, .addition, .context, .noNewline])
        #expect(lines[0].oldLine == 10 && lines[0].newLine == 10)
        #expect(lines[1].oldLine == 11 && lines[1].newLine == nil)
        #expect(lines[3].newLine == 12)
        #expect(lines[4].oldLine == 12 && lines[4].newLine == 13)
        #expect(hunks[1].lines[1].newLine == 41)
    }

    @Test func sideBySidePairsChanges() {
        let rows = DiffParser.sideBySide(DiffParser.parse(diff)[0])
        #expect(rows.count == 5)
        #expect(rows[1].left?.text == "let b = 2" && rows[1].right?.text == "let b = 3")
        #expect(rows[2].left == nil && rows[2].right?.text == "let c = 4")
    }

    @Test func countsLines() {
        let file = FileDiff(oldPath: "a", newPath: "a", diff: diff)
        #expect(file.lineCounts.additions == 3 && file.lineCounts.deletions == 2)
    }
}

@Suite struct JobLogTests {
    let esc = "\u{1B}"

    @Test func parsesColoursAndSections() {
        let text = """
        Running with gitlab-runner
        section_start:100:get_sources[collapsed=true]\r\(esc)[0K\(esc)[36;1mGetting source\(esc)[0;m
        Fetching \(esc)[32mok\(esc)[0m done
        section_end:107:get_sources\r\(esc)[0K
        \(esc)[31;1mERROR\(esc)[0m: failed
        """
        let log = JobLog(text)
        #expect(log.lines.count == 4)
        #expect(log.lines[1].opensSection == "get_sources")
        #expect(log.lines[1].plainText == "Getting source")
        #expect(log.lines[1].spans[0].style.foreground == 6 && log.lines[1].spans[0].style.bold)
        #expect(log.lines[2].section == "get_sources")
        #expect(log.lines[2].spans.map(\.text) == ["Fetching ", "ok", " done"])
        #expect(log.lines[2].spans[1].style.foreground == 2)
        #expect(log.lines[3].section == nil)
        #expect(log.lines[3].spans[0].style.foreground == 1)
        let section = try! #require(log.sections["get_sources"])
        #expect(section.collapsedByDefault && section.title == "Getting source" && section.duration == 7)
    }

    @Test func carriageReturnKeepsFinalRedraw() {
        let log = JobLog("progress 10%\rprogress 50%\rprogress 100%\n")
        #expect(log.lines.map(\.plainText) == ["progress 100%"])
    }

    @Test func extendedColours() {
        var style = JobLog.Style()
        JobLog.apply("38;5;208", to: &style)
        #expect(style.foreground == 208)
        JobLog.apply("0", to: &style)
        #expect(style.foreground == nil)
        JobLog.apply("92", to: &style)
        #expect(style.foreground == 10)
    }

    @Test func limitsLines() {
        let log = JobLog((1...50).map(String.init).joined(separator: "\n"), maxLines: 10)
        #expect(log.lines.count == 10 && log.lines.first?.plainText == "41")
    }
}

@Suite struct HighlighterTests {
    func kinds(_ tokens: [SyntaxHighlighter.Token]) -> [String: SyntaxHighlighter.Kind] {
        Dictionary(tokens.map { ($0.text, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    @Test func swift() {
        let lines = SyntaxHighlighter(fileName: "A.swift").highlight("let x = \"hi\" // note\n/* block\nmore */ func f(n: Int) { return 42 }")
        #expect(lines.count == 3)
        let first = kinds(lines[0])
        #expect(first["let"] == .keyword && first["\"hi\""] == .string && first["// note"] == .comment)
        #expect(lines[1].first?.kind == .comment)
        let third = kinds(lines[2])
        #expect(third["more */"] == .comment && third["func"] == .keyword && third["Int"] == .type && third["42"] == .number && third["f"] == .function)
    }

    @Test func yamlKeys() {
        let line = SyntaxHighlighter(fileName: ".gitlab-ci.yml").highlight("  stage: build # comment")[0]
        let map = kinds(line)
        #expect(map["stage"] == .attribute && map["# comment"] == .comment)
    }

    @Test func pythonTripleQuotes() {
        let lines = SyntaxHighlighter(fileName: "a.py").highlight("def f():\n    \"\"\"doc\n    more\"\"\"\n    return None")
        #expect(lines.count == 4)
        #expect(lines[1].last?.kind == .string && lines[2].first?.kind == .string)
        #expect(kinds(lines[3])["None"] == .keyword)
    }

    @Test func roundTripsText() {
        let source = "a\n\n  b = 'x' # y\n"
        let lines = SyntaxHighlighter(fileName: "x.sh").highlight(source)
        #expect(lines.map { $0.map(\.text).joined() }.joined(separator: "\n") == source)
    }

    @Test func languageDetection() {
        #expect(SyntaxHighlighter.language(for: "Dockerfile").name == "Dockerfile")
        #expect(SyntaxHighlighter.language(for: "main.go").name == "Go")
        #expect(SyntaxHighlighter.language(for: "README.md").name == "Markdown")
    }
}

@Suite struct MarkdownTests {
    @Test func blocks() {
        let blocks = Markdown.parse("""
        # Title

        Some **bold** text
        continues.

        - [x] done
        - [ ] todo
          wrapped
        1. one
        2. two

        ```swift
        let x = 1
        ```

        > quoted
        > more

        | a | b |
        |---|:-:|
        | 1 | 2 |

        ---
        ![shot](/uploads/x.png)
        <!-- hidden -->
        """)
        #expect(blocks.count == 9)
        #expect(blocks[0] == .heading(level: 1, text: "Title"))
        #expect(blocks[1] == .paragraph("Some **bold** text\ncontinues."))
        guard case .list(false, let items) = blocks[2] else { Issue.record("expected list"); return }
        #expect(items.map(\.checked) == [true, false] && items[1].text == "todo wrapped")
        guard case .list(true, let ordered) = blocks[3] else { Issue.record("expected ordered"); return }
        #expect(ordered.count == 2)
        #expect(blocks[4] == .code(language: "swift", text: "let x = 1"))
        #expect(blocks[5] == .quote("quoted\nmore"))
        #expect(blocks[6] == .table(header: ["a", "b"], rows: [["1", "2"]]))
        #expect(blocks[7] == .rule)
        #expect(blocks[8] == .image(alt: "shot", url: "/uploads/x.png"))
    }
}

@Suite struct TrustTests {
    @Test func rejectsGarbageCertificates() {
        #expect(CertificateSummary.parse(Data("not a certificate".utf8)).isEmpty)
        #expect(CertificateSummary.parse(Data("-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----".utf8)).isEmpty)
    }

    @Test func customPolicyNormalisesHostAndFingerprints() {
        let custom = TrustPolicy.CustomTrust(host: "Git.Example.COM", pinnedLeafSHA256: ["ABCD"])
        #expect(custom.host == "git.example.com" && custom.pinnedLeafSHA256 == ["abcd"])
        #expect(TrustPolicy.custom(custom).isCustom && !TrustPolicy.system.isCustom)
    }

    @Test func policyRoundTripsThroughJSON() throws {
        let policy = TrustPolicy.custom(.init(host: "h", anchors: [Data([1, 2])], pinnedLeafSHA256: ["aa"]))
        let decoded = try JSONDecoder().decode(TrustPolicy.self, from: JSONEncoder().encode(policy))
        #expect(decoded == policy)
    }
}

@Suite struct DemoTests {
    let client = DemoTransport.client(latency: .zero)

    @Test func coversMainScreens() async throws {
        let user = try await client.currentUser()
        #expect(user.username == "mira")
        let projects = try await client.projects()
        #expect(projects.items.count >= 5)
        let project = projects.items[0]
        let tree = try await client.tree(project.id, ref: "main")
        #expect(tree.items.first?.isDirectory == true)
        let readme = try await client.file(project.id, path: "README.md", ref: "main")
        #expect(try readme.text().contains("Aurora"))
        let mrs = try await client.mergeRequests(project: project.id)
        #expect(!mrs.items.isEmpty)
        let mr = try await client.mergeRequest(project.id, iid: mrs.items[0].iid)
        #expect(mr.headPipeline != nil)
        let discussions = try await client.discussions(project.id, kind: .mergeRequests, iid: mr.iid)
        #expect(discussions.items.contains { $0.position != nil })
        let diffs = try await client.mergeRequestDiffs(project.id, iid: mr.iid)
        #expect(diffs.items.contains { $0.newFile == true })
        let pipelines = try await client.pipelines(project.id)
        let jobs = try await client.pipelineJobs(project.id, pipeline: pipelines.items[0].id)
        #expect(PipelineStage.group(jobs).map(\.name) == ["build", "test", "deploy"])
        let trace = JobLog(try await client.jobTrace(project.id, id: jobs[0].id))
        #expect(!trace.sections.isEmpty)
        let todos = try await client.todos()
        #expect(todos.items.count == 5)
        let review = try await client.mergeRequests(filter: .reviewRequested, username: "mira")
        #expect(review.items.allSatisfy { $0.reviewers?.contains(user) == true })
    }

    @Test func nestedFilePathsResolve() async throws {
        let file = try await client.file(101, path: "Sources/Pipelines/PipelineGraph.swift", ref: "main")
        #expect(try file.text().contains("PipelineGraph"))
        await #expect(throws: GitLabError.notFound) { _ = try await client.file(101, path: "missing.txt", ref: "main") }
    }

    @Test func demoDiffsParse() async throws {
        let diffs = try await client.mergeRequestDiffs(101, iid: 318)
        for diff in diffs.items { #expect(!DiffParser.parse(diff.diff).isEmpty, "\(diff.newPath)") }
    }
}
