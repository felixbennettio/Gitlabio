package zone.routeforge.gitlabio.core

import kotlinx.coroutines.delay
import java.security.MessageDigest
import java.time.Duration
import java.time.Instant

/**
 * An offline GitLab with synthetic data, used for the demo mode and for screenshots. Writes change
 * the in-memory state so every flow can be tried without an account. Nothing here is real.
 */
class DemoGitLabApi(private val now: Instant = Instant.now(), private val latencyMillis: Long = 0) : GitLabApi {
    private val lock = Any()

    private fun ago(minutes: Long): String = now.minus(Duration.ofMinutes(minutes)).toString()
    private suspend fun <T> io(block: () -> T): T {
        if (latencyMillis > 0) delay(latencyMillis)
        return synchronized(lock, block)
    }

    val me = User(1, "felix", "Felix Bennett")
    private val lin = User(2, "lin.yue", "林悦")
    private val marco = User(3, "marco", "Marco Rossi")
    private val sora = User(4, "sora", "Sora Tanaka")

    private var projects = listOf(
        Project(101, "gitlabio", "routeforge/gitlabio", "Routeforge / gitlabio", "Native GitLab client for iOS and Android, for gitlab.com and self-managed instances.",
            "main", "https://gitlab.example.test/routeforge/gitlabio", "private", 42, 6, 4, ago(12), topics = listOf("android", "ios", "gitlab"),
            namespace = Namespace(10, "Routeforge", "routeforge", "group", "routeforge"), statistics = ProjectStatistics(1284, 48_000_000, 31_500_000)),
        Project(102, "cirrus", "routeforge/cirrus", "Routeforge / cirrus", "Reusable CI templates for Linux, macOS and Windows runners.",
            "main", "https://gitlab.example.test/routeforge/cirrus", "internal", 18, 3, 1, ago(95), topics = listOf("ci"),
            namespace = Namespace(10, "Routeforge", "routeforge", "group", "routeforge"), statistics = ProjectStatistics(402, 9_800_000, 6_100_000)),
        Project(103, "runner-images", "infra/runner-images", "Infra / runner-images", "Container images used by the CI runners.",
            "main", "https://gitlab.example.test/infra/runner-images", "private", 7, 1, 0, ago(60 * 26),
            namespace = Namespace(11, "Infra", "infra", "group", "infra"), statistics = ProjectStatistics(211, 2_400_000, 1_900_000)),
        Project(104, "design-tokens", "design/design-tokens", "Design / design-tokens", "Color, type and spacing tokens shared by the apps.",
            "main", "https://gitlab.example.test/design/design-tokens", "internal", 11, 2, 0, ago(60 * 24 * 4),
            namespace = Namespace(12, "Design", "design", "group", "design"), statistics = ProjectStatistics(96, 700_000, 500_000)),
        Project(105, "homelab", "felix/homelab", "Felix Bennett / homelab", "Ansible playbooks for the home lab.",
            "main", "https://gitlab.example.test/felix/homelab", "public", 3, 0, 0, ago(60 * 24 * 9),
            namespace = Namespace(1, "Felix Bennett", "felix", "user", "felix"), statistics = ProjectStatistics(57, 300_000, 200_000)),
    )
    private val starred = mutableSetOf(101L, 102L)

    private val files = mutableMapOf<Long, MutableMap<String, String>>(
        101L to mutableMapOf(
            "README.md" to README,
            ".gitlab-ci.yml" to CI_YAML,
            "android/build.gradle.kts" to GRADLE,
            "android/core/src/main/kotlin/GitLabClient.kt" to KOTLIN,
            "android/app/src/main/AndroidManifest.xml" to MANIFEST,
            "apple/Gitlabio/GitlabioApp.swift" to SWIFT,
            "docs/PLAN.md" to "# Plan\n\n- M1: remote editing\n- M2: native redesign\n- M3: local Git engine and OAuth\n",
            "scripts/ci-android.sh" to "#!/usr/bin/env bash\nset -euo pipefail\n# Build and test the Android app\n./gradlew :core:test :app:assembleDebug\n",
        ),
    )
    private fun filesOf(project: Long) = files.getOrPut(project) {
        mutableMapOf("README.md" to "# ${projects.first { it.id == project }.name}\n\n${projects.first { it.id == project }.description}\n")
    }

    private val branches = mutableMapOf<Long, MutableList<Branch>>()
    private fun branchesOf(project: Long) = branches.getOrPut(project) {
        val names = if (project == 101L) listOf("main", "feat/android-redesign", "feat/ios-liquid-glass", "fix/token-scope-warning") else listOf("main", "develop")
        names.mapIndexed { index, name ->
            Branch(name, protected = name == "main", default = name == "main", canPush = true, merged = false,
                commit = commitsOf(project).getOrNull(index))
        }.toMutableList()
    }

    private val commits = mutableMapOf<Long, MutableList<Commit>>()
    private fun commitsOf(project: Long) = commits.getOrPut(project) {
        listOf(
            Triple("feat(android): adaptive navigation with NavigationSuiteScaffold", lin, 25L),
            Triple("feat(core): per-account TLS trust policies", me, 140L),
            Triple("fix(ci): reuse the runner dependency cache", marco, 60L * 6),
            Triple("feat(ios): Liquid Glass inbox", lin, 60L * 20),
            Triple("docs: document the M2 milestone", me, 60L * 30),
            Triple("test(core): contract tests for pagination", sora, 60L * 48),
            Triple("chore: bump Compose BOM", marco, 60L * 72),
            Triple("feat: initial native clients", me, 60L * 24 * 6),
        ).mapIndexed { index, (title, author, minutes) ->
            val id = sha("$project-$index-$title")
            Commit(id, id.take(8), title, "$title\n\nPart of the native redesign.", author.name, "${author.username}@example.test",
                ago(minutes), ago(minutes), ago(minutes), stats = CommitStats(12 + index * 7, 3 + index, 15 + index * 8),
                webUrl = "https://gitlab.example.test/-/commit/$id")
        }.toMutableList()
    }

    private val mergeRequests = mutableListOf(
        MergeRequest(5042, 42, 101, "Android: rewrite UI with Material 3 and adaptive navigation",
            "Rebuilds the Android client.\n\n- Material 3 with dynamic color\n- `NavigationSuiteScaffold` for phones and tablets\n- Demo mode for screenshots\n\nCloses #57",
            "opened", false, "feat/android-redesign", "main", me, listOf(me), listOf(lin), listOf("android", "ui"), ago(60 * 5), ago(25),
            references = References("!42", "!42", "routeforge/gitlabio!42"), userNotesCount = 3, detailedMergeStatus = "ci_still_running",
            headPipeline = Pipeline(9001, 311, 101, "running", "feat/android-redesign", sha("p9001"), "merge_request_event", ago(20)), changesCount = "3"),
        MergeRequest(5041, 41, 101, "iOS: Liquid Glass tab bar and inbox",
            "Moves the tab bar to the system Liquid Glass style and adds the unified inbox.", "opened", false,
            "feat/ios-liquid-glass", "main", lin, listOf(lin), listOf(me), listOf("ios", "ui"), ago(60 * 20), ago(60 * 2),
            references = References("!41", "!41", "routeforge/gitlabio!41"), userNotesCount = 2, detailedMergeStatus = "mergeable",
            headPipeline = Pipeline(9000, 310, 101, "success", "feat/ios-liquid-glass", sha("p9000"), "merge_request_event", ago(60 * 3)), changesCount = "2"),
        MergeRequest(5039, 39, 101, "Draft: OAuth 2 PKCE sign-in", "Explores browser sign-in for M3.", "opened", true,
            "feat/oauth-pkce", "main", marco, listOf(me), emptyList(), listOf("security"), ago(60 * 24 * 3), ago(60 * 24),
            references = References("!39", "!39", "routeforge/gitlabio!39"), detailedMergeStatus = "draft_status", changesCount = "5"),
        MergeRequest(5040, 40, 101, "Verify TestFlight tester membership", "Uses the internal group member endpoint.", "merged", false,
            "fix/testflight-group-verification", "main", sora, emptyList(), listOf(me), listOf("ci"), ago(60 * 24 * 2), ago(60 * 30),
            mergedAt = ago(60 * 30), references = References("!40", "!40", "routeforge/gitlabio!40"), changesCount = "1"),
        MergeRequest(6012, 12, 102, "Add Windows runner template", "PowerShell job template with Visual Studio build tools.", "opened", false,
            "feat/windows", "main", sora, listOf(me), listOf(me), listOf("windows"), ago(60 * 8), ago(60 * 4),
            references = References("!12", "!12", "routeforge/cirrus!12"), detailedMergeStatus = "mergeable",
            headPipeline = Pipeline(7002, 88, 102, "failed", "feat/windows", sha("p7002"), "push", ago(60 * 4)), changesCount = "4"),
    )
    private val approvals = mutableMapOf(5042L to setOf(lin.id), 5041L to emptySet<Long>(), 6012L to emptySet())

    private val issues = mutableListOf(
        Issue(8057, 57, 101, "Pipeline log viewer should follow running jobs", "When a job is running the log should scroll with new output, like the web UI.\n\n- [ ] auto-follow toggle\n- [ ] ANSI colors",
            "opened", lin, listOf(me), listOf("ci", "enhancement"), ago(60 * 26), ago(60 * 3), references = References("#57", "#57", "routeforge/gitlabio#57"), userNotesCount = 2),
        Issue(8056, 56, 101, "Support self-signed certificates per account", "Self-managed instances often use an internal CA. Allow importing it per account, or pinning the leaf certificate.",
            "opened", marco, listOf(me), listOf("security"), ago(60 * 50), ago(60 * 5), references = References("#56", "#56", "routeforge/gitlabio#56"), userNotesCount = 1),
        Issue(8054, 54, 101, "Dark mode contrast for diff lines", "Removed lines are hard to read on OLED black.", "opened", sora, listOf(lin),
            listOf("ui", "accessibility"), ago(60 * 24 * 4), ago(60 * 24), references = References("#54", "#54", "routeforge/gitlabio#54")),
        Issue(8055, 55, 101, "Crash when README contains tables", "Fixed by switching to commonmark.", "closed", lin, listOf(lin), listOf("bug"),
            ago(60 * 24 * 6), ago(60 * 24 * 5), ago(60 * 24 * 5), references = References("#55", "#55", "routeforge/gitlabio#55")),
        Issue(9008, 8, 102, "Document the dependency cache warm-up", "Explain how the runner cache is reused between jobs.", "opened", marco, listOf(me),
            listOf("docs"), ago(60 * 24 * 2), ago(60 * 24), references = References("#8", "#8", "routeforge/cirrus#8")),
    )

    private val discussions = mutableMapOf<String, MutableList<Discussion>>(
        "mr-5042" to mutableListOf(
            Discussion("d1", true, listOf(Note(1, "requested review from @lin.yue", me, ago(60 * 5), system = true))),
            Discussion("d2", false, listOf(
                Note(2, "The navigation rail looks great on the tablet. Could the pipeline graph scroll horizontally on phones?", lin, ago(60 * 3), resolvable = true,
                    position = NotePosition("android/app/src/main/kotlin/PipelineScreens.kt", null, 48, null)),
                Note(3, "Done — stages are columns in a horizontal scroller now.", me, ago(60 * 2), resolvable = true),
            )),
            Discussion("d3", true, listOf(Note(4, "approved this merge request", lin, ago(40), system = true))),
        ),
        "mr-5041" to mutableListOf(
            Discussion("d4", true, listOf(Note(5, "Screenshots are attached to the pipeline artifacts.", lin, ago(60 * 19)))),
            Discussion("d5", true, listOf(Note(6, "Looks good, one nit about the inbox empty state.", sora, ago(60 * 4)))),
        ),
        "issue-8057" to mutableListOf(
            Discussion("d6", true, listOf(Note(7, "assigned to @felix", lin, ago(60 * 26), system = true))),
            Discussion("d7", true, listOf(Note(8, "Polling every few seconds is fine for now; GitLab has no streaming trace API.", me, ago(60 * 3)))),
        ),
    )
    private fun discussionKey(project: Long, iid: Long, kind: Noteable): String = when (kind) {
        Noteable.MERGE_REQUEST -> "mr-" + (mergeRequests.firstOrNull { it.projectId == project && it.iid == iid }?.id ?: iid)
        Noteable.ISSUE -> "issue-" + (issues.firstOrNull { it.projectId == project && it.iid == iid }?.id ?: iid)
    }

    private val pipelines = mutableListOf(
        Pipeline(9001, 311, 101, "running", "feat/android-redesign", sha("p9001"), "merge_request_event", ago(20), ago(1), ago(19), null, user = me),
        Pipeline(9000, 310, 101, "success", "feat/ios-liquid-glass", sha("p9000"), "merge_request_event", ago(60 * 3), ago(60 * 3 - 14), ago(60 * 3), ago(60 * 3 - 14), duration = 812.0, user = lin),
        Pipeline(8999, 309, 101, "failed", "fix/token-scope-warning", sha("p8999"), "push", ago(60 * 7), ago(60 * 7 - 6), ago(60 * 7), ago(60 * 7 - 6), duration = 341.0, user = marco),
        Pipeline(8998, 308, 101, "success", "main", sha("p8998"), "push", ago(60 * 9), ago(60 * 9 - 15), ago(60 * 9), ago(60 * 9 - 15), duration = 903.0, user = me),
        Pipeline(8997, 307, 101, "canceled", "feat/oauth-pkce", sha("p8997"), "push", ago(60 * 24), ago(60 * 24 - 2), user = marco),
        Pipeline(7002, 88, 102, "failed", "feat/windows", sha("p7002"), "push", ago(60 * 4), ago(60 * 4 - 9), duration = 540.0, user = sora),
        Pipeline(7001, 87, 102, "success", "main", sha("p7001"), "push", ago(60 * 30), ago(60 * 30 - 7), duration = 420.0, user = marco),
        Pipeline(6001, 51, 103, "success", "main", sha("p6001"), "schedule", ago(60 * 26), ago(60 * 26 - 22), duration = 1320.0),
    )

    private val jobs = mutableMapOf<Long, MutableList<Job>>()
    private fun jobsOf(pipeline: Pipeline) = jobs.getOrPut(pipeline.id) {
        val layout = listOf(
            "build" to "lint", "build" to "assemble", "test" to "core-tests", "test" to "screenshots", "test" to "apple", "publish" to "testflight",
        )
        layout.mapIndexed { index, (stage, name) ->
            val status = when (pipeline.status) {
                "running" -> listOf("success", "success", "running", "pending", "success", "manual")[index]
                "failed" -> listOf("success", "success", "failed", "success", "success", "skipped")[index]
                "canceled" -> listOf("success", "canceled", "canceled", "canceled", "canceled", "skipped")[index]
                else -> if (stage == "publish") "manual" else "success"
            }
            val finished = status in setOf("success", "failed", "canceled")
            Job(pipeline.id * 10 + index, name, status, stage, pipeline.ref, pipeline.createdAt,
                startedAt = if (status == "pending" || status == "manual" || status == "skipped") null else ago(18L - index),
                finishedAt = if (finished) ago(12L - index) else null, duration = if (finished) 95.0 + index * 31 else null,
                allowFailure = name == "screenshots", pipeline = JobPipeline(pipeline.id, pipeline.ref, pipeline.status), user = pipeline.user)
        }.toMutableList()
    }
    private fun findJob(id: Long): Pair<Pipeline, Job> {
        val pipeline = pipelines.firstOrNull { it.id == id / 10 } ?: throw ApiException(404)
        return pipeline to (jobsOf(pipeline).firstOrNull { it.id == id } ?: throw ApiException(404))
    }

    private val todos = mutableListOf(
        Todo(1, "Review requested", "pending", "review_requested", "MergeRequest", "https://gitlab.example.test/routeforge/gitlabio/-/merge_requests/41",
            TodoTarget(41, "iOS: Liquid Glass tab bar and inbox", "opened"), lin, TodoProject(101, "gitlabio", "routeforge/gitlabio"), ago(60 * 2)),
        Todo(2, "@felix could you check the ANSI parser?", "pending", "mentioned", "Issue", "https://gitlab.example.test/routeforge/gitlabio/-/issues/57",
            TodoTarget(57, "Pipeline log viewer should follow running jobs", "opened"), lin, TodoProject(101, "gitlabio", "routeforge/gitlabio"), ago(60 * 3)),
        Todo(3, "Assigned to you", "pending", "assigned", "MergeRequest", "https://gitlab.example.test/routeforge/cirrus/-/merge_requests/12",
            TodoTarget(12, "Add Windows runner template", "opened"), sora, TodoProject(102, "cirrus", "routeforge/cirrus"), ago(60 * 4)),
        Todo(4, "Pipeline failed", "pending", "build_failed", "MergeRequest", "https://gitlab.example.test/routeforge/cirrus/-/merge_requests/12",
            TodoTarget(12, "Add Windows runner template", "opened"), sora, TodoProject(102, "cirrus", "routeforge/cirrus"), ago(60 * 4 - 9)),
        Todo(5, "Assigned to you", "pending", "assigned", "Issue", "https://gitlab.example.test/routeforge/gitlabio/-/issues/56",
            TodoTarget(56, "Support self-signed certificates per account", "opened"), marco, TodoProject(101, "gitlabio", "routeforge/gitlabio"), ago(60 * 5)),
    )

    private fun projectOf(id: Long) = projects.firstOrNull { it.id == id } ?: throw ApiException(404)
    private fun <T> paged(items: List<T>, page: Int, size: Int = 50): Page<T> {
        val from = (page - 1) * size
        return Page(items.drop(from).take(size), if (items.size > from + size) page + 1 else null)
    }
    private fun mr(project: Long, iid: Long) = mergeRequests.firstOrNull { it.projectId == project && it.iid == iid } ?: throw ApiException(404)
    private fun issueOf(project: Long, iid: Long) = issues.firstOrNull { it.projectId == project && it.iid == iid } ?: throw ApiException(404)
    private fun replaceMr(updated: MergeRequest) = updated.also { mergeRequests[mergeRequests.indexOfFirst { it.id == updated.id }] = updated }
    private fun replaceIssue(updated: Issue) = updated.also { issues[issues.indexOfFirst { it.id == updated.id }] = updated }

    fun isStarred(project: Long) = synchronized(lock) { project in starred }

    override suspend fun currentUser() = io { me }
    override suspend fun tokenInfo() = io { TokenInfo(1, "Demo", listOf("api", "read_user")) }

    override suspend fun projects(query: ProjectQuery, page: Int) = io {
        val filtered = projects.filter { project ->
            when (query.filter) {
                ProjectFilter.MEMBERSHIP -> true
                ProjectFilter.STARRED -> project.id in starred
                ProjectFilter.OWNED -> project.namespace?.kind == "user"
            } && (query.search.isBlank() || project.pathWithNamespace.contains(query.search.trim(), ignoreCase = true))
        }
        val sorted = when (query.sort) {
            ProjectSort.ACTIVITY -> filtered.sortedByDescending { it.lastActivityAt }
            ProjectSort.NAME -> filtered.sortedBy { it.name.lowercase() }
            ProjectSort.CREATED -> filtered.sortedByDescending { it.id }
        }
        paged(sorted, page)
    }

    override suspend fun project(id: Long) = io { projectOf(id) }
    override suspend fun languages(project: Long) = io {
        if (project == 101L) mapOf("Kotlin" to 46.2, "Swift" to 38.5, "Shell" to 8.1, "Python" to 5.0, "Ruby" to 2.2) else mapOf("Shell" to 71.0, "Dockerfile" to 29.0)
    }

    override suspend fun setStarred(project: Long, starred: Boolean) = io {
        val current = projectOf(project)
        val changed = if (starred) this.starred.add(project) else this.starred.remove(project)
        val updated = if (changed) current.copy(starCount = current.starCount + if (starred) 1 else -1) else current
        projects = projects.map { if (it.id == project) updated else it }
        updated
    }

    override suspend fun readme(project: Long, ref: String) = io {
        filesOf(project)["README.md"]?.let { RepositoryFile.ofText("README.md", it, commitsOf(project).first().id, ref) }
    }

    override suspend fun branches(project: Long, search: String?, page: Int) = io {
        paged(branchesOf(project).filter { search.isNullOrBlank() || it.name.contains(search.trim(), true) }, page)
    }

    override suspend fun createBranch(project: Long, name: String, ref: String) = io {
        require(name.isNotBlank()) { "请填写分支名称。" }
        if (branchesOf(project).any { it.name == name }) throw ApiException(400)
        val branch = Branch(name.trim(), canPush = true, commit = branchesOf(project).firstOrNull { it.name == ref }?.commit ?: commitsOf(project).first())
        branchesOf(project).add(branch)
        branch
    }

    override suspend fun deleteBranch(project: Long, name: String) = io {
        val branch = branchesOf(project).firstOrNull { it.name == name } ?: throw ApiException(404)
        if (branch.protected || branch.default) throw ApiException(403)
        branchesOf(project).remove(branch)
        Unit
    }

    override suspend fun tree(project: Long, ref: String, path: String, page: Int) = io {
        val prefix = if (path.isEmpty()) "" else "$path/"
        val entries = filesOf(project).keys.filter { it.startsWith(prefix) }.map { it.removePrefix(prefix) }.map { rest ->
            val name = rest.substringBefore('/')
            TreeEntry(sha(prefix + name), name, prefix + name, if ('/' in rest) "tree" else "blob")
        }.distinctBy { it.path }.sortedWith(compareBy({ !it.isDirectory }, { it.name.lowercase() }))
        if (entries.isEmpty() && path.isNotEmpty()) throw ApiException(404)
        paged(entries, page, 100)
    }

    override suspend fun file(project: Long, ref: String, path: String) = io {
        val text = filesOf(project)[path] ?: throw ApiException(404)
        RepositoryFile.ofText(path, text, commitsOf(project).first().id, ref)
    }

    override suspend fun commitChanges(project: Long, branch: String, message: String, actions: List<CommitAction>, startBranch: String?) = io {
        require(message.isNotBlank()) { "请填写提交说明。" }
        require(actions.isNotEmpty()) { "没有要提交的更改。" }
        if (startBranch != null) {
            if (branchesOf(project).any { it.name == branch }) throw ApiException(400)
            branchesOf(project).add(Branch(branch, canPush = true))
        } else if (branchesOf(project).none { it.name == branch }) throw ApiException(400)
        val tree = filesOf(project)
        for (action in actions) when (action.action) {
            "create", "update" -> tree[action.filePath] = action.content.orEmpty()
            "delete" -> tree.remove(action.filePath)
            "move" -> action.previousPath?.let { tree.remove(it) }?.let { tree[action.filePath] = action.content ?: it }
        }
        val id = sha("$project-${commitsOf(project).size}-$message")
        val commit = Commit(id, id.take(8), message.lineSequence().first(), message, me.name, "felix@example.test", now.toString(), now.toString(), now.toString(),
            stats = CommitStats(actions.size * 4, actions.size, actions.size * 5))
        commitsOf(project).add(0, commit)
        val index = branchesOf(project).indexOfFirst { it.name == branch }
        branchesOf(project)[index] = branchesOf(project)[index].copy(commit = commit)
        commit
    }

    override suspend fun commits(project: Long, ref: String, path: String?, page: Int) = io { paged(commitsOf(project).toList(), page) }
    override suspend fun commit(project: Long, sha: String) = io { commitsOf(project).firstOrNull { it.id == sha } ?: throw ApiException(404) }
    override suspend fun commitDiff(project: Long, sha: String, page: Int) = io { paged(DIFFS, page) }

    override suspend fun mergeRequests(query: WorkQuery, page: Int) = io {
        paged(mergeRequests.filter { mr ->
            (query.project == null || mr.projectId == query.project) &&
                (query.state == "all" || mr.state == query.state) &&
                when (query.scope) {
                    WorkScope.ALL -> true
                    WorkScope.ASSIGNED -> mr.assignees.any { it.id == me.id }
                    WorkScope.CREATED -> mr.author?.id == me.id
                } && (query.reviewer == null || mr.reviewers.any { it.username == query.reviewer }) &&
                (query.search.isBlank() || mr.title.contains(query.search.trim(), true))
        }.sortedByDescending { it.updatedAt }, page)
    }

    override suspend fun mergeRequest(project: Long, iid: Long) = io { mr(project, iid) }

    override suspend fun approvals(project: Long, iid: Long) = io {
        val request = mr(project, iid)
        val by = approvals[request.id].orEmpty()
        val users = listOf(me, lin, marco, sora).filter { it.id in by }
        Approvals(by.isNotEmpty(), 1, if (by.isEmpty()) 1 else 0, users.map(::ApprovalUser), me.id in by, request.author?.id != me.id && request.state == "opened")
    }

    override suspend fun setApproved(project: Long, iid: Long, approved: Boolean) = io {
        val request = mr(project, iid)
        if (request.author?.id == me.id) throw ApiException(401)
        val current = approvals[request.id].orEmpty()
        approvals[request.id] = if (approved) current + me.id else current - me.id
        Unit
    }

    override suspend fun merge(project: Long, iid: Long, options: MergeOptions) = io {
        val request = mr(project, iid)
        if (request.state != "opened" || request.draft || request.hasConflicts) throw ApiException(405)
        if (options.removeSourceBranch) branchesOf(project).removeAll { it.name == request.sourceBranch }
        replaceMr(request.copy(state = "merged", mergedAt = now.toString(), updatedAt = now.toString(), squash = options.squash, detailedMergeStatus = null))
    }

    override suspend fun createMergeRequest(project: Long, draft: MergeRequestDraft) = io {
        require(draft.title.isNotBlank()) { "请填写标题。" }
        require(draft.sourceBranch != draft.targetBranch) { "源分支和目标分支不能相同。" }
        val iid = (mergeRequests.filter { it.projectId == project }.maxOfOrNull { it.iid } ?: 0) + 1
        val path = projectOf(project).pathWithNamespace
        val created = MergeRequest(project * 1000 + iid, iid, project, if (draft.draft) "Draft: ${draft.title}" else draft.title, draft.description, "opened", draft.draft,
            draft.sourceBranch, draft.targetBranch, me, listOf(me), emptyList(), emptyList(), now.toString(), now.toString(),
            references = References("!$iid", "!$iid", "$path!$iid"), detailedMergeStatus = if (draft.draft) "draft_status" else "mergeable",
            squash = draft.squash, forceRemoveSourceBranch = draft.removeSourceBranch, changesCount = "1")
        mergeRequests.add(0, created)
        created
    }

    override suspend fun mergeRequestDiffs(project: Long, iid: Long, page: Int) = io { mr(project, iid); paged(DIFFS, page, 30) }

    override suspend fun discussions(project: Long, iid: Long, kind: Noteable, page: Int) = io {
        paged(discussions[discussionKey(project, iid, kind)].orEmpty().toList(), page)
    }

    override suspend fun addNote(project: Long, iid: Long, kind: Noteable, body: String) = io {
        require(body.isNotBlank()) { "评论不能为空。" }
        val note = Note(System.nanoTime(), body.trim(), me, now.toString())
        discussions.getOrPut(discussionKey(project, iid, kind)) { mutableListOf() }.add(Discussion("n${note.id}", true, listOf(note)))
        note
    }

    override suspend fun issues(query: WorkQuery, page: Int) = io {
        paged(issues.filter { issue ->
            (query.project == null || issue.projectId == query.project) &&
                (query.state == "all" || issue.state == query.state) &&
                when (query.scope) {
                    WorkScope.ALL -> true
                    WorkScope.ASSIGNED -> issue.assignees.any { it.id == me.id }
                    WorkScope.CREATED -> issue.author?.id == me.id
                } && (query.search.isBlank() || issue.title.contains(query.search.trim(), true))
        }.sortedByDescending { it.updatedAt }, page)
    }

    override suspend fun issue(project: Long, iid: Long) = io { issueOf(project, iid) }

    override suspend fun createIssue(project: Long, draft: IssueDraft) = io {
        require(draft.title.isNotBlank()) { "请填写标题。" }
        val iid = (issues.filter { it.projectId == project }.maxOfOrNull { it.iid } ?: 0) + 1
        val path = projectOf(project).pathWithNamespace
        val created = Issue(project * 1000 + iid, iid, project, draft.title.trim(), draft.description, "opened", me, emptyList(), draft.labels,
            now.toString(), now.toString(), references = References("#$iid", "#$iid", "$path#$iid"), confidential = draft.confidential)
        issues.add(0, created)
        created
    }

    override suspend fun updateIssue(project: Long, iid: Long, draft: IssueDraft) = io {
        require(draft.title.isNotBlank()) { "请填写标题。" }
        replaceIssue(issueOf(project, iid).copy(title = draft.title.trim(), description = draft.description, labels = draft.labels,
            confidential = draft.confidential, updatedAt = now.toString()))
    }

    override suspend fun setIssueOpen(project: Long, iid: Long, open: Boolean) = io {
        replaceIssue(issueOf(project, iid).copy(state = if (open) "opened" else "closed", closedAt = if (open) null else now.toString(), updatedAt = now.toString()))
    }

    override suspend fun pipelines(project: Long, status: String?, ref: String?, page: Int) = io {
        paged(pipelines.filter { it.projectId == project && (status == null || it.status == status) && (ref == null || it.ref == ref) }, page)
    }

    override suspend fun pipeline(project: Long, id: Long) = io { pipelines.firstOrNull { it.id == id && it.projectId == project } ?: throw ApiException(404) }
    override suspend fun pipelineJobs(project: Long, pipeline: Long) = io { jobsOf(pipelines.first { it.id == pipeline }).toList() }

    override suspend fun triggerPipeline(project: Long, ref: String, variables: List<PipelineVariable>) = io {
        require(ref.isNotBlank()) { "请选择分支或标签。" }
        val id = (pipelines.maxOf { it.id }) + 1
        val created = Pipeline(id, id - 8690, project, "pending", ref, commitsOf(project).first().id, "api", now.toString(), now.toString(), user = me)
        pipelines.add(0, created)
        created
    }

    override suspend fun pipelineAction(project: Long, id: Long, action: PipelineAction) = io {
        val index = pipelines.indexOfFirst { it.id == id }
        if (index < 0) throw ApiException(404)
        val status = if (action == PipelineAction.RETRY) "running" else "canceled"
        pipelines[index] = pipelines[index].copy(status = status, updatedAt = now.toString())
        jobs[id] = jobsOf(pipelines[index]).map { job ->
            when {
                action == PipelineAction.CANCEL && isActiveStatus(job.status) -> job.copy(status = "canceled")
                action == PipelineAction.RETRY && job.status in setOf("failed", "canceled") -> job.copy(status = "pending", finishedAt = null)
                else -> job
            }
        }.toMutableList()
        pipelines[index]
    }

    override suspend fun job(project: Long, id: Long) = io { findJob(id).second }

    override suspend fun jobAction(project: Long, id: Long, action: JobAction) = io {
        val (pipeline, job) = findJob(id)
        val updated = job.copy(status = when (action) {
            JobAction.CANCEL -> "canceled"
            JobAction.PLAY, JobAction.RETRY -> "pending"
        }, finishedAt = null)
        val list = jobsOf(pipeline)
        list[list.indexOfFirst { it.id == id }] = updated
        updated
    }

    override suspend fun jobTrace(project: Long, id: Long) = io {
        val (_, job) = findJob(id)
        JobTrace(trace(job), false)
    }

    override suspend fun todos(page: Int) = io { paged(todos.filter { it.state == "pending" }, page) }
    override suspend fun markTodoDone(id: Long) = io {
        val index = todos.indexOfFirst { it.id == id }
        if (index >= 0) todos[index] = todos[index].copy(state = "done")
        Unit
    }
    override suspend fun markAllTodosDone() = io { todos.replaceAll { it.copy(state = "done") } }

    private fun trace(job: Job): String {
        val e = "\u001B"
        val header = "${e}[0KRunning with gitlab-runner 17.5.2 (demo)\n${e}[0K  on ci-linux demo, system ID: s_demo\n" +
            "section_start:1730000000:prepare_executor\r${e}[0K${e}[0K${e}[36;1mPreparing the \"docker\" executor${e}[0;m\n" +
            "${e}[0KUsing Docker executor with image gitlab-ci-linux:latest ...\n" +
            "section_end:1730000004:prepare_executor\r${e}[0K\n" +
            "section_start:1730000005:get_sources\r${e}[0K${e}[0K${e}[36;1mGetting source from Git repository${e}[0;m\n" +
            "${e}[32;1mFetching changes with git depth set to 20...${e}[0;m\nInitialized empty Git repository\n${e}[32;1mChecking out ${job.ref ?: "main"}...${e}[0;m\n" +
            "section_end:1730000008:get_sources\r${e}[0K\n" +
            "section_start:1730000009:step_script\r${e}[0K${e}[0K${e}[36;1mExecuting \"step_script\" stage of the job script${e}[0;m\n" +
            "${e}[32;1m$ bash scripts/ci-android.sh${e}[0;m\n"
        val body = when (job.status) {
            "failed" -> "> Task :core:compileKotlin\n> Task :core:test\n\nGitLabClientTest > redirectsDoNotForwardCredentials ${e}[32mPASSED${e}[0m\n" +
                "GitLabClientTest > trustPolicyRejectsUnknownCa ${e}[31;1mFAILED${e}[0m\n    java.lang.AssertionError: expected SSLHandshakeException\n\n" +
                "${e}[31;1m42 tests completed, 1 failed${e}[0m\n\n${e}[31;1mFAILURE: Build failed with an exception.${e}[0m\n" +
                "section_end:1730000300:step_script\r${e}[0K\n${e}[31;1mERROR: Job failed: exit code 1\n${e}[0;m\n"
            "running", "pending" -> "> Task :core:compileKotlin\n> Task :core:compileTestKotlin\n> Task :core:test\n" +
                "GitLabClientTest > projectDecodeAndPagination ${e}[32mPASSED${e}[0m\nGitLabClientTest > redirectsDoNotForwardCredentials ${e}[32mPASSED${e}[0m\n" +
                "AnsiParserTest > keepsColorsAndDropsSections ${e}[32mPASSED${e}[0m\n${e}[33mDownloading https://repo.example.test/robolectric/android-all-instrumented 34%${e}[0m\r" +
                "${e}[33mDownloading https://repo.example.test/robolectric/android-all-instrumented 87%${e}[0m\n"
            else -> "> Task :core:test\n> Task :app:assembleDebug\n> Task :app:lintDebug\n\n${e}[32;1mBUILD SUCCESSFUL${e}[0m in 3m 12s\n" +
                "87 actionable tasks: 87 executed\nsection_end:1730000200:step_script\r${e}[0K\n${e}[32;1mJob succeeded${e}[0;m\n"
        }
        return header + body
    }

    companion object {
        fun sha(seed: String): String = MessageDigest.getInstance("SHA-1").digest(seed.toByteArray()).joinToString("") { "%02x".format(it) }

        private val DIFFS = listOf(
            FileDiff("android/app/build.gradle.kts", "android/app/build.gradle.kts", """
                @@ -24,9 +24,14 @@ dependencies {
                     implementation(project(":core"))
                -    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
                +    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
                     implementation("androidx.compose.material3:material3")
                +    implementation("androidx.compose.material3:material3-adaptive-navigation-suite")
                +    implementation("androidx.navigation:navigation-compose:2.8.5")
                +    implementation("androidx.work:work-runtime-ktx:2.10.0")
                     implementation("androidx.activity:activity-compose:1.9.3")
                -    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
                +    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
            """.trimIndent() + "\n"),
            FileDiff("android/app/src/main/kotlin/PipelineScreens.kt", "android/app/src/main/kotlin/PipelineScreens.kt", """
                @@ -40,12 +40,18 @@ fun PipelineGraph(jobs: List<Job>) {
                -    Column {
                -        jobs.forEach { JobRow(it) }
                +    val stages = jobs.groupBy { it.stage }
                +    Row(Modifier.horizontalScroll(rememberScrollState())) {
                +        stages.forEach { (stage, stageJobs) ->
                +            StageColumn(stage, stageJobs, onOpen)
                +        }
                     }
                 }

                 @Composable
                -private fun JobRow(job: Job) = Text(job.name)
                +private fun StageColumn(stage: String, jobs: List<Job>, onOpen: (Job) -> Unit) {
                +    // One column per stage, jobs stacked as cards
            """.trimIndent() + "\n"),
            FileDiff("docs/legacy.md", "docs/legacy.md", "@@ -1,3 +0,0 @@\n-# Legacy\n-\n-Old Compose screens.\n", deletedFile = true),
        )

        private val README = """
            # Gitlabio

            A native client for **gitlab.com** and self-managed GitLab, written in *Kotlin* and *Swift*.

            ## Features

            - Multiple accounts and instances, with per-account certificate trust
            - Code browsing with syntax highlighting and a change basket
            - Merge requests: discussions, diffs, approvals and merging
            - Pipelines with stage graphs and live job logs
            - A to-do inbox with background notifications

            ## Build

            ```bash
            cd android
            ./gradlew :core:test :app:assembleDebug
            ```

            | Platform | UI | Minimum |
            | --- | --- | --- |
            | Android | Jetpack Compose | 8.0 |
            | iOS | SwiftUI | 17 |

            > Demo data is synthetic. See [the plan](docs/PLAN.md) for milestones.
        """.trimIndent() + "\n"

        private val CI_YAML = """
            stages: [verify, publish]

            android:
              stage: verify
              tags: [linux]
              timeout: 40m
              script:
                - bash scripts/ci-android.sh
              artifacts:
                when: always
                paths: [dist/android/, reports/android/]
        """.trimIndent() + "\n"

        private val GRADLE = """
            plugins {
                id("com.android.application") version "8.7.2" apply false
                kotlin("android") version "2.1.21" apply false
            }
        """.trimIndent() + "\n"

        private val KOTLIN = """
            package zone.routeforge.gitlabio.core

            import okhttp3.OkHttpClient

            /** Talks to the GitLab REST API v4. */
            class GitLabClient(private val token: String) {
                private val http = OkHttpClient.Builder()
                    .followRedirects(false) // never replay the token elsewhere
                    .build()

                suspend fun projects(page: Int = 1): List<Project> {
                    val url = "https://gitlab.com/api/v4/projects?page=${'$'}page"
                    return get(url).decode()
                }

                @Deprecated("Use projects()")
                fun legacy(): Int = 42
            }
        """.trimIndent() + "\n"

        private val MANIFEST = """
            <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                <!-- Tokens never leave the device backup -->
                <application android:allowBackup="false" android:label="Gitlabio">
                    <activity android:name=".MainActivity" android:exported="true" />
                </application>
            </manifest>
        """.trimIndent() + "\n"

        private val SWIFT = """
            import SwiftUI

            @main
            struct GitlabioApp: App {
                @State private var accounts = AccountStore()

                var body: some Scene {
                    WindowGroup {
                        RootView()
                            .environment(accounts)
                    }
                }
            }
        """.trimIndent() + "\n"
    }
}
