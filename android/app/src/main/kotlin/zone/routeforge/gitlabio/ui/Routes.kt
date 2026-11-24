package zone.routeforge.gitlabio.ui

import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.serialization.Serializable

@Serializable object HomeRoute
@Serializable object ProjectsRoute
@Serializable object InboxRoute
@Serializable object SettingsRoute

@Serializable data class AccountEditorRoute(val accountId: String = "")
@Serializable data class ProjectRoute(val project: Long)
@Serializable data class TreeRoute(val project: Long, val ref: String, val path: String = "")
@Serializable data class FileRoute(val project: Long, val ref: String, val path: String)
@Serializable data class EditFileRoute(val project: Long, val ref: String, val path: String = "", val create: Boolean = false)
@Serializable data class BasketRoute(val project: Long, val ref: String)
@Serializable data class BranchesRoute(val project: Long)
@Serializable data class CommitsRoute(val project: Long, val ref: String, val path: String = "")
@Serializable data class CommitRoute(val project: Long, val sha: String)
/** [project] 0 lists merge requests across all projects. */
@Serializable data class MergeRequestsRoute(val project: Long = 0, val preset: String = "")
@Serializable data class MergeRequestRoute(val project: Long, val iid: Long)
@Serializable data class NewMergeRequestRoute(val project: Long, val source: String = "")
@Serializable data class IssuesRoute(val project: Long = 0, val preset: String = "")
@Serializable data class IssueRoute(val project: Long, val iid: Long)
@Serializable data class IssueEditorRoute(val project: Long, val iid: Long = 0)
@Serializable data class PipelinesRoute(val project: Long)
@Serializable data class PipelineRoute(val project: Long, val pipeline: Long)
@Serializable data class JobRoute(val project: Long, val job: Long)
@Serializable data class RunPipelineRoute(val project: Long, val ref: String = "")

/** Navigation actions screens may take, independent of the NavController. */
interface Navigator {
    fun open(route: Any)
    /** Replaces the current screen, e.g. a form with what it created. */
    fun replace(route: Any)
    fun back()
}

val LocalNavigator = staticCompositionLocalOf<Navigator> {
    object : Navigator {
        override fun open(route: Any) = Unit
        override fun replace(route: Any) = Unit
        override fun back() = Unit
    }
}
