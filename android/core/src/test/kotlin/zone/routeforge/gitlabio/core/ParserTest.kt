package zone.routeforge.gitlabio.core

import org.junit.Test
import kotlin.test.*

class AnsiParserTest {
    @Test fun keepsColorsAndDropsOtherSequences() {
        val lines = AnsiParser.parse("\u001B[0K\u001B[32;1mok\u001B[0m plain\n\u001B[31mred\u001B[39m\u001B[2K tail\n")
        assertEquals(listOf("ok plain", "red tail"), lines.map { it.text })
        val ok = lines[0].spans.single()
        assertEquals(0 to 2, ok.start to ok.end)
        assertEquals(AnsiColor(2), ok.style.foreground)
        assertTrue(ok.style.bold)
        assertEquals(AnsiColor(1), lines[1].spans.single().style.foreground)
    }

    @Test fun stylesCarryAcrossLinesUntilReset() {
        val lines = AnsiParser.parse("\u001B[33mone\ntwo\u001B[0m\nthree")
        assertEquals(AnsiColor(3), lines[1].spans.single().style.foreground)
        assertTrue(lines[2].spans.isEmpty())
    }

    @Test fun extendedColors() {
        assertEquals(AnsiColor(208), AnsiParser.apply(AnsiStyle(), "38;5;208").foreground)
        assertEquals(AnsiColor(0x102030, rgb = true), AnsiParser.apply(AnsiStyle(), "38;2;16;32;48").foreground)
        val combined = AnsiParser.apply(AnsiStyle(), "1;48;5;4;97")
        assertEquals(AnsiColor(4), combined.background)
        assertEquals(AnsiColor(15), combined.foreground)
        assertTrue(combined.bold)
        assertNull(AnsiParser.apply(AnsiStyle(), "38;2;1").foreground)
    }

    @Test fun gitlabSectionsAndCarriageReturns() {
        val lines = AnsiParser.parse("section_start:1730000000:get_sources\r\u001B[0K\u001B[36;1mGetting source\u001B[0;m\nprogress 10%\rprogress 100%\nsection_end:1730000001:get_sources\r\u001B[0K\n")
        assertEquals("get_sources", lines[0].section)
        assertEquals("Getting source", lines[0].text)
        assertEquals("progress 100%", lines[1].text)
        assertEquals("", lines[2].text)
    }

    @Test fun truncatedEscapeIsIgnored() {
        assertEquals("abc", AnsiParser.parse("abc\u001B[3").single().text)
    }
}

class DiffParserTest {
    @Test fun numbersLinesPerHunk() {
        val lines = DiffParser.parse("@@ -10,3 +10,4 @@ fun a()\n ctx\n-old\n+new\n+added\n ctx2\n\\ No newline at end of file\n@@ -40 +41 @@\n-x\n")
        assertEquals(DiffLineKind.HUNK, lines[0].kind)
        assertEquals(DiffLine(DiffLineKind.CONTEXT, "ctx", 10, 10), lines[1])
        assertEquals(DiffLine(DiffLineKind.REMOVED, "old", 11, null), lines[2])
        assertEquals(DiffLine(DiffLineKind.ADDED, "new", null, 11), lines[3])
        assertEquals(DiffLine(DiffLineKind.ADDED, "added", null, 12), lines[4])
        assertEquals(DiffLine(DiffLineKind.CONTEXT, "ctx2", 12, 13), lines[5])
        assertEquals(DiffLineKind.META, lines[6].kind)
        assertEquals(DiffLine(DiffLineKind.REMOVED, "x", 40, null), lines[8])
        assertEquals(3 to 2, DiffParser.stats("@@ -10,3 +10,4 @@ fun a()\n ctx\n-old\n+new\n+added\n ctx2\n@@ -40 +41 @@\n-x\n+y\n"))
    }

    @Test fun emptyDiff() {
        assertTrue(DiffParser.parse("").isEmpty())
    }
}

class SyntaxTest {
    private fun kinds(text: String, language: Language) = Syntax.highlight(text, language).map { text.substring(it.start, it.end) to it.kind }

    @Test fun picksLanguageByNameAndExtension() {
        assertEquals("Kotlin", Syntax.languageFor("android/build.gradle.kts")?.name)
        assertEquals("YAML", Syntax.languageFor(".gitlab-ci.yml")?.name)
        assertEquals("Dockerfile", Syntax.languageFor("docker/Dockerfile.ci")?.name)
        assertEquals("Swift", Syntax.languageFor("App.swift")?.name)
        assertNull(Syntax.languageFor("LICENSE"))
    }

    @Test fun kotlinTokens() {
        val tokens = kinds("@Test fun a(x: Int) = \"s\\\"q\" // done\n/* block\n */ val n = 0x1F", Syntax.kotlin)
        assertTrue("@Test" to TokenKind.ANNOTATION in tokens)
        assertTrue("fun" to TokenKind.KEYWORD in tokens)
        assertTrue("a" to TokenKind.FUNCTION in tokens)
        assertTrue("Int" to TokenKind.TYPE in tokens)
        assertTrue("\"s\\\"q\"" to TokenKind.STRING in tokens)
        assertTrue("// done" to TokenKind.COMMENT in tokens)
        assertTrue("/* block\n */" to TokenKind.COMMENT in tokens)
        assertTrue("0x1F" to TokenKind.NUMBER in tokens)
    }

    @Test fun keywordsInsideIdentifiersAreNotHighlighted() {
        assertTrue(kinds("val format2 = info", Syntax.kotlin).none { it.first == "in" || it.first == "2" })
    }

    @Test fun yamlKeysAndComments() {
        val tokens = kinds("stage: verify # note\ntags: [linux]\nurl: \"a#b\"", Syntax.yaml)
        assertTrue("stage" to TokenKind.PROPERTY in tokens)
        assertTrue("# note" to TokenKind.COMMENT in tokens)
        assertTrue("\"a#b\"" to TokenKind.STRING in tokens)
    }

    @Test fun jsonKeysDifferFromValues() {
        val tokens = kinds("{\"a\": \"b\", \"n\": 1, \"t\": true}", Syntax.json)
        assertTrue("\"a\"" to TokenKind.PROPERTY in tokens)
        assertTrue("\"b\"" to TokenKind.STRING in tokens)
        assertTrue("true" to TokenKind.KEYWORD in tokens)
    }

    @Test fun markupTagsAndAttributes() {
        val tokens = kinds("<!-- c --><a href=\"x\">t</a>", Syntax.xml)
        assertTrue("<!-- c -->" to TokenKind.COMMENT in tokens)
        assertTrue("<a" to TokenKind.TAG in tokens)
        assertTrue("href" to TokenKind.PROPERTY in tokens)
        assertTrue("</a" to TokenKind.TAG in tokens)
    }

    @Test fun shellHashOnlyStartsCommentsAfterWhitespace() {
        val tokens = kinds("echo \$# items # count", Syntax.shell)
        assertEquals(listOf("# count"), tokens.filter { it.second == TokenKind.COMMENT }.map { it.first })
    }

    @Test fun unterminatedConstructsStopAtEnd() {
        assertEquals(TokenKind.COMMENT, Syntax.highlight("/* open", Syntax.kotlin).single().kind)
        assertEquals(TokenKind.STRING, Syntax.highlight("\"open", Syntax.kotlin).single().kind)
    }
}

class DemoApiTest {
    private val api = DemoGitLabApi(java.time.Instant.parse("2026-10-28T12:00:00Z"))

    @Test fun reviewMergeFlow() = kotlinx.coroutines.runBlocking {
        val review = api.mergeRequests(WorkQuery(reviewer = api.me.username)).items
        assertTrue(review.any { it.iid == 41L })
        assertFalse(api.approvals(101, 41).userHasApproved)
        api.setApproved(101, 41, true)
        assertTrue(api.approvals(101, 41).userHasApproved)
        val merged = api.merge(101, 41, MergeOptions(squash = true, removeSourceBranch = true))
        assertEquals("merged", merged.state)
        assertTrue(api.branches(101).items.none { it.name == "feat/ios-liquid-glass" })
        assertEquals(405, assertFailsWith<ApiException> { api.merge(101, 39, MergeOptions()) }.status)
    }

    @Test fun commitBasketCreatesBranchAndChangesFiles() = kotlinx.coroutines.runBlocking {
        val readme = api.file(101, "main", "README.md")
        api.commitChanges(101, "docs/update", "docs: update", listOf(
            CommitAction("update", "README.md", content = "# New", lastCommitId = readme.lastCommitId),
            CommitAction("create", "docs/new.md", content = "hi"),
            CommitAction("delete", "scripts/ci-android.sh"),
        ), startBranch = "main")
        assertEquals("# New", api.file(101, "docs/update", "README.md").editableText())
        assertEquals("hi", api.file(101, "docs/update", "docs/new.md").editableText())
        assertEquals(404, assertFailsWith<ApiException> { api.tree(101, "docs/update", "scripts") }.status)
        assertEquals("docs: update", api.commits(101, "docs/update").items.first().title)
        assertTrue(api.branches(101, "docs/").items.any { it.name == "docs/update" })
    }

    @Test fun treeListsDirectoriesFirst() = kotlinx.coroutines.runBlocking {
        val root = api.tree(101, "main", "").items
        assertTrue(root.first().isDirectory)
        assertTrue(root.any { it.name == "README.md" && !it.isDirectory })
        assertEquals(404, assertFailsWith<ApiException> { api.tree(101, "main", "missing") }.status)
    }

    @Test fun todosAndIssues() = kotlinx.coroutines.runBlocking {
        val count = api.todos().items.size
        api.markTodoDone(api.todos().items.first().id)
        assertEquals(count - 1, api.todos().items.size)
        api.setIssueOpen(101, 57, false)
        assertEquals("closed", api.issue(101, 57).state)
        val created = api.createIssue(101, IssueDraft("New bug", "Steps"))
        assertEquals("routeforge/gitlabio#58", created.reference)
        api.addNote(101, created.iid, Noteable.ISSUE, "first")
        assertEquals("first", api.discussions(101, created.iid, Noteable.ISSUE).items.single().notes.single().body)
    }

    @Test fun pipelinesHaveStagesAndLogs() = kotlinx.coroutines.runBlocking {
        val running = api.pipelines(101).items.first()
        val jobs = api.pipelineJobs(101, running.id)
        assertEquals(listOf("build", "test", "publish"), jobs.map { it.stage }.distinct())
        val log = AnsiParser.parse(api.jobTrace(101, jobs.first().id).text)
        assertTrue(log.any { it.spans.isNotEmpty() })
        assertTrue(log.none { "section_" in it.text || '\u001B' in it.text })
        api.pipelineAction(101, running.id, PipelineAction.CANCEL)
        assertTrue(api.pipelineJobs(101, running.id).none { isActiveStatus(it.status) })
    }
}

class FormatTest {
    private val now = java.time.Instant.parse("2026-10-28T12:00:00Z")
    private val utc = java.time.ZoneOffset.UTC

    @Test fun relativeTimes() {
        assertEquals("刚刚", Format.relative("2026-10-28T11:59:30Z", now, utc))
        assertEquals("5 分钟前", Format.relative("2026-10-28T11:55:00.000Z", now, utc))
        assertEquals("3 小时前", Format.relative("2026-10-28T17:00:00+08:00", now, utc))
        assertEquals("昨天", Format.relative("2026-10-27T10:00:00Z", now, utc))
        assertEquals("4 天前", Format.relative("2026-10-24T10:00:00Z", now, utc))
        assertEquals("9月1日", Format.relative("2026-09-01T10:00:00Z", now, utc))
        assertEquals("2025年9月1日", Format.relative("2025-09-01T10:00:00Z", now, utc))
        assertEquals("", Format.relative("garbage", now, utc))
        assertEquals("2026-10-28 09:05", Format.dateTime("2026-10-28T09:05:00Z", utc))
    }

    @Test fun durationsAndSizes() {
        assertEquals("42 秒", Format.duration(42.7))
        assertEquals("3 分 5 秒", Format.duration(185.0))
        assertEquals("1 小时 2 分", Format.duration(3720.0))
        assertEquals("", Format.duration(null))
        assertEquals("512 B", Format.bytes(512))
        assertEquals("1.5 KB", Format.bytes(1536))
        assertEquals("30.0 MB", Format.bytes(31_457_280))
        assertEquals("1.3 万", Format.count(12_840))
    }
}
