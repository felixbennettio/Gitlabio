package zone.routeforge.gitlabio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.DoneAll
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.Todo
import zone.routeforge.gitlabio.notifications.TodoNotifications
import zone.routeforge.gitlabio.ui.IssueRoute
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.MergeRequestRoute
import zone.routeforge.gitlabio.ui.components.Avatar
import zone.routeforge.gitlabio.ui.components.ConfirmDialog
import zone.routeforge.gitlabio.ui.components.EmptyPane
import zone.routeforge.gitlabio.ui.components.PagedList
import zone.routeforge.gitlabio.ui.components.rememberOpenUrl
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.now
import zone.routeforge.gitlabio.ui.state.rememberActions
import zone.routeforge.gitlabio.ui.state.rememberPaged
import zone.routeforge.gitlabio.ui.theme.AppTheme
import zone.routeforge.gitlabio.ui.theme.ToneKey

@Composable
fun InboxScreen() {
    val navigator = LocalNavigator.current
    val session = LocalSession.current
    val openUrl = rememberOpenUrl()
    val actions = rememberActions()
    val todos = rememberPaged("todos") { page -> todos(page) }
    // Hidden right away when marked done, before the list reloads.
    var done by remember { mutableStateOf(setOf<Long>()) }
    var confirmAll by remember { mutableStateOf(false) }

    fun markDone(todo: Todo) {
        done = done + todo.id
        actions.run<Unit>("已标记完成", onError = { done = done - todo.id }) { markTodoDone(todo.id) }
    }

    ScreenScaffold(title = "待办", subtitle = session.instanceHost, back = false, actions = {
        if (session.capabilities.canWrite) IconButton(onClick = { confirmAll = true }, enabled = todos.items.isNotEmpty()) { Icon(Icons.Outlined.DoneAll, "全部标记完成") }
    }) { padding ->
        Box(Modifier.padding(padding)) {
            PagedList(todos, key = { it.id }, empty = { EmptyPane("待办清空了", "新的审阅请求、指派和提及会出现在这里。", Icons.Outlined.TaskAlt) }) { todo ->
                if (todo.id !in done) TodoRow(
                    todo, canWrite = session.capabilities.canWrite,
                    onOpen = {
                        val project = todo.project?.id
                        val iid = todo.target?.iid
                        when {
                            project != null && iid != null && todo.targetType == "MergeRequest" -> navigator.open(MergeRequestRoute(project, iid))
                            project != null && iid != null && todo.targetType == "Issue" -> navigator.open(IssueRoute(project, iid))
                            else -> openUrl(todo.targetUrl)
                        }
                    },
                    onDone = { markDone(todo) },
                )
            }
        }
    }
    if (confirmAll) {
        ConfirmDialog("全部标记完成？", "会把 GitLab 上所有待办标记为完成，包括未加载的。", "全部完成",
            onConfirm = { actions.run<Unit>("待办已清空") { markAllTodosDone() } }, onDismiss = { confirmAll = false })
    }
}

@Composable
private fun TodoRow(todo: Todo, canWrite: Boolean, onOpen: () -> Unit, onDone: () -> Unit) {
    val now = now()
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart && canWrite) { onDone(); true } else false
    })
    SwipeToDismissBox(
        state = state, enableDismissFromStartToEnd = false, enableDismissFromEndToStart = canWrite,
        backgroundContent = {
            val tone = AppTheme.colors.tone(ToneKey.SUCCESS)
            Box(Modifier.fillMaxSize().background(tone.container).padding(horizontal = 24.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Filled.Check, "完成", tint = tone.content)
            }
        },
    ) {
        Row(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface).clickable(onClick = onOpen).padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 4.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Avatar(todo.author?.name ?: "GitLab")
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("${todo.author?.name ?: "GitLab"} ${TodoNotifications.describe(todo)}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                Text(todo.target?.title ?: todo.body, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                val reference = when (todo.targetType) {
                    "MergeRequest" -> todo.target?.iid?.let { "!$it" }
                    "Issue" -> todo.target?.iid?.let { "#$it" }
                    else -> null
                }
                Text(
                    listOfNotNull(todo.project?.pathWithNamespace?.let { it + (reference ?: "") }, Format.relative(todo.createdAt, now)).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                if (todo.body.isNotBlank() && todo.body != todo.target?.title && todo.actionName in setOf("mentioned", "directly_addressed")) {
                    Text(todo.body, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            if (canWrite) IconButton(onClick = onDone) { Icon(Icons.Filled.Check, "标记完成", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}
