package zone.routeforge.gitlabio.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Commit
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import zone.routeforge.gitlabio.core.Commit
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.Issue
import zone.routeforge.gitlabio.core.MergeRequest
import zone.routeforge.gitlabio.core.Pipeline
import zone.routeforge.gitlabio.core.Project
import zone.routeforge.gitlabio.ui.state.now
import zone.routeforge.gitlabio.ui.theme.CodeFont

/** Shared two-line row layout: leading visual, title, metadata, optional trailing content. */
@Composable
fun RowItem(
    onClick: () -> Unit,
    leading: @Composable () -> Unit,
    title: String,
    modifier: Modifier = Modifier,
    overline: String? = null,
    trailing: (@Composable () -> Unit)? = null,
    meta: @Composable () -> Unit = {},
) {
    Row(
        modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        leading()
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (overline != null) Text(overline, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            meta()
        }
        if (trailing != null) { Spacer(Modifier.width(8.dp)); trailing() }
    }
}

@Composable
fun MergeRequestRow(mr: MergeRequest, onClick: () -> Unit, showProject: Boolean = true) {
    val now = now()
    RowItem(
        onClick = onClick,
        leading = { StatusBadge(mergeRequestStatus(mr)) },
        title = mr.title,
        overline = if (showProject) mr.reference else "!${mr.iid}",
        trailing = mr.headPipeline.let { pipeline -> if (pipeline != null) ({ StatusBadge(pipelineStatus(pipeline.status), size = 22.dp) }) else null },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Meta(Icons.AutoMirrored.Filled.CallSplit, mr.sourceBranch, Modifier.weight(1f, fill = false))
            Meta(null, "${mr.author?.name ?: ""} · ${Format.relative(mr.updatedAt, now)}")
            if (mr.userNotesCount > 0) Meta(Icons.Outlined.ChatBubbleOutline, "${mr.userNotesCount}")
        }
        Labels(mr.labels)
    }
}

@Composable
fun IssueRow(issue: Issue, onClick: () -> Unit, showProject: Boolean = true) {
    val now = now()
    RowItem(
        onClick = onClick,
        leading = { StatusBadge(issueStatus(issue)) },
        title = issue.title,
        overline = if (showProject) issue.reference else "#${issue.iid}",
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Meta(null, "${issue.author?.name ?: ""} · ${Format.relative(issue.updatedAt, now)}", Modifier.weight(1f, fill = false))
            if (issue.confidential) Meta(Icons.Outlined.Lock, "机密")
            if (issue.userNotesCount > 0) Meta(Icons.Outlined.ChatBubbleOutline, "${issue.userNotesCount}")
        }
        Labels(issue.labels)
    }
}

@Composable
fun Labels(labels: List<String>, max: Int = 4) {
    if (labels.isEmpty()) return
    FlowRow(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        labels.take(max).forEach { LabelChip(it) }
        if (labels.size > max) Text("+${labels.size - max}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun PipelineRow(pipeline: Pipeline, onClick: () -> Unit, projectName: String? = null) {
    val now = now()
    RowItem(
        onClick = onClick,
        leading = { StatusBadge(pipelineStatus(pipeline.status)) },
        title = projectName ?: pipeline.ref,
        overline = "#${pipeline.iid ?: pipeline.id} · ${pipelineStatus(pipeline.status).label}",
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            if (projectName != null) Meta(Icons.AutoMirrored.Filled.CallSplit, pipeline.ref, Modifier.weight(1f, fill = false))
            pipeline.sha?.let { Meta(Icons.Outlined.Commit, it.take(8)) }
            Meta(Icons.Outlined.Schedule, Format.relative(pipeline.updatedAt ?: pipeline.createdAt, now))
            pipeline.duration?.let { Meta(Icons.Outlined.Timer, Format.duration(it)) }
        }
        pipeline.user?.let { Meta(null, "由 ${it.name} 触发 · ${sourceLabel(pipeline.source)}") }
    }
}

fun sourceLabel(source: String?) = when (source) {
    "push" -> "推送"
    "merge_request_event" -> "合并请求"
    "schedule" -> "计划"
    "web" -> "网页"
    "api" -> "API"
    "trigger" -> "触发器"
    "pipeline", "parent_pipeline" -> "上游流水线"
    null -> "未知来源"
    else -> source
}

@Composable
fun ProjectRow(project: Project, onClick: () -> Unit, starred: Boolean? = null, onStar: (() -> Unit)? = null) {
    val now = now()
    RowItem(
        onClick = onClick,
        leading = { ProjectMark(project.name) },
        title = project.name,
        overline = project.namespace?.fullPath ?: project.pathWithNamespace.substringBeforeLast('/'),
        trailing = if (onStar == null) null else ({
                IconButton(onClick = onStar, modifier = Modifier.size(40.dp)) {
                    Icon(
                        if (starred == true) Icons.Filled.Star else Icons.Outlined.StarBorder, if (starred == true) "取消星标" else "加星标",
                        tint = if (starred == true) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
        }),
    ) {
        project.description?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Meta(if (project.visibility == "public") Icons.Outlined.Public else Icons.Outlined.Lock, visibilityLabel(project.visibility))
            Meta(Icons.Outlined.StarBorder, "${project.starCount}")
            Meta(Icons.Outlined.Schedule, Format.relative(project.lastActivityAt, now))
        }
    }
}

fun visibilityLabel(visibility: String?) = when (visibility) {
    "public" -> "公开"
    "internal" -> "内部"
    "private" -> "私有"
    else -> "未知"
}

@Composable
fun CommitRow(commit: Commit, onClick: () -> Unit) {
    val now = now()
    RowItem(
        onClick = onClick,
        leading = { Avatar(commit.authorName ?: "?", size = 32.dp) },
        title = commit.title,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(commit.shortId, style = MaterialTheme.typography.labelMedium.copy(fontFamily = CodeFont), color = MaterialTheme.colorScheme.primary)
            Meta(null, "${commit.authorName ?: ""} · ${Format.relative(commit.authoredDate ?: commit.createdAt, now)}", Modifier.weight(1f, fill = false))
        }
    }
}
