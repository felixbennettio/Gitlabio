package zone.routeforge.gitlabio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MergeType
import androidx.compose.material.icons.outlined.Adjust
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.RateReview
import androidx.compose.material.icons.outlined.RocketLaunch
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import zone.routeforge.gitlabio.core.GitLabApi
import zone.routeforge.gitlabio.core.Pipeline
import zone.routeforge.gitlabio.core.Project
import zone.routeforge.gitlabio.core.ProjectQuery
import zone.routeforge.gitlabio.core.WorkQuery
import zone.routeforge.gitlabio.core.WorkScope
import zone.routeforge.gitlabio.ui.InboxRoute
import zone.routeforge.gitlabio.ui.IssueRoute
import zone.routeforge.gitlabio.ui.IssuesRoute
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.MergeRequestRoute
import zone.routeforge.gitlabio.ui.MergeRequestsRoute
import zone.routeforge.gitlabio.ui.PipelineRoute
import zone.routeforge.gitlabio.ui.components.Avatar
import zone.routeforge.gitlabio.ui.components.IssueRow
import zone.routeforge.gitlabio.ui.components.MergeRequestRow
import zone.routeforge.gitlabio.ui.components.PipelineRow
import zone.routeforge.gitlabio.ui.components.SectionTitle
import zone.routeforge.gitlabio.ui.state.Load
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.ResourceModel
import zone.routeforge.gitlabio.ui.state.rememberResource
import zone.routeforge.gitlabio.ui.theme.AppTheme
import zone.routeforge.gitlabio.ui.theme.ToneKey

private const val PREVIEW = 4

/** Latest pipeline of each recently active project. */
suspend fun GitLabApi.recentPipelines(): List<Pair<Project, Pipeline>> = coroutineScope {
    projects(ProjectQuery(), 1).items.take(6).map { project ->
        async { runCatching { pipelines(project.id).items.firstOrNull() }.getOrNull()?.let { project to it } }
    }.awaitAll().filterNotNull().sortedByDescending { it.second.updatedAt ?: it.second.createdAt }
}

@Composable
fun HomeScreen() {
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    val username = session.user.username
    val review = rememberResource("home-review") { mergeRequests(WorkQuery(reviewer = username)) }
    val assigned = rememberResource("home-assigned") { mergeRequests(WorkQuery(scope = WorkScope.ASSIGNED)) }
    val issues = rememberResource("home-issues") { issues(WorkQuery(scope = WorkScope.ASSIGNED)) }
    val pipelines = rememberResource("home-pipelines") { recentPipelines() }
    val todos = rememberResource("todo-count") { todos() }
    val all = listOf(review, assigned, issues, pipelines, todos)

    ScreenScaffold(title = "首页", subtitle = "${session.user.name} · ${session.instanceHost}", back = false, actions = {
        Avatar(session.user.name, Modifier.padding(end = 12.dp), size = 32.dp)
    }) { padding ->
        PullToRefreshBox(
            isRefreshing = all.any { it.refreshing }, onRefresh = { all.forEach { it.reload() } },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
                item {
                    val stats: List<@Composable (Modifier) -> Unit> = listOf(
                        { StatCard("待我审阅", review.value?.items?.size, review.value?.next != null, Icons.Outlined.RateReview, ToneKey.ACCENT, it) { navigator.open(MergeRequestsRoute(preset = "review")) } },
                        { StatCard("我的合并请求", assigned.value?.items?.size, assigned.value?.next != null, Icons.AutoMirrored.Filled.MergeType, ToneKey.INFO, it) { navigator.open(MergeRequestsRoute(preset = "assigned")) } },
                        { StatCard("指派的议题", issues.value?.items?.size, issues.value?.next != null, Icons.Outlined.Adjust, ToneKey.SUCCESS, it) { navigator.open(IssuesRoute(preset = "assigned")) } },
                        { StatCard("待办", todos.value?.items?.size, todos.value?.next != null, Icons.Outlined.Inbox, ToneKey.WARNING, it) { navigator.open(InboxRoute) } },
                    )
                    // Two by two on phones, one row of four once there is room.
                    BoxWithConstraints(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                        val perRow = if (maxWidth >= 560.dp) 4 else 2
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            stats.chunked(perRow).forEach { row ->
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { row.forEach { it(Modifier.weight(1f)) } }
                            }
                        }
                    }
                }
                section("待我审阅", review, { navigator.open(MergeRequestsRoute(preset = "review")) }, "没有等待你审阅的合并请求") { page ->
                    items(page.items.take(PREVIEW), key = { "review-${it.id}" }) { mr ->
                        MergeRequestRow(mr, onClick = { navigator.open(MergeRequestRoute(mr.projectId, mr.iid)) })
                    }
                }
                section("指派给我的合并请求", assigned, { navigator.open(MergeRequestsRoute(preset = "assigned")) }, "没有指派给你的合并请求") { page ->
                    items(page.items.take(PREVIEW), key = { "assigned-${it.id}" }) { mr ->
                        MergeRequestRow(mr, onClick = { navigator.open(MergeRequestRoute(mr.projectId, mr.iid)) })
                    }
                }
                section("指派给我的议题", issues, { navigator.open(IssuesRoute(preset = "assigned")) }, "没有指派给你的议题") { page ->
                    items(page.items.take(PREVIEW), key = { "issue-${it.id}" }) { issue ->
                        IssueRow(issue, onClick = { navigator.open(IssueRoute(issue.projectId, issue.iid)) })
                    }
                }
                section("最近流水线", pipelines, null, "最近活跃的项目还没有流水线") { list ->
                    items(list, key = { "pipeline-${it.second.id}" }) { (project, pipeline) ->
                        PipelineRow(pipeline, onClick = { navigator.open(PipelineRoute(project.id, pipeline.id)) }, projectName = project.nameWithNamespace ?: project.name)
                    }
                }
            }
        }
    }
}

private fun <T> LazyListScope.section(
    title: String,
    model: ResourceModel<T>,
    onAll: (() -> Unit)?,
    emptyText: String,
    content: LazyListScope.(T) -> Unit,
) {
    item(key = "title-$title") {
        SectionTitle(title, trailing = if (onAll != null) ({ TextButton(onClick = onAll) { Text("全部") } }) else null)
    }
    when (val state = model.state) {
        Load.Loading -> item(key = "loading-$title") {
            Row(Modifier.fillMaxWidth().padding(20.dp), horizontalArrangement = Arrangement.Center) { CircularProgressIndicator(Modifier.size(24.dp)) }
        }
        is Load.Failed -> item(key = "error-$title") {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(state.message, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                TextButton(onClick = { model.reload() }) { Text("重试") }
            }
        }
        is Load.Ready -> {
            val empty = when (val value = state.value) {
                is List<*> -> value.isEmpty()
                is zone.routeforge.gitlabio.core.Page<*> -> value.items.isEmpty()
                else -> false
            }
            if (empty) item(key = "empty-$title") {
                Text(emptyText, Modifier.padding(horizontal = 16.dp, vertical = 8.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else content(state.value)
        }
    }
}

@Composable
private fun StatCard(label: String, count: Int?, more: Boolean, icon: ImageVector, tone: ToneKey, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = AppTheme.colors.tone(tone)
    Card(onClick = onClick, modifier = modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(14.dp)) {
            Box(Modifier.size(36.dp).background(colors.container, CircleShape), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = colors.content, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.height(12.dp))
            Text(
                when {
                    count == null -> "—"
                    more -> "$count+"
                    else -> "$count"
                },
                style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold,
            )
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}
