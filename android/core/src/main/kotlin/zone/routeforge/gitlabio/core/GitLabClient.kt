package zone.routeforge.gitlabio.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.Buffer
import java.io.IOException
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class GitLabInstance(value: String) {
    val url: HttpUrl

    init {
        val text = value.trim()
        val raw = runCatching { URI(text) }.getOrNull()
        require(
            raw != null && raw.scheme.equals("https", true) && !raw.host.isNullOrEmpty() && raw.rawUserInfo == null &&
                raw.rawQuery == null && raw.rawFragment == null && raw.path.split('/').none { it == "." || it == ".." }
        ) { "请输入 HTTPS GitLab 实例地址；不能包含账户、查询或片段。" }
        url = text.trimEnd('/').toHttpUrl()
    }

    /** Canonical form stored with accounts, without a trailing slash. */
    val canonical: String get() = url.toString().trimEnd('/')
    val host: String get() = url.host

    fun endpoint(path: List<String>, query: Map<String, String> = emptyMap()): HttpUrl {
        val builder = url.newBuilder()
        builder.addPathSegments("api/v4")
        path.forEach { builder.addPathSegment(it) }
        query.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        return builder.build()
    }

    companion object { const val GITLAB_COM = "https://gitlab.com" }
}

class GitLabClient(
    val instance: GitLabInstance,
    private val token: String,
    trust: TrustPolicy = TrustPolicy.System,
    transport: OkHttpClient = sharedTransport,
) : GitLabApi {
    init { require(token.isNotEmpty() && token.all { it.code in 33..126 }) { "令牌包含不支持的字符，请重新粘贴。" } }

    // Redirects are refused outright so the PRIVATE-TOKEN header can never be replayed to another origin.
    private val http = trust.apply(transport.newBuilder()).followRedirects(false).followSslRedirects(false)
        .connectTimeout(20, TimeUnit.SECONDS).callTimeout(90, TimeUnit.SECONDS).build()

    fun request(path: List<String>, query: Map<String, String> = emptyMap(), method: String = "GET", body: JsonElement? = null): Request {
        val payload = body?.let { json.encodeToString(JsonElement.serializer(), it).toRequestBody(JSON_TYPE) }
            ?: if (method == "POST" || method == "PUT") ByteArray(0).toRequestBody() else null
        return Request.Builder().url(instance.endpoint(path, query)).header("PRIVATE-TOKEN", token)
            .header("Accept", "application/json").method(method, payload).build()
    }

    private suspend fun execute(request: Request): Response = suspendCancellableCoroutine { continuation ->
        val call = http.newCall(request)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) { if (!continuation.isCancelled) continuation.resumeWithException(e) }
            override fun onResponse(call: Call, response: Response) {
                if (continuation.isCancelled) response.close()
                else continuation.resume(response) { _, value, _ -> value.close() }
            }
        })
    }

    private class Raw(val text: String, val next: String?, val truncated: Boolean)

    /** Reads at most [limit] bytes; with [keepTail] the oldest bytes are dropped instead of failing. */
    private suspend fun raw(
        path: List<String>, query: Map<String, String> = emptyMap(), method: String = "GET", body: JsonElement? = null,
        limit: Long = MAX_RESPONSE_BYTES, keepTail: Boolean = false,
    ): Raw = withContext(Dispatchers.IO) {
        execute(request(path, query, method, body)).use { response ->
            if (!response.isSuccessful) throw ApiException(response.code)
            val source = response.body?.source() ?: return@use Raw("", null, false)
            val buffer = Buffer()
            var truncated = false
            while (source.read(buffer, 64 * 1024) != -1L) {
                if (buffer.size > limit) {
                    if (!keepTail) throw ResponseTooLargeException()
                    buffer.skip(buffer.size - limit)
                    truncated = true
                }
            }
            Raw(buffer.readUtf8(), response.header("X-Next-Page"), truncated)
        }
    }

    private suspend inline fun <reified T> obj(path: List<String>, query: Map<String, String> = emptyMap(), method: String = "GET", body: JsonElement? = null): T =
        json.decodeFromString(raw(path, query, method, body).text)

    private suspend inline fun <reified T> list(path: List<String>, page: Int, query: Map<String, String> = emptyMap(), perPage: Int = PER_PAGE): Page<T> {
        val response = raw(path, query + mapOf("page" to "$page", "per_page" to "$perPage"))
        return Page(json.decodeFromString<List<T>>(response.text), response.next?.toIntOrNull()?.takeIf { it > page })
    }

    private fun projectPath(id: Long, vararg rest: String) = listOf("projects", "$id") + rest

    override suspend fun currentUser(): User = obj(listOf("user"))

    override suspend fun tokenInfo(): TokenInfo? = try {
        obj(listOf("personal_access_tokens", "self"))
    } catch (error: ApiException) {
        if (error.status == 404 || error.status == 403) null else throw error
    }

    override suspend fun projects(query: ProjectQuery, page: Int): Page<Project> {
        val params = mutableMapOf("order_by" to query.sort.orderBy, "sort" to if (query.sort == ProjectSort.NAME) "asc" else "desc", "simple" to "false")
        when (query.filter) {
            ProjectFilter.MEMBERSHIP -> params["membership"] = "true"
            ProjectFilter.STARRED -> params["starred"] = "true"
            ProjectFilter.OWNED -> params["owned"] = "true"
        }
        if (query.search.isNotBlank()) params["search"] = query.search.trim()
        return list(listOf("projects"), page, params)
    }

    override suspend fun project(id: Long): Project = obj(projectPath(id), mapOf("statistics" to "true"))

    override suspend fun languages(project: Long): Map<String, Double> = obj(projectPath(project, "languages"))

    override suspend fun setStarred(project: Long, starred: Boolean): Project = try {
        obj(projectPath(project, if (starred) "star" else "unstar"), method = "POST")
    } catch (error: ApiException) {
        // 304 means the project was already in the requested state.
        if (error.status == 304) project(project) else throw error
    }

    override suspend fun readme(project: Long, ref: String): RepositoryFile? {
        val entries = list<TreeEntry>(projectPath(project, "repository", "tree"), 1, mapOf("ref" to ref), perPage = 100).items
        val candidate = entries.filter { !it.isDirectory && README.matches(it.name) }
            .minByOrNull { if (it.name.endsWith(".md", true)) 0 else 1 } ?: return null
        return file(project, ref, candidate.path)
    }

    override suspend fun branches(project: Long, search: String?, page: Int): Page<Branch> =
        list(projectPath(project, "repository", "branches"), page, search?.takeIf { it.isNotBlank() }?.let { mapOf("search" to it.trim()) } ?: emptyMap())

    override suspend fun createBranch(project: Long, name: String, ref: String): Branch {
        require(name.isNotBlank()) { "请填写分支名称。" }
        return obj(projectPath(project, "repository", "branches"), method = "POST", body = buildJsonObject { put("branch", name.trim()); put("ref", ref) })
    }

    override suspend fun deleteBranch(project: Long, name: String) {
        raw(projectPath(project, "repository", "branches", name), method = "DELETE")
    }

    override suspend fun tree(project: Long, ref: String, path: String, page: Int): Page<TreeEntry> =
        list(projectPath(project, "repository", "tree"), page, buildMap { put("ref", ref); if (path.isNotEmpty()) put("path", path) }, perPage = 100)

    override suspend fun file(project: Long, ref: String, path: String): RepositoryFile =
        obj(projectPath(project, "repository", "files", path), mapOf("ref" to ref))

    override suspend fun commitChanges(project: Long, branch: String, message: String, actions: List<CommitAction>, startBranch: String?): Commit {
        require(message.isNotBlank()) { "请填写提交说明。" }
        require(actions.isNotEmpty()) { "没有要提交的更改。" }
        val body = buildJsonObject {
            put("branch", branch)
            put("commit_message", message)
            if (startBranch != null) put("start_branch", startBranch)
            put("actions", json.encodeToJsonElement(actions))
        }
        return obj(projectPath(project, "repository", "commits"), method = "POST", body = body)
    }

    override suspend fun commits(project: Long, ref: String, path: String?, page: Int): Page<Commit> =
        list(projectPath(project, "repository", "commits"), page, buildMap { put("ref_name", ref); if (!path.isNullOrEmpty()) put("path", path) })

    override suspend fun commit(project: Long, sha: String): Commit = obj(projectPath(project, "repository", "commits", sha))

    override suspend fun commitDiff(project: Long, sha: String, page: Int): Page<FileDiff> =
        list(projectPath(project, "repository", "commits", sha, "diff"), page)

    private fun workParams(query: WorkQuery): Map<String, String> = buildMap {
        put("state", query.state)
        put("scope", query.scope.value)
        put("order_by", "updated_at")
        query.reviewer?.let { put("reviewer_username", it) }
        if (query.search.isNotBlank()) put("search", query.search.trim())
    }

    private fun workPath(query: WorkQuery, kind: Noteable) =
        query.project?.let { projectPath(it, kind.path) } ?: listOf(kind.path)

    override suspend fun mergeRequests(query: WorkQuery, page: Int): Page<MergeRequest> =
        list(workPath(query, Noteable.MERGE_REQUEST), page, workParams(query))

    override suspend fun mergeRequest(project: Long, iid: Long): MergeRequest = obj(projectPath(project, "merge_requests", "$iid"))

    override suspend fun approvals(project: Long, iid: Long): Approvals = obj(projectPath(project, "merge_requests", "$iid", "approvals"))

    override suspend fun setApproved(project: Long, iid: Long, approved: Boolean) {
        raw(projectPath(project, "merge_requests", "$iid", if (approved) "approve" else "unapprove"), method = "POST")
    }

    override suspend fun merge(project: Long, iid: Long, options: MergeOptions): MergeRequest {
        val body = buildJsonObject {
            put("squash", options.squash)
            put("should_remove_source_branch", options.removeSourceBranch)
            options.commitMessage?.takeIf { it.isNotBlank() }?.let { put(if (options.squash) "squash_commit_message" else "merge_commit_message", it) }
            options.sha?.let { put("sha", it) }
        }
        return obj(projectPath(project, "merge_requests", "$iid", "merge"), method = "PUT", body = body)
    }

    override suspend fun createMergeRequest(project: Long, draft: MergeRequestDraft): MergeRequest {
        require(draft.title.isNotBlank()) { "请填写标题。" }
        require(draft.sourceBranch != draft.targetBranch) { "源分支和目标分支不能相同。" }
        val title = draft.title.trim().let { if (draft.draft && !it.startsWith("Draft:")) "Draft: $it" else it }
        val body = buildJsonObject {
            put("source_branch", draft.sourceBranch)
            put("target_branch", draft.targetBranch)
            put("title", title)
            put("description", draft.description)
            put("remove_source_branch", draft.removeSourceBranch)
            put("squash", draft.squash)
        }
        return obj(projectPath(project, "merge_requests"), method = "POST", body = body)
    }

    override suspend fun mergeRequestDiffs(project: Long, iid: Long, page: Int): Page<FileDiff> =
        list(projectPath(project, "merge_requests", "$iid", "diffs"), page, perPage = 30)

    override suspend fun discussions(project: Long, iid: Long, kind: Noteable, page: Int): Page<Discussion> =
        list(projectPath(project, kind.path, "$iid", "discussions"), page)

    override suspend fun addNote(project: Long, iid: Long, kind: Noteable, body: String): Note {
        require(body.isNotBlank()) { "评论不能为空。" }
        return obj(projectPath(project, kind.path, "$iid", "notes"), method = "POST", body = buildJsonObject { put("body", body) })
    }

    override suspend fun issues(query: WorkQuery, page: Int): Page<Issue> =
        list(workPath(query, Noteable.ISSUE), page, workParams(query))

    override suspend fun issue(project: Long, iid: Long): Issue = obj(projectPath(project, "issues", "$iid"))

    private fun issueBody(draft: IssueDraft): JsonObject {
        require(draft.title.isNotBlank()) { "请填写标题。" }
        return buildJsonObject {
            put("title", draft.title.trim())
            put("description", draft.description)
            put("labels", draft.labels.joinToString(","))
            put("confidential", draft.confidential)
        }
    }

    override suspend fun createIssue(project: Long, draft: IssueDraft): Issue =
        obj(projectPath(project, "issues"), method = "POST", body = issueBody(draft))

    override suspend fun updateIssue(project: Long, iid: Long, draft: IssueDraft): Issue =
        obj(projectPath(project, "issues", "$iid"), method = "PUT", body = issueBody(draft))

    override suspend fun setIssueOpen(project: Long, iid: Long, open: Boolean): Issue =
        obj(projectPath(project, "issues", "$iid"), method = "PUT", body = buildJsonObject { put("state_event", if (open) "reopen" else "close") })

    override suspend fun pipelines(project: Long, status: String?, ref: String?, page: Int): Page<Pipeline> =
        list(projectPath(project, "pipelines"), page, buildMap { status?.let { put("status", it) }; ref?.let { put("ref", it) } })

    override suspend fun pipeline(project: Long, id: Long): Pipeline = obj(projectPath(project, "pipelines", "$id"))

    override suspend fun pipelineJobs(project: Long, pipeline: Long): List<Job> {
        val jobs = mutableListOf<Job>()
        var page: Int? = 1
        while (page != null && page <= 20) {
            val result = list<Job>(projectPath(project, "pipelines", "$pipeline", "jobs"), page, perPage = 100)
            jobs += result.items
            page = result.next
        }
        return jobs
    }

    override suspend fun triggerPipeline(project: Long, ref: String, variables: List<PipelineVariable>): Pipeline {
        require(ref.isNotBlank()) { "请选择分支或标签。" }
        val body = buildJsonObject {
            put("ref", ref)
            put("variables", JsonArray(variables.filter { it.key.isNotBlank() }.map { json.encodeToJsonElement(it) }))
        }
        return obj(projectPath(project, "pipeline"), method = "POST", body = body)
    }

    override suspend fun pipelineAction(project: Long, id: Long, action: PipelineAction): Pipeline =
        obj(projectPath(project, "pipelines", "$id", action.path), method = "POST")

    override suspend fun job(project: Long, id: Long): Job = obj(projectPath(project, "jobs", "$id"))

    override suspend fun jobAction(project: Long, id: Long, action: JobAction): Job =
        obj(projectPath(project, "jobs", "$id", action.path), method = "POST")

    override suspend fun jobTrace(project: Long, id: Long): JobTrace {
        val response = raw(projectPath(project, "jobs", "$id", "trace"), limit = MAX_TRACE_BYTES, keepTail = true)
        // Dropping bytes may split a UTF-8 sequence or line; start at the next full line.
        val text = if (response.truncated) response.text.substringAfter('\n') else response.text
        return JobTrace(text, response.truncated)
    }

    override suspend fun todos(page: Int): Page<Todo> = list(listOf("todos"), page, mapOf("state" to "pending"))

    override suspend fun markTodoDone(id: Long) { raw(listOf("todos", "$id", "mark_as_done"), method = "POST") }

    override suspend fun markAllTodosDone() { raw(listOf("todos", "mark_as_done"), method = "POST") }

    companion object {
        const val PER_PAGE = 50
        const val MAX_RESPONSE_BYTES = 16L * 1024 * 1024
        const val MAX_TRACE_BYTES = 1L * 1024 * 1024
        private val JSON_TYPE = "application/json".toMediaType()
        private val README = Regex("readme(\\.(md|markdown|txt|rst|adoc))?", RegexOption.IGNORE_CASE)
        internal val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true; encodeDefaults = true }
        private val sharedTransport by lazy { OkHttpClient() }
    }
}
