package zone.routeforge.gitlabio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MergeType
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Adjust
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Commit
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.RocketLaunch
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.Project
import zone.routeforge.gitlabio.core.ProjectFilter
import zone.routeforge.gitlabio.core.ProjectQuery
import zone.routeforge.gitlabio.core.ProjectSort
import zone.routeforge.gitlabio.core.RepositoryFile
import zone.routeforge.gitlabio.ui.BranchesRoute
import zone.routeforge.gitlabio.ui.CommitsRoute
import zone.routeforge.gitlabio.ui.IssuesRoute
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.MergeRequestsRoute
import zone.routeforge.gitlabio.ui.PipelinesRoute
import zone.routeforge.gitlabio.ui.ProjectRoute
import zone.routeforge.gitlabio.ui.TreeRoute
import zone.routeforge.gitlabio.ui.components.Markdown
import zone.routeforge.gitlabio.ui.components.PagedList
import zone.routeforge.gitlabio.ui.components.ProjectMark
import zone.routeforge.gitlabio.ui.components.ProjectRow
import zone.routeforge.gitlabio.ui.components.ResourceContent
import zone.routeforge.gitlabio.ui.components.SectionTitle
import zone.routeforge.gitlabio.ui.components.EmptyPane
import zone.routeforge.gitlabio.ui.components.rememberOpenUrl
import zone.routeforge.gitlabio.ui.components.visibilityLabel
import zone.routeforge.gitlabio.ui.state.rememberActions
import zone.routeforge.gitlabio.ui.state.rememberPaged
import zone.routeforge.gitlabio.ui.state.rememberResource
import zone.routeforge.gitlabio.ui.theme.AppTheme
import zone.routeforge.gitlabio.ui.theme.ToneKey

@Composable
fun ProjectsScreen() {
    val navigator = LocalNavigator.current
    val actions = rememberActions()
    var search by rememberSaveable { mutableStateOf("") }
    var filter by rememberSaveable { mutableStateOf(ProjectFilter.MEMBERSHIP) }
    var sort by rememberSaveable { mutableStateOf(ProjectSort.ACTIVITY) }
    var sortMenu by remember { mutableStateOf(false) }
    // Local star overrides so the icon flips immediately while the list reloads.
    var stars by remember { mutableStateOf(mapOf<Long, Boolean>()) }
    val query = ProjectQuery(search, filter, sort)
    val projects = rememberPaged("projects", query) { page -> projects(query, page) }

    ScreenScaffold(title = "项目", back = false, actions = {
        Box {
            IconButton(onClick = { sortMenu = true }) { Icon(Icons.AutoMirrored.Filled.Sort, "排序") }
            DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                listOf(ProjectSort.ACTIVITY to "最近活动", ProjectSort.NAME to "名称", ProjectSort.CREATED to "创建时间").forEach { (value, label) ->
                    DropdownMenuItem(
                        text = { Text(label) }, onClick = { sort = value; sortMenu = false },
                        leadingIcon = if (value == sort) ({ Icon(Icons.Filled.Check, null) }) else null,
                    )
                }
            }
        }
    }) { padding ->
        Column(Modifier.padding(padding)) {
            SearchField(search, { search = it }, "搜索项目")
            ChoiceChips(listOf(ProjectFilter.MEMBERSHIP to "我参与的", ProjectFilter.STARRED to "星标", ProjectFilter.OWNED to "我拥有的"), filter, { filter = it })
            PagedList(
                projects, key = { it.id },
                empty = { EmptyPane(if (search.isBlank()) "没有项目" else "没有匹配“$search”的项目", icon = Icons.Outlined.Folder) },
            ) { project ->
                val starred = stars[project.id] ?: (filter == ProjectFilter.STARRED || isDemoStarred(project))
                ProjectRow(project, onClick = { navigator.open(ProjectRoute(project.id)) }, starred = starred, onStar = {
                    stars = stars + (project.id to !starred)
                    actions.run<Project>(if (starred) "已取消星标" else "已加星标", onError = { stars = stars - project.id }) { setStarred(project.id, !starred) }
                })
            }
        }
    }
}

/** GitLab's project list does not say whether the user starred it; the demo can. */
@Composable
private fun isDemoStarred(project: Project): Boolean {
    val api = zone.routeforge.gitlabio.ui.state.LocalSession.current.api
    return (api as? zone.routeforge.gitlabio.core.DemoGitLabApi)?.isStarred(project.id) ?: false
}

private data class ProjectOverview(val project: Project, val languages: Map<String, Double>, val readme: RepositoryFile?)

@Composable
fun ProjectScreen(projectId: Long) {
    val navigator = LocalNavigator.current
    val actions = rememberActions()
    val openUrl = rememberOpenUrl()
    val overview = rememberResource("project", projectId) {
        coroutineScope {
            val project = project(projectId)
            val languages = async { runCatching { languages(projectId) }.getOrDefault(emptyMap()) }
            val readme = async { project.defaultBranch?.let { runCatching { readme(projectId, it) }.getOrNull() } }
            ProjectOverview(project, languages.await(), readme.await())
        }
    }
    val project = overview.value?.project
    var starred by rememberSaveable { mutableStateOf<Boolean?>(null) }
    ScreenScaffold(
        title = project?.name ?: "项目",
        subtitle = project?.pathWithNamespace,
        actions = {
            if (project != null) {
                val isStarred = starred ?: isDemoStarred(project)
                IconButton(onClick = {
                    starred = !isStarred
                    actions.run<Project>(if (isStarred) "已取消星标" else "已加星标", onError = { starred = isStarred }) { setStarred(projectId, !isStarred) }
                }) {
                    Icon(if (isStarred) Icons.Filled.Star else Icons.Outlined.StarBorder, if (isStarred) "取消星标" else "加星标",
                        tint = if (isStarred) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = { openUrl(project.webUrl) }) { Icon(Icons.AutoMirrored.Filled.OpenInNew, "在浏览器中打开") }
            }
        },
    ) { padding ->
        ResourceContent(overview, Modifier.padding(padding)) { data ->
            val p = data.project
            val ref = p.defaultBranch ?: "main"
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
                item { ProjectHeader(p, data.languages) }
                item {
                    val entries = listOf(
                        Triple("代码", Icons.Outlined.Code, { navigator.open(TreeRoute(p.id, ref)) }),
                        Triple("合并请求", Icons.AutoMirrored.Filled.MergeType, { navigator.open(MergeRequestsRoute(p.id)) }),
                        Triple("议题", Icons.Outlined.Adjust, { navigator.open(IssuesRoute(p.id)) }),
                        Triple("流水线", Icons.Outlined.RocketLaunch, { navigator.open(PipelinesRoute(p.id)) }),
                        Triple("分支", Icons.Outlined.AccountTree, { navigator.open(BranchesRoute(p.id)) }),
                        Triple("提交", Icons.Outlined.Commit, { navigator.open(CommitsRoute(p.id, ref)) }),
                    )
                    FlowRow(
                        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), maxItemsInEachRow = 3,
                    ) {
                        entries.forEach { (label, icon, open) -> EntryCard(label, icon, Modifier.weight(1f), open) }
                    }
                }
                item { SectionTitle(data.readme?.fileName ?: "README") }
                item {
                    val text = data.readme?.textOrNull()
                    if (text != null) Markdown(text, Modifier.padding(horizontal = 16.dp))
                    else Text(
                        if (data.readme == null) "仓库根目录没有 README。" else "README 不是可显示的文本。",
                        Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun ProjectHeader(project: Project, languages: Map<String, Double>) {
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ProjectMark(project.name, size = 52.dp)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(project.nameWithNamespace ?: project.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Text("${visibilityLabel(project.visibility)} · 默认分支 ${project.defaultBranch ?: "无"}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        project.description?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        if (project.topics.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { project.topics.forEach { SuggestionChip(onClick = {}, label = { Text(it) }) } }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Stat("${project.starCount}", "星标")
            Stat("${project.forksCount}", "派生")
            project.openIssuesCount?.let { Stat("$it", "开放议题") }
            project.statistics?.let { Stat(Format.count(it.commitCount), "提交") }
            project.statistics?.let { Stat(Format.bytes(it.repositorySize), "仓库") }
        }
        if (languages.isNotEmpty()) LanguageBar(languages)
        project.lastActivityAt?.let {
            Text("最近活动 ${Format.dateTime(it)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
}

@Composable
private fun Stat(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun LanguageBar(languages: Map<String, Double>) {
    val tones = listOf(ToneKey.INFO, ToneKey.ACCENT, ToneKey.SUCCESS, ToneKey.WARNING, ToneKey.DANGER, ToneKey.NEUTRAL)
    val sorted = languages.entries.sortedByDescending { it.value }.take(6)
    val colors = sorted.indices.map { AppTheme.colors.tone(tones[it]).content }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().height(8.dp).clip(CircleShape)) {
            sorted.forEachIndexed { index, entry ->
                Box(Modifier.weight(entry.value.toFloat().coerceAtLeast(0.5f)).fillMaxHeight().background(colors[index]))
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            sorted.forEachIndexed { index, entry -> LanguageLegend(entry.key, entry.value, colors[index]) }
        }
    }
}

@Composable
private fun LanguageLegend(name: String, percent: Double, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(4.dp))
        Text("$name ${"%.1f".format(java.util.Locale.ROOT, percent)}%", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun EntryCard(label: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    Card(onClick = onClick, modifier = modifier, shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(6.dp))
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    }
}
