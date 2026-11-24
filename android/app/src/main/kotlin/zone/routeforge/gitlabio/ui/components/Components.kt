package zone.routeforge.gitlabio.ui.components

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MergeType
import androidx.compose.material.icons.filled.Adjust
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import zone.routeforge.gitlabio.core.Issue
import zone.routeforge.gitlabio.core.MergeRequest
import zone.routeforge.gitlabio.ui.state.Load
import zone.routeforge.gitlabio.ui.state.PagedModel
import zone.routeforge.gitlabio.ui.state.ResourceModel
import zone.routeforge.gitlabio.ui.theme.AppTheme
import zone.routeforge.gitlabio.ui.theme.ToneKey

data class StatusSpec(val label: String, val icon: ImageVector, val tone: ToneKey, val spinning: Boolean = false)

fun pipelineStatus(status: String): StatusSpec = when (status) {
    "success" -> StatusSpec("成功", Icons.Filled.CheckCircle, ToneKey.SUCCESS)
    "failed" -> StatusSpec("失败", Icons.Filled.Cancel, ToneKey.DANGER)
    "running" -> StatusSpec("运行中", Icons.Filled.Sync, ToneKey.INFO, spinning = true)
    "pending" -> StatusSpec("等待中", Icons.Filled.Schedule, ToneKey.WARNING)
    "waiting_for_resource" -> StatusSpec("等待资源", Icons.Filled.HourglassEmpty, ToneKey.WARNING)
    "preparing" -> StatusSpec("准备中", Icons.Filled.HourglassEmpty, ToneKey.WARNING)
    "created" -> StatusSpec("已创建", Icons.Filled.RadioButtonUnchecked, ToneKey.NEUTRAL)
    "canceled", "canceling" -> StatusSpec("已取消", Icons.Filled.Block, ToneKey.NEUTRAL)
    "skipped" -> StatusSpec("已跳过", Icons.Filled.SkipNext, ToneKey.NEUTRAL)
    "manual" -> StatusSpec("手动", Icons.Filled.PlayCircle, ToneKey.ACCENT)
    "scheduled" -> StatusSpec("已计划", Icons.Filled.Schedule, ToneKey.ACCENT)
    else -> StatusSpec(status, Icons.Filled.RadioButtonUnchecked, ToneKey.NEUTRAL)
}

fun mergeRequestStatus(mr: MergeRequest): StatusSpec = when {
    mr.state == "merged" -> StatusSpec("已合并", Icons.AutoMirrored.Filled.MergeType, ToneKey.ACCENT)
    mr.state == "closed" -> StatusSpec("已关闭", Icons.Filled.Cancel, ToneKey.DANGER)
    mr.draft -> StatusSpec("草稿", Icons.Filled.EditNote, ToneKey.NEUTRAL)
    mr.state == "locked" -> StatusSpec("已锁定", Icons.Filled.Block, ToneKey.NEUTRAL)
    else -> StatusSpec("开放", Icons.Filled.Adjust, ToneKey.SUCCESS)
}

fun issueStatus(issue: Issue): StatusSpec =
    if (issue.state == "closed") StatusSpec("已关闭", Icons.Filled.TaskAlt, ToneKey.INFO) else StatusSpec("开放", Icons.Filled.Adjust, ToneKey.SUCCESS)

@Composable
private fun StatusGlyph(spec: StatusSpec, size: Dp, tint: Color) {
    val angle = if (spec.spinning) {
        val transition = rememberInfiniteTransition(label = "spin")
        transition.animateFloat(0f, 360f, infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart), label = "angle").value
    } else 0f
    Icon(spec.icon, contentDescription = null, tint = tint, modifier = Modifier.size(size).rotate(angle))
}

/** Icon plus label on a tinted capsule; color is never the only signal. */
@Composable
fun StatusPill(spec: StatusSpec, modifier: Modifier = Modifier) {
    val tone = AppTheme.colors.tone(spec.tone)
    Row(
        modifier.clip(CircleShape).background(tone.container).padding(start = 6.dp, end = 10.dp, top = 3.dp, bottom = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StatusGlyph(spec, 16.dp, tone.content)
        Spacer(Modifier.width(4.dp))
        Text(spec.label, color = tone.content, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
    }
}

/** Compact round status marker for dense rows; the label is the content description. */
@Composable
fun StatusBadge(spec: StatusSpec, modifier: Modifier = Modifier, size: Dp = 28.dp) {
    val tone = AppTheme.colors.tone(spec.tone)
    Box(modifier.size(size).clip(CircleShape).background(tone.container), contentAlignment = Alignment.Center) {
        StatusGlyph(spec, size * 0.64f, tone.content)
    }
}

private val avatarTones = listOf(ToneKey.INFO, ToneKey.SUCCESS, ToneKey.ACCENT, ToneKey.WARNING, ToneKey.DANGER)

private fun stableHash(text: String) = text.fold(7) { acc, c -> acc * 31 + c.code }.let { if (it < 0) -it else it }

@Composable
fun Avatar(name: String, modifier: Modifier = Modifier, size: Dp = 36.dp) {
    val tone = AppTheme.colors.tone(avatarTones[stableHash(name) % avatarTones.size])
    val initials = name.split(' ', '.', '-', '_').filter { it.isNotBlank() }.take(2).joinToString("") { it.first().uppercase() }.ifEmpty { "?" }
    Box(modifier.size(size).clip(CircleShape).background(tone.container), contentAlignment = Alignment.Center) {
        Text(initials.take(2), color = tone.content, fontWeight = FontWeight.SemiBold, fontSize = (size.value * 0.38f).sp, maxLines = 1)
    }
}

/** Project or label initial on a rounded square. */
@Composable
fun ProjectMark(name: String, modifier: Modifier = Modifier, size: Dp = 40.dp) {
    val tone = AppTheme.colors.tone(avatarTones[stableHash(name) % avatarTones.size])
    Box(modifier.size(size).clip(RoundedCornerShape(size / 4)).background(tone.container), contentAlignment = Alignment.Center) {
        Text(name.take(1).uppercase(), color = tone.content, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.45f).sp)
    }
}

@Composable
fun LabelChip(label: String, modifier: Modifier = Modifier) {
    val scoped = label.split("::", limit = 2)
    val tone = AppTheme.colors.tone(avatarTones[stableHash(scoped.first()) % avatarTones.size])
    Text(
        if (scoped.size == 2) "${scoped[0]} · ${scoped[1]}" else label,
        modifier.clip(RoundedCornerShape(6.dp)).background(tone.container).padding(horizontal = 7.dp, vertical = 2.dp),
        color = tone.content, style = MaterialTheme.typography.labelSmall, maxLines = 1,
    )
}

@Composable
fun LoadingPane(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable
fun MessagePane(icon: ImageVector, title: String, message: String? = null, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
            Icon(icon, null, Modifier.padding(16.dp).size(32.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        if (message != null) Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 420.dp))
        if (action != null) { Spacer(Modifier.height(4.dp)); action() }
    }
}

@Composable
fun ErrorPane(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    MessagePane(Icons.Outlined.CloudOff, "加载失败", message, modifier) { FilledTonalButton(onClick = onRetry) { Text("重试") } }
}

@Composable
fun EmptyPane(title: String, message: String? = null, icon: ImageVector = Icons.Outlined.Inbox, modifier: Modifier = Modifier) {
    MessagePane(icon, title, message, modifier)
}

/** Shows loading and errors for [model], pull-to-refresh, and [content] once data is there. */
@Composable
fun <T> ResourceContent(model: ResourceModel<T>, modifier: Modifier = Modifier, content: @Composable (T) -> Unit) {
    when (val state = model.state) {
        Load.Loading -> LoadingPane(modifier)
        is Load.Failed -> Box(modifier.fillMaxSize()) { ErrorPane(state.message, { model.reload() }) }
        is Load.Ready -> PullToRefreshBox(isRefreshing = model.refreshing, onRefresh = { model.reload() }, modifier = modifier.fillMaxSize()) {
            content(state.value)
        }
    }
}

/**
 * A pull-to-refresh lazy list fed by [model] that asks for the next page near the end.
 * [header] items come first and are shown even while the list is empty.
 */
@Composable
fun <T> PagedList(
    model: PagedModel<T>,
    modifier: Modifier = Modifier,
    key: ((T) -> Any)? = null,
    empty: @Composable () -> Unit = { EmptyPane("这里还没有内容") },
    state: LazyListState = rememberLazyListState(),
    contentPadding: PaddingValues = PaddingValues(bottom = 96.dp),
    header: LazyListScope.() -> Unit = {},
    itemContent: @Composable (T) -> Unit,
) {
    val nearEnd by remember(state) {
        derivedStateOf {
            val info = state.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()?.index ?: 0
            info.totalItemsCount > 0 && last >= info.totalItemsCount - 5
        }
    }
    LaunchedEffect(state, model) {
        snapshotFlow { nearEnd }.collect { if (it) model.loadMore() }
    }
    PullToRefreshBox(isRefreshing = model.refreshing, onRefresh = { model.reload() }, modifier = modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), state = state, contentPadding = contentPadding) {
            header()
            when (val load = model.state) {
                Load.Loading -> item { LoadingPane() }
                is Load.Failed -> item { ErrorPane(load.message, { model.reload() }) }
                is Load.Ready -> {
                    if (model.items.isEmpty()) item { empty() }
                    items(model.items.size, key = key?.let { k -> { index: Int -> k(model.items[index]) } }) { index -> itemContent(model.items[index]) }
                    if (model.loadingMore) item { Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp)) } }
                    model.moreError?.let { message ->
                        item {
                            Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(message, Modifier.weight(1f), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                                TextButton(onClick = { if (model.hasMore) model.loadMore() else model.reload() }) { Text("重试") }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SectionTitle(title: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 20.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

/** Small icon + text used for metadata under list titles. */
@Composable
fun Meta(icon: ImageVector?, text: String, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Icon(icon, null, Modifier.size(14.dp), tint = color)
            Spacer(Modifier.width(3.dp))
        }
        Text(text, style = MaterialTheme.typography.bodySmall, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun BackButton(onClick: () -> Unit) {
    IconButton(onClick = onClick) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回") }
}

@Composable
fun ConfirmDialog(
    title: String, message: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit,
    destructive: Boolean = false, content: (@Composable () -> Unit)? = null,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(message)
                content?.invoke()
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(); onDismiss() },
                colors = if (destructive) androidx.compose.material3.ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError,
                ) else androidx.compose.material3.ButtonDefaults.buttonColors(),
            ) { Text(confirm) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}

/** Opens http(s) links in the browser; anything else is ignored rather than crashing. */
@Composable
fun rememberOpenUrl(): (String?) -> Unit {
    val context = LocalContext.current
    return remember(context) {
        { url ->
            if (url != null && (url.startsWith("https://") || url.startsWith("http://"))) {
                try {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (_: ActivityNotFoundException) {
                }
            }
        }
    }
}
