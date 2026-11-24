package zone.routeforge.gitlabio.core

/** Everything the app reads or changes on a GitLab instance; implemented over HTTP and by the offline demo. */
interface GitLabApi {
    suspend fun currentUser(): User
    /** Scopes of the token in use, or null when the instance cannot report them (older GitLab, non-PAT tokens). */
    suspend fun tokenInfo(): TokenInfo?

    suspend fun projects(query: ProjectQuery = ProjectQuery(), page: Int = 1): Page<Project>
    suspend fun project(id: Long): Project
    suspend fun languages(project: Long): Map<String, Double>
    suspend fun setStarred(project: Long, starred: Boolean): Project
    /** The README at the root of [ref], or null when the repository has none. */
    suspend fun readme(project: Long, ref: String): RepositoryFile?

    suspend fun branches(project: Long, search: String? = null, page: Int = 1): Page<Branch>
    suspend fun createBranch(project: Long, name: String, ref: String): Branch
    suspend fun deleteBranch(project: Long, name: String)

    suspend fun tree(project: Long, ref: String, path: String, page: Int = 1): Page<TreeEntry>
    suspend fun file(project: Long, ref: String, path: String): RepositoryFile
    /** Commits several file changes at once; [startBranch] creates [branch] from it first. */
    suspend fun commitChanges(project: Long, branch: String, message: String, actions: List<CommitAction>, startBranch: String? = null): Commit
    suspend fun commits(project: Long, ref: String, path: String? = null, page: Int = 1): Page<Commit>
    suspend fun commit(project: Long, sha: String): Commit
    suspend fun commitDiff(project: Long, sha: String, page: Int = 1): Page<FileDiff>

    suspend fun mergeRequests(query: WorkQuery, page: Int = 1): Page<MergeRequest>
    suspend fun mergeRequest(project: Long, iid: Long): MergeRequest
    suspend fun approvals(project: Long, iid: Long): Approvals
    suspend fun setApproved(project: Long, iid: Long, approved: Boolean)
    suspend fun merge(project: Long, iid: Long, options: MergeOptions): MergeRequest
    suspend fun createMergeRequest(project: Long, draft: MergeRequestDraft): MergeRequest
    suspend fun mergeRequestDiffs(project: Long, iid: Long, page: Int = 1): Page<FileDiff>

    suspend fun discussions(project: Long, iid: Long, kind: Noteable, page: Int = 1): Page<Discussion>
    suspend fun addNote(project: Long, iid: Long, kind: Noteable, body: String): Note

    suspend fun issues(query: WorkQuery, page: Int = 1): Page<Issue>
    suspend fun issue(project: Long, iid: Long): Issue
    suspend fun createIssue(project: Long, draft: IssueDraft): Issue
    suspend fun updateIssue(project: Long, iid: Long, draft: IssueDraft): Issue
    suspend fun setIssueOpen(project: Long, iid: Long, open: Boolean): Issue

    suspend fun pipelines(project: Long, status: String? = null, ref: String? = null, page: Int = 1): Page<Pipeline>
    suspend fun pipeline(project: Long, id: Long): Pipeline
    /** All current (non-retried) jobs of a pipeline, across pages. */
    suspend fun pipelineJobs(project: Long, pipeline: Long): List<Job>
    suspend fun triggerPipeline(project: Long, ref: String, variables: List<PipelineVariable>): Pipeline
    suspend fun pipelineAction(project: Long, id: Long, action: PipelineAction): Pipeline
    suspend fun job(project: Long, id: Long): Job
    suspend fun jobAction(project: Long, id: Long, action: JobAction): Job
    suspend fun jobTrace(project: Long, id: Long): JobTrace

    suspend fun todos(page: Int = 1): Page<Todo>
    suspend fun markTodoDone(id: Long)
    suspend fun markAllTodosDone()
}

enum class ProjectFilter { MEMBERSHIP, STARRED, OWNED }

enum class ProjectSort(val orderBy: String) { ACTIVITY("last_activity_at"), NAME("name"), CREATED("created_at") }

data class ProjectQuery(
    val search: String = "",
    val filter: ProjectFilter = ProjectFilter.MEMBERSHIP,
    val sort: ProjectSort = ProjectSort.ACTIVITY,
)

/** Filters shared by the issue and merge request lists; [project] null means across all projects. */
data class WorkQuery(
    val project: Long? = null,
    val state: String = "opened",
    val scope: WorkScope = WorkScope.ALL,
    val reviewer: String? = null,
    val search: String = "",
)

enum class WorkScope(val value: String) { ALL("all"), ASSIGNED("assigned_to_me"), CREATED("created_by_me") }

enum class Noteable(val path: String) { ISSUE("issues"), MERGE_REQUEST("merge_requests") }

data class MergeOptions(
    val squash: Boolean = false,
    val removeSourceBranch: Boolean = false,
    val commitMessage: String? = null,
    val sha: String? = null,
)

data class MergeRequestDraft(
    val sourceBranch: String,
    val targetBranch: String,
    val title: String,
    val description: String = "",
    val draft: Boolean = false,
    val removeSourceBranch: Boolean = true,
    val squash: Boolean = false,
)

data class IssueDraft(
    val title: String,
    val description: String = "",
    val labels: List<String> = emptyList(),
    val confidential: Boolean = false,
)

enum class PipelineAction(val path: String) { RETRY("retry"), CANCEL("cancel") }

enum class JobAction(val path: String) { RETRY("retry"), CANCEL("cancel"), PLAY("play") }

/** Job log text; [truncated] means only the tail was kept. */
data class JobTrace(val text: String, val truncated: Boolean)

/** True for statuses that will still change on their own, so screens keep refreshing. */
fun isActiveStatus(status: String) = status in setOf("created", "waiting_for_resource", "preparing", "pending", "running")
