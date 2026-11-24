package zone.routeforge.gitlabio.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.Base64

@Serializable data class User(
    val id: Long,
    val username: String,
    val name: String,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("web_url") val webUrl: String? = null,
)

@Serializable data class TokenInfo(
    val id: Long,
    val name: String,
    val scopes: List<String> = emptyList(),
    val active: Boolean = true,
    val revoked: Boolean = false,
    @SerialName("expires_at") val expiresAt: String? = null,
)

@Serializable data class Namespace(
    val id: Long,
    val name: String,
    val path: String,
    val kind: String? = null,
    @SerialName("full_path") val fullPath: String? = null,
)

@Serializable data class ProjectStatistics(
    @SerialName("commit_count") val commitCount: Long = 0,
    @SerialName("storage_size") val storageSize: Long = 0,
    @SerialName("repository_size") val repositorySize: Long = 0,
)

@Serializable data class Project(
    val id: Long,
    val name: String,
    @SerialName("path_with_namespace") val pathWithNamespace: String,
    @SerialName("name_with_namespace") val nameWithNamespace: String? = null,
    val description: String? = null,
    @SerialName("default_branch") val defaultBranch: String? = null,
    @SerialName("web_url") val webUrl: String? = null,
    val visibility: String? = null,
    @SerialName("star_count") val starCount: Int = 0,
    @SerialName("forks_count") val forksCount: Int = 0,
    @SerialName("open_issues_count") val openIssuesCount: Int? = null,
    @SerialName("last_activity_at") val lastActivityAt: String? = null,
    val archived: Boolean = false,
    val topics: List<String> = emptyList(),
    val namespace: Namespace? = null,
    val statistics: ProjectStatistics? = null,
)

@Serializable data class CommitStats(val additions: Int = 0, val deletions: Int = 0, val total: Int = 0)

@Serializable data class Commit(
    val id: String,
    @SerialName("short_id") val shortId: String = id.take(8),
    val title: String = "",
    val message: String? = null,
    @SerialName("author_name") val authorName: String? = null,
    @SerialName("author_email") val authorEmail: String? = null,
    @SerialName("authored_date") val authoredDate: String? = null,
    @SerialName("committed_date") val committedDate: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("parent_ids") val parentIds: List<String> = emptyList(),
    @SerialName("web_url") val webUrl: String? = null,
    val stats: CommitStats? = null,
)

@Serializable data class Branch(
    val name: String,
    val protected: Boolean = false,
    val merged: Boolean = false,
    val default: Boolean = false,
    @SerialName("can_push") val canPush: Boolean = false,
    @SerialName("web_url") val webUrl: String? = null,
    val commit: Commit? = null,
)

@Serializable data class TreeEntry(
    val id: String,
    val name: String,
    val path: String,
    val type: String,
    val mode: String? = null,
) {
    val isDirectory get() = type == "tree"
}

@Serializable data class RepositoryFile(
    @SerialName("file_path") val filePath: String,
    val size: Long,
    val encoding: String,
    val content: String,
    @SerialName("last_commit_id") val lastCommitId: String,
    @SerialName("file_name") val fileName: String = filePath.substringAfterLast('/'),
    val ref: String? = null,
) {
    /** Decoded text when the file is UTF-8 without NUL bytes and at most 1 MiB; throws otherwise. */
    fun editableText(): String {
        require(size <= MAX_EDITABLE_BYTES) { "文件超过 1 MiB，当前版本不支持编辑。" }
        require(encoding == "base64") { "不支持此文件编码。" }
        val bytes = Base64.getDecoder().decode(content.filterNot(Char::isWhitespace))
        require(!bytes.contains(0.toByte())) { "该文件不是可编辑的 UTF-8 文本。" }
        return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString()
    }

    fun textOrNull(): String? = runCatching { editableText() }.getOrNull()

    companion object {
        const val MAX_EDITABLE_BYTES = 1_048_576L

        fun ofText(path: String, text: String, lastCommitId: String, ref: String? = null): RepositoryFile {
            val bytes = text.toByteArray(Charsets.UTF_8)
            return RepositoryFile(path, bytes.size.toLong(), "base64", Base64.getEncoder().encodeToString(bytes), lastCommitId, ref = ref)
        }
    }
}

@Serializable data class References(val short: String? = null, val relative: String? = null, val full: String? = null)

@Serializable data class Milestone(val id: Long, val title: String)

@Serializable data class MergeRequest(
    val id: Long,
    val iid: Long,
    @SerialName("project_id") val projectId: Long,
    val title: String,
    val description: String? = null,
    val state: String,
    val draft: Boolean = false,
    @SerialName("source_branch") val sourceBranch: String,
    @SerialName("target_branch") val targetBranch: String,
    val author: User? = null,
    val assignees: List<User> = emptyList(),
    val reviewers: List<User> = emptyList(),
    val labels: List<String> = emptyList(),
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("merged_at") val mergedAt: String? = null,
    @SerialName("web_url") val webUrl: String? = null,
    val references: References? = null,
    @SerialName("user_notes_count") val userNotesCount: Int = 0,
    @SerialName("has_conflicts") val hasConflicts: Boolean = false,
    @SerialName("detailed_merge_status") val detailedMergeStatus: String? = null,
    @SerialName("head_pipeline") val headPipeline: Pipeline? = null,
    val sha: String? = null,
    val squash: Boolean = false,
    @SerialName("force_remove_source_branch") val forceRemoveSourceBranch: Boolean? = null,
    @SerialName("changes_count") val changesCount: String? = null,
) {
    val reference get() = references?.full ?: references?.short ?: "!$iid"
}

@Serializable data class Issue(
    val id: Long,
    val iid: Long,
    @SerialName("project_id") val projectId: Long,
    val title: String,
    val description: String? = null,
    val state: String,
    val author: User? = null,
    val assignees: List<User> = emptyList(),
    val labels: List<String> = emptyList(),
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("closed_at") val closedAt: String? = null,
    @SerialName("web_url") val webUrl: String? = null,
    val references: References? = null,
    @SerialName("user_notes_count") val userNotesCount: Int = 0,
    @SerialName("due_date") val dueDate: String? = null,
    val confidential: Boolean = false,
    val milestone: Milestone? = null,
) {
    val reference get() = references?.full ?: references?.short ?: "#$iid"
}

@Serializable data class NotePosition(
    @SerialName("new_path") val newPath: String? = null,
    @SerialName("old_path") val oldPath: String? = null,
    @SerialName("new_line") val newLine: Int? = null,
    @SerialName("old_line") val oldLine: Int? = null,
)

@Serializable data class Note(
    val id: Long,
    val body: String,
    val author: User? = null,
    @SerialName("created_at") val createdAt: String? = null,
    val system: Boolean = false,
    val resolvable: Boolean = false,
    val resolved: Boolean = false,
    val position: NotePosition? = null,
)

@Serializable data class Discussion(
    val id: String,
    @SerialName("individual_note") val individualNote: Boolean = false,
    val notes: List<Note> = emptyList(),
)

@Serializable data class FileDiff(
    @SerialName("old_path") val oldPath: String = "",
    @SerialName("new_path") val newPath: String,
    val diff: String = "",
    @SerialName("new_file") val newFile: Boolean = false,
    @SerialName("renamed_file") val renamedFile: Boolean = false,
    @SerialName("deleted_file") val deletedFile: Boolean = false,
    @SerialName("too_large") val tooLarge: Boolean = false,
    val collapsed: Boolean = false,
)

@Serializable data class ApprovalUser(val user: User)

@Serializable data class Approvals(
    val approved: Boolean = false,
    @SerialName("approvals_required") val approvalsRequired: Int = 0,
    @SerialName("approvals_left") val approvalsLeft: Int = 0,
    @SerialName("approved_by") val approvedBy: List<ApprovalUser> = emptyList(),
    @SerialName("user_has_approved") val userHasApproved: Boolean = false,
    @SerialName("user_can_approve") val userCanApprove: Boolean = false,
)

@Serializable data class Pipeline(
    val id: Long,
    val iid: Long? = null,
    @SerialName("project_id") val projectId: Long? = null,
    val status: String,
    val ref: String,
    val sha: String? = null,
    val source: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    @SerialName("web_url") val webUrl: String? = null,
    val duration: Double? = null,
    val user: User? = null,
)

@Serializable data class JobPipeline(val id: Long, val ref: String? = null, val status: String? = null)

@Serializable data class Job(
    val id: Long,
    val name: String,
    val status: String,
    val stage: String,
    val ref: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("finished_at") val finishedAt: String? = null,
    val duration: Double? = null,
    @SerialName("allow_failure") val allowFailure: Boolean = false,
    @SerialName("web_url") val webUrl: String? = null,
    val pipeline: JobPipeline? = null,
    val user: User? = null,
)

@Serializable data class TodoTarget(
    val iid: Long? = null,
    val title: String? = null,
    val state: String? = null,
)

@Serializable data class TodoProject(
    val id: Long,
    val name: String,
    @SerialName("path_with_namespace") val pathWithNamespace: String,
)

@Serializable data class Todo(
    val id: Long,
    val body: String = "",
    val state: String = "pending",
    @SerialName("action_name") val actionName: String = "",
    @SerialName("target_type") val targetType: String = "",
    @SerialName("target_url") val targetUrl: String? = null,
    val target: TodoTarget? = null,
    val author: User? = null,
    val project: TodoProject? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable data class PipelineVariable(
    val key: String,
    val value: String,
    @SerialName("variable_type") val variableType: String = "env_var",
)

@Serializable data class CommitAction(
    val action: String,
    @SerialName("file_path") val filePath: String,
    @SerialName("previous_path") val previousPath: String? = null,
    val content: String? = null,
    val encoding: String? = null,
    @SerialName("last_commit_id") val lastCommitId: String? = null,
)

data class Page<T>(val items: List<T>, val next: Int?)
