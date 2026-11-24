package zone.routeforge.gitlabio.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.MergeType
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import zone.routeforge.gitlabio.core.Approvals
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.MergeOptions
import zone.routeforge.gitlabio.core.MergeRequest
import zone.routeforge.gitlabio.core.MergeRequestDraft
import zone.routeforge.gitlabio.core.Noteable
import zone.routeforge.gitlabio.core.Note
import zone.routeforge.gitlabio.core.WorkQuery
import zone.routeforge.gitlabio.core.WorkScope
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.MergeRequestRoute
import zone.routeforge.gitlabio.ui.MergeRequestsRoute
import zone.routeforge.gitlabio.ui.NewMergeRequestRoute
import zone.routeforge.gitlabio.ui.PipelineRoute
import zone.routeforge.gitlabio.ui.components.Avatar
import zone.routeforge.gitlabio.ui.components.ConfirmDialog
import zone.routeforge.gitlabio.ui.components.EmptyPane
import zone.routeforge.gitlabio.ui.components.ErrorPane
import zone.routeforge.gitlabio.ui.components.Labels
import zone.routeforge.gitlabio.ui.components.LoadingPane
import zone.routeforge.gitlabio.ui.components.Markdown
import zone.routeforge.gitlabio.ui.components.MergeRequestRow
import zone.routeforge.gitlabio.ui.components.PagedList
import zone.routeforge.gitlabio.ui.components.ResourceContent
import zone.routeforge.gitlabio.ui.components.StatusPill
import zone.routeforge.gitlabio.ui.components.mergeRequestStatus
import zone.routeforge.gitlabio.ui.components.pipelineStatus
import zone.routeforge.gitlabio.ui.components.rememberOpenUrl
import zone.routeforge.gitlabio.ui.state.Load
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.now
import zone.routeforge.gitlabio.ui.state.rememberActions
import zone.routeforge.gitlabio.ui.state.rememberPaged
import zone.routeforge.gitlabio.ui.state.rememberResource
import zone.routeforge.gitlabio.ui.theme.CodeFont

enum class MrFilter(val label: String) { ALL("全部"), REVIEW("待我审阅"), ASSIGNED("指派给我"), CREATED("我创建的") }

@Composable
fun MergeRequestsScreen(route: MergeRequestsRoute) {
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    val global = route.project == 0L
    val initial = when (route.preset) {
        "review" -> MrFilter.REVIEW
        "assigned" -> MrFilter.ASSIGNED
        "created" -> MrFilter.CREATED
        else -> if (global) MrFilter.ASSIGNED else MrFilter.ALL
    }
    var filter by rememberSaveable { mutableStateOf(initial) }
    var state by rememberSaveable { mutableStateOf("opened") }
    var search by rememberSaveable { mutableStateOf("") }
    val query = WorkQuery(
        project = route.project.takeIf { !global },
        state = state,
        scope = when (filter) {
            MrFilter.ASSIGNED -> WorkScope.ASSIGNED
            MrFilter.CREATED -> WorkScope.CREATED
            else -> WorkScope.ALL
        },
        reviewer = if (filter == MrFilter.REVIEW) session.user.username else null,
        search = search,
    )
    val list = rememberPaged("mrs", query) { page -> mergeRequests(query, page) }
    ScreenScaffold(
        title = "合并请求", subtitle = if (global) "所有项目" else null,
        floatingActionButton = {
            if (!global) ExtendedFloatingActionButton(onClick = { navigator.open(NewMergeRequestRoute(route.project)) },
                icon = { Icon(Icons.AutoMirrored.Filled.MergeType, null) }, text = { Text("新建") })
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            SearchField(search, { search = it }, "搜索标题或描述")
            ChoiceChips(MrFilter.entries.filter { !global || it != MrFilter.ALL }.map { it to it.label }, filter, { filter = it })
            ChoiceChips(listOf("opened" to "开放", "merged" to "已合并", "closed" to "已关闭", "all" to "全部"), state, { state = it })
            PagedList(list, key = { it.id }, empty = { EmptyPane("没有符合条件的合并请求", icon = Icons.AutoMirrored.Filled.MergeType) }) { mr ->
                MergeRequestRow(mr, onClick = { navigator.open(MergeRequestRoute(mr.projectId, mr.iid)) }, showProject = global)
            }
        }
    }
}

fun mergeStatusText(status: String?): String = when (status) {
    null, "mergeable" -> "可以合并"
    "ci_still_running" -> "流水线仍在运行"
    "ci_must_pass" -> "流水线必须先成功"
    "not_approved" -> "尚未获得足够的批准"
    "draft_status" -> "草稿状态，不能合并"
    "discussions_not_resolved" -> "还有未解决的讨论"
    "conflict" -> "源分支与目标分支存在冲突"
    "need_rebase" -> "需要先变基"
    "blocked_status" -> "被其他合并请求阻塞"
    "checking", "unchecked", "preparing", "approvals_syncing" -> "GitLab 正在检查能否合并"
    "not_open" -> "合并请求未开放"
    "requested_changes" -> "审阅者要求修改"
    "broken_status" -> "源分支状态异常"
    "jira_association_missing" -> "缺少 Jira 关联"
    "external_status_checks" -> "外部状态检查未通过"
    "merge_request_blocked" -> "被依赖阻塞"
    else -> status
}

@Composable
fun MergeRequestScreen(route: MergeRequestRoute) {
    val openUrl = rememberOpenUrl()
    val session = LocalSession.current
    val mr = rememberResource("mr", route.project, route.iid) { mergeRequest(route.project, route.iid) }
    val discussions = rememberPaged("mr-discussions", route.project, route.iid) { page -> discussions(route.project, route.iid, Noteable.MERGE_REQUEST, page) }
    val diffs = rememberPaged("mr-diffs", route.project, route.iid) { page -> mergeRequestDiffs(route.project, route.iid, page) }
    val actions = rememberActions()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val value = mr.value
    ScreenScaffold(
        title = value?.reference ?: "!${route.iid}",
        subtitle = value?.title,
        actions = { if (!session.isDemo) value?.webUrl?.let { url -> IconButton(onClick = { openUrl(url) }) { Icon(Icons.AutoMirrored.Filled.OpenInNew, "在浏览器中打开") } } },
        bottomBar = {
            if (tab == 1) Composer(actions.busy, session.capabilities.canWrite, onSend = { body, clear ->
                actions.run<Note>("评论已发布", onSuccess = { clear() }) { addNote(route.project, route.iid, Noteable.MERGE_REQUEST, body) }
            })
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            PrimaryTabRow(selectedTabIndex = tab) {
                Tab(tab == 0, { tab = 0 }, text = { Text("概览") })
                Tab(tab == 1, { tab = 1 }, text = { Text(if (value != null && value.userNotesCount > 0) "讨论 ${value.userNotesCount}" else "讨论") })
                Tab(tab == 2, { tab = 2 }, text = { Text(value?.changesCount?.let { "变更 $it" } ?: "变更") })
            }
            when (tab) {
                0 -> ResourceContent(mr) { MergeRequestOverview(it) }
                1 -> DiscussionList(discussions, "还没有讨论")
                else -> DiffPane(diffs)
            }
        }
    }
}

@Composable
fun DiscussionList(model: zone.routeforge.gitlabio.ui.state.PagedModel<zone.routeforge.gitlabio.core.Discussion>, empty: String) {
    PagedList(model, key = { it.id }, empty = { EmptyPane(empty, icon = Icons.Outlined.ChatBubbleOutline) }, contentPadding = PaddingValues(vertical = 8.dp)) {
        DiscussionView(it)
    }
}

@Composable
private fun MergeRequestOverview(mr: MergeRequest) {
    val navigator = LocalNavigator.current
    val session = LocalSession.current
    val actions = rememberActions()
    val now = now()
    val approvals = rememberResource("mr-approvals", mr.projectId, mr.iid) { approvals(mr.projectId, mr.iid) }
    var squash by rememberSaveable(mr.id) { mutableStateOf(mr.squash) }
    var removeSource by rememberSaveable(mr.id) { mutableStateOf(mr.forceRemoveSourceBranch ?: true) }
    var confirmMerge by remember { mutableStateOf(false) }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    StatusPill(mergeRequestStatus(mr))
                    Spacer(Modifier.width(8.dp))
                    Text(mr.reference, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(mr.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(mr.author?.name ?: "?", size = 24.dp)
                    Spacer(Modifier.width(8.dp))
                    Text("${mr.author?.name ?: ""} 创建于 ${Format.relative(mr.createdAt, now)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                FlowRow(verticalArrangement = Arrangement.spacedBy(4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    BranchTag(mr.sourceBranch)
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, "合并到", Modifier.size(18.dp).align(Alignment.CenterVertically), tint = MaterialTheme.colorScheme.outline)
                    BranchTag(mr.targetBranch)
                }
                Labels(mr.labels, max = 10)
            }
        }
        mr.headPipeline?.let { pipeline ->
            item {
                Card(onClick = { navigator.open(PipelineRoute(mr.projectId, pipeline.id)) }, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        StatusPill(pipelineStatus(pipeline.status))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("流水线 #${pipeline.iid ?: pipeline.id}", style = MaterialTheme.typography.titleSmall)
                            Text(pipeline.sha?.take(8) ?: pipeline.ref, style = MaterialTheme.typography.bodySmall.copy(fontFamily = CodeFont), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        item { ApprovalCard(mr, approvals.value, approvals.state is Load.Failed, actions.busy, session.capabilities.canWrite) { approve ->
            actions.run<Unit>(if (approve) "已批准" else "已撤销批准") { setApproved(mr.projectId, mr.iid, approve) }
        } }
        if (mr.state == "opened") item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("合并", style = MaterialTheme.typography.titleSmall)
                    val ready = mr.detailedMergeStatus == null || mr.detailedMergeStatus == "mergeable"
                    Text(mergeStatusText(mr.detailedMergeStatus), style = MaterialTheme.typography.bodyMedium,
                        color = if (ready) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error)
                    CheckRow("压缩提交（squash）", squash) { squash = it }
                    CheckRow("合并后删除源分支", removeSource) { removeSource = it }
                    Button(
                        onClick = { confirmMerge = true }, modifier = Modifier.fillMaxWidth(),
                        enabled = !actions.busy && !mr.draft && !mr.hasConflicts && session.capabilities.canWrite,
                    ) { Icon(Icons.AutoMirrored.Filled.MergeType, null); Spacer(Modifier.width(8.dp)); Text("合并") }
                }
            }
        }
        if (mr.state == "merged") item {
            Text("已于 ${Format.dateTime(mr.mergedAt)} 合并到 ${mr.targetBranch}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (mr.reviewers.isNotEmpty() || mr.assignees.isNotEmpty()) item {
            Column {
                if (mr.assignees.isNotEmpty()) InfoLine("指派给", mr.assignees.joinToString("、") { it.name })
                if (mr.reviewers.isNotEmpty()) InfoLine("审阅者", mr.reviewers.joinToString("、") { it.name })
            }
        }
        item {
            val description = mr.description?.takeIf { it.isNotBlank() }
            if (description != null) Markdown(description)
            else Text("没有描述", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
    }
    if (confirmMerge) {
        ConfirmDialog(
            "合并 ${mr.reference}？",
            "把 ${mr.sourceBranch} 合并到 ${mr.targetBranch}" + (if (squash) "，压缩为一个提交" else "") + (if (removeSource) "，并删除源分支" else "") + "。",
            "合并",
            onConfirm = {
                actions.run<MergeRequest>("已合并") { merge(mr.projectId, mr.iid, MergeOptions(squash, removeSource, sha = mr.sha)) }
            },
            onDismiss = { confirmMerge = false },
        )
    }
}

@Composable
private fun BranchTag(name: String) {
    androidx.compose.material3.Surface(shape = MaterialTheme.shapes.small, color = MaterialTheme.colorScheme.secondaryContainer) {
        Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.AutoMirrored.Filled.CallSplit, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSecondaryContainer)
            Spacer(Modifier.width(4.dp))
            Text(name, style = MaterialTheme.typography.labelMedium.copy(fontFamily = CodeFont), color = MaterialTheme.colorScheme.onSecondaryContainer,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun CheckRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!checked) }, verticalAlignment = Alignment.CenterVertically) {
        Checkbox(checked, null)
        Spacer(Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun ApprovalCard(mr: MergeRequest, approvals: Approvals?, failed: Boolean, busy: Boolean, canWrite: Boolean, onApprove: (Boolean) -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(if (approvals?.approved == true) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp, null,
                    tint = if (approvals?.approved == true) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(10.dp))
                Text(
                    when {
                        failed -> "无法读取批准状态"
                        approvals == null -> "正在读取批准…"
                        approvals.approvalsLeft > 0 -> "还需要 ${approvals.approvalsLeft} 个批准"
                        approvals.approvedBy.isNotEmpty() -> "已批准"
                        else -> "无需批准"
                    },
                    style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f),
                )
            }
            if (approvals != null && approvals.approvedBy.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    approvals.approvedBy.take(6).forEach { Avatar(it.user.name, size = 26.dp) }
                    Text(approvals.approvedBy.joinToString("、") { it.user.name }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (approvals != null && mr.state == "opened" && canWrite) {
                when {
                    approvals.userHasApproved -> OutlinedButton(onClick = { onApprove(false) }, enabled = !busy) { Text("撤销批准") }
                    approvals.userCanApprove -> FilledTonalButton(onClick = { onApprove(true) }, enabled = !busy) { Text("批准") }
                }
            }
        }
    }
}

@Composable
fun NewMergeRequestScreen(route: NewMergeRequestRoute) {
    val navigator = LocalNavigator.current
    val actions = rememberActions()
    val project = rememberResource("project", route.project) { project(route.project) }
    var source by rememberSaveable { mutableStateOf(route.source) }
    var target by rememberSaveable { mutableStateOf("") }
    var title by rememberSaveable { mutableStateOf("") }
    var description by rememberSaveable { mutableStateOf("") }
    var draft by rememberSaveable { mutableStateOf(false) }
    var removeSource by rememberSaveable { mutableStateOf(true) }
    var squash by rememberSaveable { mutableStateOf(false) }
    var picking by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(project.value) { if (target.isEmpty()) project.value?.defaultBranch?.let { target = it } }
    LaunchedEffect(source) {
        if (title.isEmpty() && source.isNotEmpty()) title = source.substringAfterLast('/').replace('-', ' ').replace('_', ' ').replaceFirstChar { it.uppercase() }
    }

    ScreenScaffold(title = "新建合并请求", subtitle = project.value?.pathWithNamespace) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).imePadding().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            BranchField("源分支", source) { picking = "source" }
            BranchField("目标分支", target) { picking = "target" }
            OutlinedTextField(title, { title = it }, Modifier.fillMaxWidth(), label = { Text("标题") }, singleLine = true)
            OutlinedTextField(description, { description = it }, Modifier.fillMaxWidth(), label = { Text("描述（Markdown）") }, minLines = 5)
            SwitchRow("标记为草稿", draft) { draft = it }
            SwitchRow("合并后删除源分支", removeSource) { removeSource = it }
            SwitchRow("合并时压缩提交", squash) { squash = it }
            Button(
                onClick = {
                    actions.run<MergeRequest>("已创建合并请求", onSuccess = { navigator.replace(MergeRequestRoute(it.projectId, it.iid)) }) {
                        createMergeRequest(route.project, MergeRequestDraft(source, target, title, description, draft, removeSource, squash))
                    }
                },
                enabled = !actions.busy && source.isNotBlank() && target.isNotBlank() && title.isNotBlank() && source != target,
                modifier = Modifier.fillMaxWidth(),
            ) { if (actions.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("创建合并请求") }
            if (source.isNotEmpty() && source == target) Text("源分支和目标分支不能相同。", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }
    picking?.let { which ->
        BranchPicker(route.project, if (which == "source") source else target, title = if (which == "source") "选择源分支" else "选择目标分支",
            onPick = { if (which == "source") source = it else target = it }, onDismiss = { picking = null })
    }
}

@Composable
fun BranchField(label: String, value: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 4.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
            Icon(Icons.AutoMirrored.Filled.CallSplit, null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(8.dp))
            Text(value.ifEmpty { "选择分支" }, style = MaterialTheme.typography.bodyLarge.copy(fontFamily = CodeFont),
                color = if (value.isEmpty()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
        }
    }
}

@Composable
fun SwitchRow(label: String, checked: Boolean, supporting: String? = null, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled) { onChange(!checked) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            if (supporting != null) Text(supporting, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked, null, enabled = enabled)
    }
}

@Composable
internal fun ErrorOrLoading(state: Load<*>, onRetry: () -> Unit) {
    when (state) {
        Load.Loading -> LoadingPane()
        is Load.Failed -> ErrorPane(state.message, onRetry)
        else -> Unit
    }
}

