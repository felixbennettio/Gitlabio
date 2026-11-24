package zone.routeforge.gitlabio.core

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import okio.Buffer
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.io.File
import kotlin.test.*

internal fun fixture(name: String): String =
    GitLabClientTest::class.java.getResource("/fixtures/$name")?.readText() ?: error("Missing fixture $name")

internal fun sharedContract(name: String): String = File(System.getProperty("gitlabio.contracts"), "fixtures/$name").readText()

class GitLabClientTest {
    private lateinit var server: MockWebServer
    private lateinit var client: GitLabClient

    @Before fun setup() {
        val certificate = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val serverCerts = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCerts = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server = MockWebServer().apply { useHttps(serverCerts.sslSocketFactory(), false); start() }
        val transport = OkHttpClient.Builder().sslSocketFactory(clientCerts.sslSocketFactory(), clientCerts.trustManager).build()
        client = GitLabClient(GitLabInstance(server.url("/gitlab").toString()), "test-only", transport = transport)
    }

    @After fun cleanup() { server.shutdown() }

    private fun RecordedRequest.json(): JsonObject = Json.parseToJsonElement(body.readUtf8()).jsonObject
    private fun ok(body: String = "{}") = MockResponse().setBody(body)

    @Test fun rejectsUnsafeInstances() {
        listOf("http://host", "https://user:secret@host", "https://host?token=a", "https://host/#x", "https://host/a/../b", "file:///tmp/x", "not a url", "").forEach {
            assertFailsWith<IllegalArgumentException>(it) { GitLabInstance(it) }
        }
    }

    @Test fun tokenControlCharactersDoNotReachHTTPHeaders() {
        val error = assertFailsWith<IllegalArgumentException> { GitLabClient(GitLabInstance("https://host"), "sensitive\nvalue") }
        assertFalse(error.message!!.contains("sensitive"))
    }

    @Test fun nestedPathAndRefAreNotConfused() {
        val request = client.request(listOf("projects", "group/app", "repository", "files", "文 件/a#b%.kt"), mapOf("ref" to "feat/a&b"))
        assertTrue(request.url.encodedPath.contains("/gitlab/api/v4/projects/group%2Fapp/"))
        assertTrue(request.url.encodedPath.endsWith("%2Fa%23b%25.kt"))
        assertEquals("feat/a&b", request.url.queryParameter("ref"))
        assertEquals("test-only", request.header("PRIVATE-TOKEN"))
        assertNull(request.url.queryParameter("private_token"))
    }

    @Test fun rootAndSubpathInstancesUseOneAPIPrefix() {
        assertEquals("https://gitlab.com/api/v4/user", GitLabInstance("https://gitlab.com/").endpoint(listOf("user")).toString())
        assertEquals("https://host/gitlab/api/v4/user", GitLabInstance("https://host/gitlab/").endpoint(listOf("user")).toString())
        assertEquals("https://host/gitlab", GitLabInstance(" https://host/gitlab/ ").canonical)
    }

    @Test fun projectDecodeAndPagination() = runBlocking {
        server.enqueue(ok(sharedContract("projects.json")).setHeader("X-Next-Page", "3"))
        val result = client.projects(ProjectQuery(search = " app ", filter = ProjectFilter.STARRED), 2)
        assertEquals(3, result.next)
        assertEquals("group/app", result.items.single().pathWithNamespace)
        val url = server.takeRequest().requestUrl!!
        assertEquals("2", url.queryParameter("page"))
        assertEquals("50", url.queryParameter("per_page"))
        assertEquals("true", url.queryParameter("starred"))
        assertEquals("app", url.queryParameter("search"))
        assertNull(url.queryParameter("membership"))
    }

    @Test fun rejectsBackwardsPagination() = runBlocking {
        server.enqueue(ok("[]").setHeader("X-Next-Page", "1"))
        assertNull(client.projects(page = 2).next)
        server.enqueue(ok("[]").setHeader("X-Next-Page", ""))
        assertNull(client.projects(page = 1).next)
    }

    @Test fun httpFailureDoesNotExposeResponseBody() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(401).setBody("sensitive-server-response"))
        val error = assertFailsWith<ApiException> { client.currentUser() }
        assertEquals(401, error.status)
        assertFalse(error.message!!.contains("sensitive"))
        assertFalse(describeError(error).contains("sensitive"))
    }

    @Test fun redirectsDoNotForwardCredentials() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", server.url("/stolen")))
        server.enqueue(ok())
        assertEquals(302, assertFailsWith<ApiException> { client.currentUser() }.status)
        assertEquals(1, server.requestCount)
    }

    @Test fun userAndTokenScopesDecode() = runBlocking {
        server.enqueue(ok(fixture("user.json")))
        server.enqueue(ok(fixture("token_self.json")))
        assertEquals("fixture.user", client.currentUser().username)
        val token = assertNotNull(client.tokenInfo())
        assertEquals(listOf("read_api", "read_user"), token.scopes)
        assertEquals("/gitlab/api/v4/personal_access_tokens/self", server.takeRequest().let { server.takeRequest() }.requestUrl!!.encodedPath)
        val capabilities = TokenCapabilities(token.scopes)
        assertTrue(capabilities.canRead)
        assertFalse(capabilities.canWrite)
        assertEquals(1, capabilities.warnings.size)
    }

    @Test fun tokenInfoIsOptionalOnOlderInstances() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(404))
        assertNull(client.tokenInfo())
        server.enqueue(MockResponse().setResponseCode(401))
        assertEquals(401, assertFailsWith<ApiException> { client.tokenInfo() }.status)
    }

    @Test fun mergeRequestDecodesNestedPipelineAndReferences() = runBlocking {
        server.enqueue(ok(fixture("merge_request.json")))
        val mr = client.mergeRequest(11, 42)
        assertEquals("group/app!42", mr.reference)
        assertEquals("running", mr.headPipeline?.status)
        assertEquals(listOf("reviewer"), mr.reviewers.map { it.username })
        assertEquals(true, mr.forceRemoveSourceBranch)
        assertEquals("/gitlab/api/v4/projects/11/merge_requests/42", server.takeRequest().requestUrl!!.encodedPath)
    }

    @Test fun globalAndProjectWorkQueries() = runBlocking {
        server.enqueue(ok("[]"))
        server.enqueue(ok("[]"))
        client.mergeRequests(WorkQuery(scope = WorkScope.ALL, reviewer = "me", state = "opened"))
        client.issues(WorkQuery(project = 11, state = "closed", scope = WorkScope.ASSIGNED, search = "crash"))
        val global = server.takeRequest().requestUrl!!
        assertEquals("/gitlab/api/v4/merge_requests", global.encodedPath)
        assertEquals("me", global.queryParameter("reviewer_username"))
        val scoped = server.takeRequest().requestUrl!!
        assertEquals("/gitlab/api/v4/projects/11/issues", scoped.encodedPath)
        assertEquals("assigned_to_me", scoped.queryParameter("scope"))
        assertEquals("closed", scoped.queryParameter("state"))
        assertEquals("crash", scoped.queryParameter("search"))
    }

    @Test fun mergeSendsOptionsWithPut() = runBlocking {
        server.enqueue(ok(fixture("merge_request.json")))
        client.merge(11, 42, MergeOptions(squash = true, removeSourceBranch = true, commitMessage = "squashed", sha = "abc"))
        val request = server.takeRequest()
        assertEquals("PUT", request.method)
        assertTrue(request.path!!.endsWith("/merge_requests/42/merge"))
        val body = request.json()
        assertTrue(body["squash"]!!.jsonPrimitive.boolean)
        assertTrue(body["should_remove_source_branch"]!!.jsonPrimitive.boolean)
        assertEquals("squashed", body["squash_commit_message"]!!.jsonPrimitive.content)
        assertEquals("abc", body["sha"]!!.jsonPrimitive.content)
    }

    @Test fun mergeConflictsAreErrors() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(405))
        assertEquals(405, assertFailsWith<ApiException> { client.merge(11, 42, MergeOptions()) }.status)
    }

    @Test fun approveAndUnapproveUsePost() = runBlocking {
        server.enqueue(ok())
        server.enqueue(ok())
        client.setApproved(11, 42, true)
        client.setApproved(11, 42, false)
        assertEquals("POST", server.takeRequest().also { assertTrue(it.path!!.endsWith("/42/approve")) }.method)
        assertTrue(server.takeRequest().path!!.endsWith("/42/unapprove"))
    }

    @Test fun createMergeRequestMarksDraftsInTitle() = runBlocking {
        server.enqueue(ok(fixture("merge_request.json")))
        client.createMergeRequest(11, MergeRequestDraft("feat/x", "main", "Add x", "why", draft = true))
        val body = server.takeRequest().json()
        assertEquals("Draft: Add x", body["title"]!!.jsonPrimitive.content)
        assertEquals("feat/x", body["source_branch"]!!.jsonPrimitive.content)
        assertTrue(body["remove_source_branch"]!!.jsonPrimitive.boolean)
        assertFailsWith<IllegalArgumentException> { client.createMergeRequest(11, MergeRequestDraft("main", "main", "x")) }
        Unit
    }

    @Test fun commitChangesSendsAllActionsInOneRequest() = runBlocking {
        server.enqueue(ok("""{"id":"abc","short_id":"abc","title":"Edit"}"""))
        val actions = listOf(
            CommitAction("update", "src/a.kt", content = "new", encoding = "text", lastCommitId = "prev"),
            CommitAction("create", "src/b.kt", content = "b", encoding = "text"),
            CommitAction("delete", "src/c.kt"),
        )
        val commit = client.commitChanges(11, "feat/edit", "Edit files", actions, startBranch = "main")
        assertEquals("abc", commit.id)
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertTrue(request.path!!.startsWith("/gitlab/api/v4/projects/11/repository/commits"))
        val body = request.json()
        assertEquals("main", body["start_branch"]!!.jsonPrimitive.content)
        assertEquals("feat/edit", body["branch"]!!.jsonPrimitive.content)
        val sent = body["actions"]!!.jsonArray.map { it.jsonObject }
        assertEquals(listOf("update", "create", "delete"), sent.map { it["action"]!!.jsonPrimitive.content })
        assertEquals("prev", sent[0]["last_commit_id"]!!.jsonPrimitive.content)
        assertFalse(sent[2].containsKey("content"))
    }

    @Test fun commitConflictKeepsErrorVisible() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(400).setBody("""{"message":"A file with this name doesn't exist"}"""))
        val error = assertFailsWith<ApiException> { client.commitChanges(11, "main", "x", listOf(CommitAction("update", "a", content = "b"))) }
        assertEquals(400, error.status)
        assertEquals(1, server.requestCount)
    }

    @Test fun branchNamesAreSinglePathSegments() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(204))
        client.deleteBranch(11, "feat/a b")
        val request = server.takeRequest()
        assertEquals("DELETE", request.method)
        assertEquals("/gitlab/api/v4/projects/11/repository/branches/feat%2Fa%20b", request.requestUrl!!.encodedPath)
    }

    @Test fun issueStateChangesUseStateEvent() = runBlocking {
        server.enqueue(ok("""{"id":1,"iid":2,"project_id":11,"title":"t","state":"closed"}"""))
        assertEquals("closed", client.setIssueOpen(11, 2, false).state)
        val request = server.takeRequest()
        assertEquals("PUT", request.method)
        assertEquals("close", request.json()["state_event"]!!.jsonPrimitive.content)
    }

    @Test fun discussionsKeepSystemNotesAndPositions() = runBlocking {
        server.enqueue(ok(fixture("discussions.json")))
        val discussions = client.discussions(11, 42, Noteable.MERGE_REQUEST).items
        assertTrue(discussions[0].notes.single().system)
        assertEquals(48, discussions[1].notes[0].position?.newLine)
        assertTrue(discussions[1].notes[1].resolved)
    }

    @Test fun todosDecodeEvenWithCommitTargets() = runBlocking {
        server.enqueue(ok(fixture("todos.json")))
        val todos = client.todos().items
        assertEquals(42, todos[0].target?.iid)
        assertNull(todos[1].target?.iid)
        assertEquals("pending", server.takeRequest().requestUrl!!.queryParameter("state"))
    }

    @Test fun pipelineJobsAreCollectedAcrossPages() = runBlocking {
        server.enqueue(ok(fixture("jobs.json")).setHeader("X-Next-Page", "2"))
        server.enqueue(ok(fixture("jobs.json")))
        val jobs = client.pipelineJobs(11, 901)
        assertEquals(4, jobs.size)
        assertEquals("manual", jobs[1].status)
        assertTrue(jobs[1].allowFailure)
        assertEquals("100", server.takeRequest().requestUrl!!.queryParameter("per_page"))
    }

    @Test fun triggerPipelineSendsVariables() = runBlocking {
        server.enqueue(ok("""{"id":5,"status":"created","ref":"main"}"""))
        client.triggerPipeline(11, "main", listOf(PipelineVariable("DEPLOY", "true"), PipelineVariable(" ", "ignored")))
        val request = server.takeRequest()
        assertTrue(request.path!!.endsWith("/projects/11/pipeline"))
        val variables = request.json()["variables"]!!.jsonArray
        assertEquals(1, variables.size)
        assertEquals("env_var", variables[0].jsonObject["variable_type"]!!.jsonPrimitive.content)
    }

    @Test fun pipelineAndJobActionsUsePost() = runBlocking {
        server.enqueue(ok("""{"id":5,"status":"running","ref":"main"}"""))
        server.enqueue(ok("""{"id":7,"name":"deploy","status":"pending","stage":"deploy"}"""))
        client.pipelineAction(11, 5, PipelineAction.RETRY)
        client.jobAction(11, 7, JobAction.PLAY)
        assertEquals("POST", server.takeRequest().also { assertTrue(it.path!!.endsWith("/pipelines/5/retry")) }.method)
        assertEquals("POST", server.takeRequest().also { assertTrue(it.path!!.endsWith("/jobs/7/play")) }.method)
    }

    @Test fun traceKeepsOnlyTheTailOfLargeLogs() = runBlocking {
        val log = buildString {
            repeat(40_000) { append("line $it ").append("x".repeat(30)).append('\n') }
            append("FINAL LINE\n")
        }
        server.enqueue(MockResponse().setBody(Buffer().writeUtf8(log)))
        val trace = client.jobTrace(11, 7)
        assertTrue(trace.truncated)
        assertTrue(trace.text.endsWith("FINAL LINE\n"))
        assertTrue(trace.text.startsWith("line "))
        assertTrue(trace.text.length <= GitLabClient.MAX_TRACE_BYTES)
        server.enqueue(ok("short"))
        assertEquals(JobTrace("short", false), client.jobTrace(11, 7))
    }

    @Test fun commitDiffDecodes() = runBlocking {
        server.enqueue(ok(fixture("commit_diff.json")))
        val diffs = client.commitDiff(11, "0123").items
        assertEquals(2 to 1, DiffParser.stats(diffs[0].diff))
        assertTrue(diffs[1].newFile)
    }

    @Test fun readmeIsFoundInRootTree() = runBlocking {
        server.enqueue(ok("""[{"id":"1","name":"src","path":"src","type":"tree"},{"id":"2","name":"README.md","path":"README.md","type":"blob"}]"""))
        server.enqueue(ok("""{"file_path":"README.md","size":3,"encoding":"base64","content":"IyBB","last_commit_id":"x"}"""))
        assertEquals("# A", client.readme(11, "main")?.editableText())
        assertEquals("100", server.takeRequest().requestUrl!!.queryParameter("per_page"))
        assertEquals("/gitlab/api/v4/projects/11/repository/files/README.md", server.takeRequest().requestUrl!!.encodedPath)
        server.enqueue(ok("[]"))
        assertNull(client.readme(11, "main"))
    }

    @Test fun binaryAndLargeFilesCannotBeEdited() {
        assertEquals("old", RepositoryFile("a", 3, "base64", "b2xk\n", "sha").editableText())
        assertEquals("héllo", RepositoryFile.ofText("a", "héllo", "sha").editableText())
        assertFails { RepositoryFile("a", 1, "base64", "AA==", "sha").editableText() }
        assertFails { RepositoryFile("a", 2_000_000, "base64", "YQ==", "sha").editableText() }
        assertFails { RepositoryFile("a", 2, "base64", "/w==", "sha").editableText() }
    }
}
