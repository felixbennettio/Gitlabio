package zone.routeforge.gitlabio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.WrapText
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Commit
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Replay
import androidx.compose.material.icons.outlined.RocketLaunch
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.VerticalAlignBottom
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledIconToggleButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import zone.routeforge.gitlabio.core.AnsiLine
import zone.routeforge.gitlabio.core.AnsiParser
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.Job
import zone.routeforge.gitlabio.core.JobAction
import zone.routeforge.gitlabio.core.Pipeline
import zone.routeforge.gitlabio.core.PipelineAction
import zone.routeforge.gitlabio.core.PipelineVariable
import zone.routeforge.gitlabio.core.isActiveStatus
import zone.routeforge.gitlabio.ui.JobRoute
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.PipelineRoute
import zone.routeforge.gitlabio.ui.RunPipelineRoute
import zone.routeforge.gitlabio.ui.components.ConfirmDialog
import zone.routeforge.gitlabio.ui.components.EmptyPane
import zone.routeforge.gitlabio.ui.components.LoadingPane
import zone.routeforge.gitlabio.ui.components.Meta
import zone.routeforge.gitlabio.ui.components.PagedList
import zone.routeforge.gitlabio.ui.components.PipelineRow
import zone.routeforge.gitlabio.ui.components.ResourceContent
import zone.routeforge.gitlabio.ui.components.StatusBadge
import zone.routeforge.gitlabio.ui.components.StatusPill
import zone.routeforge.gitlabio.ui.components.Terminal
import zone.routeforge.gitlabio.ui.components.codeStyle
import zone.routeforge.gitlabio.ui.components.pipelineStatus
import zone.routeforge.gitlabio.ui.components.sourceLabel
import zone.routeforge.gitlabio.ui.state.LocalAutoRefresh
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.now
import zone.routeforge.gitlabio.ui.state.rememberActions
import zone.routeforge.gitlabio.ui.state.rememberPaged
import zone.routeforge.gitlabio.ui.state.rememberResource
import zone.routeforge.gitlabio.ui.theme.CodeFont

@Composable
fun PipelinesScreen(projectId: Long) {
    val navigator = LocalNavigator.current
    var status by rememberSaveable { mutableStateOf("") }
    val project = rememberResource("project", projectId) { project(projectId) }
    val list = rememberPaged("pipelines", projectId, status) { page -> pipelines(projectId, status.ifEmpty { null }, null, page) }
    val active = list.items.any { isActiveStatus(it.status) } && LocalAutoRefresh.current
    LaunchedEffect(active) {
        while (active) { delay(10_000); list.reload(quiet = true) }
    }
    ScreenScaffold(
        title = "流水线", subtitle = project.value?.pathWithNamespace,
        floatingActionButton = {
            ExtendedFloatingActionButton(onClick = { navigator.open(RunPipelineRoute(projectId)) },
                icon = { Icon(Icons.Filled.PlayArrow, null) }, text = { Text("运行流水线") })
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            ChoiceChips(
                listOf("" to "全部", "running" to "运行中", "pending" to "等待中", "success" to "成功", "failed" to "失败", "canceled" to "已取消", "manual" to "手动"),
                status, { status = it },
            )
            PagedList(list, key = { it.id }, empty = { EmptyPane("没有流水线", icon = Icons.Outlined.RocketLaunch) }) { pipeline ->
                PipelineRow(pipeline, onClick = { navigator.open(PipelineRoute(projectId, pipeline.id)) })
            }
        }
    }
}

private data class PipelineDetail(val pipeline: Pipeline, val jobs: List<Job>)

@Composable
fun PipelineScreen(route: PipelineRoute) {
    val navigator = LocalNavigator.current
    val session = LocalSession.current
    val actions = rememberActions()
    val detail = rememberResource("pipeline", route.project, route.pipeline) {
        PipelineDetail(pipeline(route.project, route.pipeline), pipelineJobs(route.project, route.pipeline))
    }
    val value = detail.value
    val autoRefresh = LocalAutoRefresh.current
    val active = value?.let { isActiveStatus(it.pipeline.status) || it.jobs.any { job -> isActiveStatus(job.status) } } ?: false
    LaunchedEffect(active && autoRefresh) {
        if (!autoRefresh) return@LaunchedEffect
        while (active) { delay(5_000); detail.reload(quiet = true) }
    }
    var confirm by remember { mutableStateOf<PipelineAction?>(null) }
    ScreenScaffold(
        title = "流水线 #${value?.pipeline?.iid ?: route.pipeline}", subtitle = value?.pipeline?.ref,
        actions = {
            if (value != null && session.capabilities.canWrite) {
                if (isActiveStatus(value.pipeline.status)) IconButton(onClick = { confirm = PipelineAction.CANCEL }) { Icon(Icons.Outlined.Block, "取消流水线") }
                if (value.pipeline.status in setOf("failed", "canceled", "success", "skipped")) IconButton(onClick = { confirm = PipelineAction.RETRY }) { Icon(Icons.Outlined.Replay, "重试失败的作业") }
            }
        },
    ) { padding ->
        ResourceContent(detail, Modifier.padding(padding)) { data ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 32.dp)) {
                PipelineHeader(data.pipeline)
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                if (data.jobs.isEmpty()) EmptyPane("这条流水线没有作业")
                else StageGraph(data.jobs, canWrite = session.capabilities.canWrite, busy = actions.busy,
                    onOpen = { navigator.open(JobRoute(route.project, it.id)) },
                    onAction = { job, action -> actions.run<Job>(jobActionLabel(action)) { jobAction(route.project, job.id, action) } })
            }
        }
    }
    confirm?.let { action ->
        ConfirmDialog(
            if (action == PipelineAction.CANCEL) "取消流水线？" else "重试流水线？",
            if (action == PipelineAction.CANCEL) "正在运行和等待中的作业都会被取消。" else "失败或取消的作业会重新运行。",
            if (action == PipelineAction.CANCEL) "取消流水线" else "重试",
            onConfirm = { actions.run<Pipeline>(if (action == PipelineAction.CANCEL) "已取消流水线" else "已重试流水线") { pipelineAction(route.project, route.pipeline, action) } },
            onDismiss = { confirm = null }, destructive = action == PipelineAction.CANCEL,
        )
    }
}

private fun jobActionLabel(action: JobAction) = when (action) {
    JobAction.PLAY -> "已启动作业"
    JobAction.RETRY -> "已重试作业"
    JobAction.CANCEL -> "已取消作业"
}

@Composable
private fun PipelineHeader(pipeline: Pipeline) {
    val now = now()
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StatusPill(pipelineStatus(pipeline.status))
            Spacer(Modifier.width(10.dp))
            Text("#${pipeline.iid ?: pipeline.id}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Meta(Icons.AutoMirrored.Filled.CallSplit, pipeline.ref)
            pipeline.sha?.let { Meta(Icons.Outlined.Commit, it.take(8)) }
            Meta(Icons.Outlined.Schedule, Format.relative(pipeline.createdAt, now))
            pipeline.duration?.let { Meta(Icons.Outlined.Timer, Format.duration(it)) }
            pipeline.user?.let { Meta(Icons.Outlined.Person, it.name) }
            Meta(null, sourceLabel(pipeline.source))
        }
    }
}

private val stageWidth = 220.dp

/** Stages as columns, jobs as cards, in GitLab's pipeline-graph layout. Scrolls sideways on phones. */
@Composable
private fun StageGraph(jobs: List<Job>, canWrite: Boolean, busy: Boolean, onOpen: (Job) -> Unit, onAction: (Job, JobAction) -> Unit) {
    val stages = jobs.groupBy { it.stage }.toList()
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 16.dp)) {
        stages.forEachIndexed { index, (stage, stageJobs) ->
            if (index > 0) Box(Modifier.height(40.dp), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.outline)
            }
            Column(Modifier.width(stageWidth), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.height(40.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    StatusBadge(pipelineStatus(stageStatus(stageJobs)), size = 22.dp)
                    Spacer(Modifier.width(8.dp))
                    Text(stage, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                stageJobs.forEach { job -> JobCard(job, canWrite, busy, onOpen, onAction) }
            }
        }
    }
}

/** The status GitLab would show for a stage: the most urgent of its jobs. */
fun stageStatus(jobs: List<Job>): String {
    val statuses = jobs.map { it.status }
    return listOf("failed", "running", "pending", "preparing", "waiting_for_resource", "created", "manual", "canceled", "success", "skipped")
        .firstOrNull { status -> status in statuses && !(status == "failed" && jobs.filter { it.status == "failed" }.all { it.allowFailure }) }
        ?: "success"
}

@Composable
private fun JobCard(job: Job, canWrite: Boolean, busy: Boolean, onOpen: (Job) -> Unit, onAction: (Job, JobAction) -> Unit) {
    val action = when {
        job.status == "manual" -> JobAction.PLAY
        isActiveStatus(job.status) -> JobAction.CANCEL
        job.status in setOf("failed", "canceled", "success") -> JobAction.RETRY
        else -> null
    }
    Card(onClick = { onOpen(job) }, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Row(Modifier.fillMaxWidth().padding(start = 10.dp, top = 8.dp, bottom = 8.dp, end = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            StatusBadge(pipelineStatus(job.status), size = 24.dp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(job.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val detail = listOfNotNull(
                    job.duration?.let { Format.duration(it) } ?: pipelineStatus(job.status).label,
                    "允许失败".takeIf { job.allowFailure && job.status == "failed" },
                ).joinToString(" · ")
                Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
            if (action != null && canWrite) {
                IconButton(onClick = { onAction(job, action) }, enabled = !busy, modifier = Modifier.size(36.dp)) {
                    Icon(
                        when (action) {
                            JobAction.PLAY -> Icons.Filled.PlayArrow
                            JobAction.CANCEL -> Icons.Filled.Close
                            JobAction.RETRY -> Icons.Outlined.Replay
                        },
                        when (action) {
                            JobAction.PLAY -> "运行 ${job.name}"
                            JobAction.CANCEL -> "取消 ${job.name}"
                            JobAction.RETRY -> "重试 ${job.name}"
                        },
                        Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

@Composable
fun JobScreen(route: JobRoute) {
    val session = LocalSession.current
    val actions = rememberActions()
    val job = rememberResource("job", route.project, route.job) { job(route.project, route.job) }
    val trace = rememberResource("trace", route.project, route.job) { jobTrace(route.project, route.job) }
    val autoRefresh = LocalAutoRefresh.current
    val active = job.value?.let { isActiveStatus(it.status) } ?: false
    var follow by rememberSaveable { mutableStateOf(true) }
    var wrap by rememberSaveable { mutableStateOf(true) }
    LaunchedEffect(active && autoRefresh) {
        if (!autoRefresh) return@LaunchedEffect
        while (active) {
            delay(3_000)
            job.reload(quiet = true)
            trace.reload(quiet = true)
        }
    }
    val text = trace.value?.text
    var lines by remember { mutableStateOf<List<AnsiLine>?>(null) }
    LaunchedEffect(text) { lines = text?.let { withContext(Dispatchers.Default) { AnsiParser.parse(it) } } }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(lines?.size, follow) {
        val count = lines?.size ?: 0
        if (follow && count > 0) listState.scrollToItem(count - 1)
    }
    val value = job.value
    ScreenScaffold(
        title = value?.name ?: "作业", maxContentWidth = Dp.Unspecified, subtitle = value?.let { "${it.stage} · ${pipelineStatus(it.status).label}${it.duration?.let { d -> " · " + Format.duration(d) } ?: ""}" },
        actions = {
            FilledIconToggleButton(checked = follow, onCheckedChange = { follow = it }) { Icon(Icons.Outlined.VerticalAlignBottom, if (follow) "停止跟随" else "跟随输出") }
            IconButton(onClick = { wrap = !wrap }) { Icon(Icons.AutoMirrored.Filled.WrapText, if (wrap) "取消换行" else "自动换行") }
            if (value != null && session.capabilities.canWrite) {
                when {
                    value.status == "manual" -> IconButton(onClick = { actions.run<Job>("已启动作业") { jobAction(route.project, route.job, JobAction.PLAY) } }, enabled = !actions.busy) { Icon(Icons.Filled.PlayArrow, "运行") }
                    isActiveStatus(value.status) -> IconButton(onClick = { actions.run<Job>("已取消作业") { jobAction(route.project, route.job, JobAction.CANCEL) } }, enabled = !actions.busy) { Icon(Icons.Outlined.Block, "取消作业") }
                    else -> IconButton(onClick = { actions.run<Job>("已重试作业") { jobAction(route.project, route.job, JobAction.RETRY) } }, enabled = !actions.busy) { Icon(Icons.Outlined.Replay, "重试作业") }
                }
            }
        },
        floatingActionButton = {
            if (!follow) SmallFloatingActionButton(onClick = { follow = true; scope.launch { lines?.size?.takeIf { it > 0 }?.let { listState.animateScrollToItem(it - 1) } } }) {
                Icon(Icons.Outlined.VerticalAlignBottom, "跳到末尾")
            }
        },
    ) { padding ->
        Surface(color = Terminal.background, contentColor = Terminal.foreground, modifier = Modifier.fillMaxSize().padding(padding)) {
            ResourceContent(trace) { log ->
                val parsed = lines
                if (parsed == null) LoadingPane()
                else Column(Modifier.fillMaxSize()) {
                    if (log.truncated) Text("日志较长，只显示最后 1 MiB。", Modifier.fillMaxWidth().background(Terminal.foreground.copy(alpha = 0.08f)).padding(horizontal = 12.dp, vertical = 6.dp),
                        style = MaterialTheme.typography.bodySmall)
                    if (parsed.all { it.text.isEmpty() }) Text(if (active) "等待输出…" else "没有日志输出。", Modifier.padding(16.dp))
                    LogLines(parsed, wrap, listState)
                }
            }
        }
    }
}

@Composable
private fun LogLines(lines: List<AnsiLine>, wrap: Boolean, state: androidx.compose.foundation.lazy.LazyListState) {
    val digits = lines.size.toString().length
    val horizontal = rememberScrollState()
    SelectionContainer {
        LazyColumn(
            Modifier.fillMaxSize().then(if (wrap) Modifier else Modifier.horizontalScroll(horizontal)),
            state = state, contentPadding = PaddingValues(top = 6.dp, bottom = 96.dp),
        ) {
            items(lines.size) { index ->
                val line = lines[index]
                Row(Modifier.then(if (line.section != null) Modifier.background(Terminal.foreground.copy(alpha = 0.06f)) else Modifier)) {
                    Text((index + 1).toString().padStart(digits), Modifier.padding(start = 8.dp, end = 10.dp), style = codeStyle, color = Terminal.foreground.copy(alpha = 0.35f))
                    Text(Terminal.render(line), style = codeStyle, softWrap = wrap, modifier = if (wrap) Modifier.weight(1f).padding(end = 8.dp) else Modifier.padding(end = 8.dp),
                        fontWeight = if (line.section != null) FontWeight.SemiBold else null)
                }
            }
        }
    }
}

@Composable
fun RunPipelineScreen(route: RunPipelineRoute) {
    val navigator = LocalNavigator.current
    val actions = rememberActions()
    val project = rememberResource("project", route.project) { project(route.project) }
    var ref by rememberSaveable { mutableStateOf(route.ref) }
    var picking by remember { mutableStateOf(false) }
    val variables = remember { mutableStateListOf<Pair<String, String>>() }
    LaunchedEffect(project.value) { if (ref.isEmpty()) project.value?.defaultBranch?.let { ref = it } }
    ScreenScaffold(title = "运行流水线", subtitle = project.value?.pathWithNamespace) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).imePadding().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            BranchField("分支或标签", ref) { picking = true }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Text("变量", style = MaterialTheme.typography.titleSmall)
            Text("作为环境变量传给本次流水线；值会发送到 GitLab 并可能出现在作业日志里，不要填写长期密钥。",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            variables.forEachIndexed { index, (key, value) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(key, { variables[index] = it.trim() to value }, Modifier.weight(1f), label = { Text("键") }, singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont))
                    Spacer(Modifier.width(8.dp))
                    OutlinedTextField(value, { variables[index] = key to it }, Modifier.weight(1f), label = { Text("值") }, singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont))
                    IconButton(onClick = { variables.removeAt(index) }) { Icon(Icons.Filled.Close, "删除变量") }
                }
            }
            TextButton(onClick = { variables.add("" to "") }) { Icon(Icons.Outlined.Add, null); Spacer(Modifier.width(6.dp)); Text("添加变量") }
            Button(
                onClick = {
                    val list = variables.filter { it.first.isNotBlank() }.map { PipelineVariable(it.first, it.second) }
                    actions.run<Pipeline>("已创建流水线", onSuccess = { navigator.replace(PipelineRoute(route.project, it.id)) }) { triggerPipeline(route.project, ref, list) }
                },
                enabled = !actions.busy && ref.isNotBlank(), modifier = Modifier.fillMaxWidth(),
            ) { if (actions.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("运行流水线") }
        }
    }
    if (picking) BranchPicker(route.project, ref, onPick = { ref = it }, onDismiss = { picking = false })
}
