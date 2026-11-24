package zone.routeforge.gitlabio.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Adjust
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.Issue
import zone.routeforge.gitlabio.core.IssueDraft
import zone.routeforge.gitlabio.core.Note
import zone.routeforge.gitlabio.core.Noteable
import zone.routeforge.gitlabio.core.WorkQuery
import zone.routeforge.gitlabio.core.WorkScope
import zone.routeforge.gitlabio.ui.IssueEditorRoute
import zone.routeforge.gitlabio.ui.IssueRoute
import zone.routeforge.gitlabio.ui.IssuesRoute
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.components.Avatar
import zone.routeforge.gitlabio.ui.components.ConfirmDialog
import zone.routeforge.gitlabio.ui.components.EmptyPane
import zone.routeforge.gitlabio.ui.components.IssueRow
import zone.routeforge.gitlabio.ui.components.Labels
import zone.routeforge.gitlabio.ui.components.Markdown
import zone.routeforge.gitlabio.ui.components.PagedList
import zone.routeforge.gitlabio.ui.components.ResourceContent
import zone.routeforge.gitlabio.ui.components.StatusPill
import zone.routeforge.gitlabio.ui.components.issueStatus
import zone.routeforge.gitlabio.ui.components.rememberOpenUrl
import zone.routeforge.gitlabio.ui.state.Load
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.now
import zone.routeforge.gitlabio.ui.state.rememberActions
import zone.routeforge.gitlabio.ui.state.rememberPaged
import zone.routeforge.gitlabio.ui.state.rememberResource

@Composable
fun IssuesScreen(route: IssuesRoute) {
    val navigator = LocalNavigator.current
    val global = route.project == 0L
    var scope by rememberSaveable { mutableStateOf(if (route.preset == "assigned" || global) WorkScope.ASSIGNED else WorkScope.ALL) }
    var state by rememberSaveable { mutableStateOf("opened") }
    var search by rememberSaveable { mutableStateOf("") }
    val query = WorkQuery(project = route.project.takeIf { !global }, state = state, scope = scope, search = search)
    val list = rememberPaged("issues", query) { page -> issues(query, page) }
    ScreenScaffold(
        title = "议题", subtitle = if (global) "所有项目" else null,
        floatingActionButton = {
            if (!global) ExtendedFloatingActionButton(onClick = { navigator.open(IssueEditorRoute(route.project)) },
                icon = { Icon(Icons.Outlined.Add, null) }, text = { Text("新建议题") })
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            SearchField(search, { search = it }, "搜索议题")
            val scopes = listOf(WorkScope.ALL to "全部", WorkScope.ASSIGNED to "指派给我", WorkScope.CREATED to "我创建的").filter { !global || it.first != WorkScope.ALL }
            ChoiceChips(scopes, scope, { scope = it })
            ChoiceChips(listOf("opened" to "开放", "closed" to "已关闭", "all" to "全部"), state, { state = it })
            PagedList(list, key = { it.id }, empty = { EmptyPane("没有符合条件的议题", icon = Icons.Outlined.Adjust) }) { issue ->
                IssueRow(issue, onClick = { navigator.open(IssueRoute(issue.projectId, issue.iid)) }, showProject = global)
            }
        }
    }
}

@Composable
fun IssueScreen(route: IssueRoute) {
    val navigator = LocalNavigator.current
    val session = LocalSession.current
    val openUrl = rememberOpenUrl()
    val actions = rememberActions()
    val issue = rememberResource("issue", route.project, route.iid) { issue(route.project, route.iid) }
    val discussions = rememberPaged("issue-discussions", route.project, route.iid) { page -> discussions(route.project, route.iid, Noteable.ISSUE, page) }
    var confirm by remember { mutableStateOf(false) }
    val value = issue.value
    val now = now()
    ScreenScaffold(
        title = value?.reference ?: "#${route.iid}", subtitle = value?.title,
        actions = {
            if (value != null && session.capabilities.canWrite) IconButton(onClick = { navigator.open(IssueEditorRoute(route.project, route.iid)) }) { Icon(Icons.Outlined.Edit, "编辑") }
            if (!session.isDemo) value?.webUrl?.let { url -> IconButton(onClick = { openUrl(url) }) { Icon(Icons.AutoMirrored.Filled.OpenInNew, "在浏览器中打开") } }
        },
        bottomBar = {
            Composer(actions.busy, session.capabilities.canWrite, onSend = { body, clear ->
                actions.run<Note>("评论已发布", onSuccess = { clear() }) { addNote(route.project, route.iid, Noteable.ISSUE, body) }
            })
        },
    ) { padding ->
        ResourceContent(issue, Modifier.padding(padding)) { loaded ->
            PagedList(discussions, key = { it.id }, empty = { Text("还没有评论", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) },
                contentPadding = PaddingValues(bottom = 24.dp), header = {
                    item { IssueHeader(loaded, now, actions.busy, session.capabilities.canWrite) { confirm = true } }
                }) { DiscussionView(it) }
        }
    }
    if (confirm && value != null) {
        val open = value.state != "opened"
        ConfirmDialog(
            if (open) "重新打开 ${value.reference}？" else "关闭 ${value.reference}？",
            if (open) "议题会回到开放状态。" else "关闭后仍可随时重新打开。",
            if (open) "重新打开" else "关闭议题",
            onConfirm = { actions.run<Issue>(if (open) "已重新打开" else "已关闭") { setIssueOpen(route.project, route.iid, open) } },
            onDismiss = { confirm = false },
        )
    }
}

@Composable
private fun IssueHeader(issue: Issue, now: java.time.Instant, busy: Boolean, canWrite: Boolean, onToggle: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StatusPill(issueStatus(issue))
            Spacer(Modifier.width(8.dp))
            Text(issue.reference, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (issue.confidential) Text(" · 机密", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.error)
        }
        Text(issue.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(issue.author?.name ?: "?", size = 24.dp)
            Spacer(Modifier.width(8.dp))
            Text("${issue.author?.name ?: ""} 创建于 ${Format.relative(issue.createdAt, now)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Labels(issue.labels, max = 10)
        Column {
            if (issue.assignees.isNotEmpty()) InfoLine("指派给", issue.assignees.joinToString("、") { it.name })
            issue.milestone?.let { InfoLine("里程碑", it.title) }
            issue.dueDate?.let { InfoLine("截止日期", it) }
        }
        val description = issue.description?.takeIf { it.isNotBlank() }
        if (description != null) Markdown(description) else Text("没有描述", color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (canWrite) OutlinedButton(onClick = onToggle, enabled = !busy) { Text(if (issue.state == "opened") "关闭议题" else "重新打开") }
        HorizontalDivider(Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.outlineVariant)
        Text("讨论", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
    }
}

@Composable
fun IssueEditorScreen(route: IssueEditorRoute) {
    val navigator = LocalNavigator.current
    val actions = rememberActions()
    val editing = route.iid != 0L
    val existing = rememberResource("issue-edit", route.project, route.iid) { if (editing) issue(route.project, route.iid) else null }
    var title by rememberSaveable { mutableStateOf("") }
    var description by rememberSaveable { mutableStateOf("") }
    var labels by rememberSaveable { mutableStateOf("") }
    var confidential by rememberSaveable { mutableStateOf(false) }
    var loaded by rememberSaveable { mutableStateOf(!editing) }
    LaunchedEffect(existing.state) {
        val issue = (existing.state as? Load.Ready)?.value
        if (!loaded && issue != null) {
            title = issue.title; description = issue.description.orEmpty(); labels = issue.labels.joinToString(", "); confidential = issue.confidential
            loaded = true
        }
    }
    ScreenScaffold(title = if (editing) "编辑议题" else "新建议题", subtitle = if (editing) "#${route.iid}" else null) { padding ->
        ResourceContent(existing, Modifier.padding(padding)) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("标题") }, singleLine = true)
                OutlinedTextField(description, { description = it }, Modifier.fillMaxWidth(), label = { Text("描述（Markdown）") }, minLines = 8)
                OutlinedTextField(labels, { labels = it }, Modifier.fillMaxWidth(), label = { Text("标签（逗号分隔）") }, singleLine = true)
                SwitchRow("机密议题", confidential, "仅项目成员可见") { confidential = it }
                Button(
                    onClick = {
                        val draft = IssueDraft(title, description, labels.split(',').map { it.trim() }.filter { it.isNotEmpty() }, confidential)
                        actions.run<Issue>(if (editing) "已保存" else "已创建议题", onSuccess = {
                            if (editing) navigator.back() else navigator.replace(IssueRoute(it.projectId, it.iid))
                        }) { if (editing) updateIssue(route.project, route.iid, draft) else createIssue(route.project, draft) }
                    },
                    enabled = !actions.busy && title.isNotBlank() && loaded, modifier = Modifier.fillMaxWidth(),
                ) { if (actions.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(if (editing) "保存" else "创建议题") }
            }
        }
    }
}
