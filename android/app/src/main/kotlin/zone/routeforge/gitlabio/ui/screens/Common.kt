package zone.routeforge.gitlabio.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import zone.routeforge.gitlabio.core.Discussion
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.Note
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.components.Avatar
import zone.routeforge.gitlabio.ui.components.BackButton
import zone.routeforge.gitlabio.ui.components.Markdown
import zone.routeforge.gitlabio.ui.components.Meta
import zone.routeforge.gitlabio.ui.state.now
import zone.routeforge.gitlabio.ui.state.rememberPaged

@Composable
fun ScreenScaffold(
    title: String,
    subtitle: String? = null,
    back: Boolean = true,
    actions: @Composable RowScope.() -> Unit = {},
    floatingActionButton: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    /** Caps the content column on tablets and landscape; code and logs pass [Dp.Unspecified] to use the full width. */
    maxContentWidth: Dp = ReadableWidth,
    content: @Composable (PaddingValues) -> Unit,
) {
    val navigator = LocalNavigator.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                },
                navigationIcon = { if (back) BackButton { navigator.back() } },
                actions = actions,
            )
        },
        floatingActionButton = floatingActionButton,
        bottomBar = bottomBar,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
    ) { padding ->
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.widthIn(max = maxContentWidth).fillMaxSize()) { content(padding) }
        }
    }
}

val ReadableWidth = 840.dp

/** A horizontally scrolling row of single-choice filter chips. */
@Composable
fun <T> ChoiceChips(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { (value, label) ->
            FilterChip(
                selected = value == selected, onClick = { onSelect(value) }, label = { Text(label) },
                leadingIcon = if (value == selected) ({ Icon(Icons.Filled.Check, null, Modifier.size(FilterChipDefaults.IconSize)) }) else null,
            )
        }
    }
}

@Composable
fun SearchField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    OutlinedTextField(
        value = value, onValueChange = onChange, singleLine = true,
        placeholder = { Text(placeholder) }, leadingIcon = { Icon(Icons.Outlined.Search, null) },
        shape = MaterialTheme.shapes.extraLarge,
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
    )
}

/** Bottom sheet that lists and searches branches; used for switching refs and picking sources. */
@Composable
fun BranchPicker(project: Long, current: String?, onPick: (String) -> Unit, onDismiss: () -> Unit, title: String = "选择分支") {
    var query by rememberSaveable { mutableStateOf("") }
    val branches = rememberPaged(project, "branch-picker", query) { page -> branches(project, query, page) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
        SearchField(query, { query = it }, "搜索分支")
        LazyColumn(Modifier.fillMaxWidth().navigationBarsPadding(), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (branches.items.isEmpty() && branches.state is zone.routeforge.gitlabio.ui.state.Load.Loading) {
                item { Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center) { CircularProgressIndicator() } }
            }
            items(branches.items, key = { it.name }) { branch ->
                val commit = branch.commit
                ListItem(
                    headlineContent = { Text(branch.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    supportingContent = if (commit != null) ({ Text(commit.title, maxLines = 1, overflow = TextOverflow.Ellipsis) }) else null,
                    leadingContent = { Icon(Icons.AutoMirrored.Filled.CallSplit, null) },
                    trailingContent = if (branch.name == current) ({ Icon(Icons.Filled.Check, "当前", tint = MaterialTheme.colorScheme.primary) }) else null,
                    modifier = Modifier.clickable { onPick(branch.name); onDismiss() },
                )
            }
            if (branches.hasMore) item {
                Row(Modifier.fillMaxWidth().clickable { branches.loadMore() }.padding(16.dp), horizontalArrangement = Arrangement.Center) { Text("加载更多", color = MaterialTheme.colorScheme.primary) }
            }
        }
    }
}

@Composable
fun NoteView(note: Note, modifier: Modifier = Modifier) {
    val now = now()
    if (note.system) {
        Row(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(10.dp))
            Text(
                "${note.author?.name ?: ""} ${note.body} · ${Format.relative(note.createdAt, now)}",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Avatar(note.author?.name ?: "?", size = 32.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(note.author?.name ?: "未知用户", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.width(6.dp))
                Meta(null, "@${note.author?.username ?: ""} · ${Format.relative(note.createdAt, now)}")
            }
            note.position?.newPath?.let { path ->
                Meta(null, "$path${note.position?.newLine?.let { ":$it" } ?: ""}", color = MaterialTheme.colorScheme.primary)
            }
            Markdown(note.body)
            if (note.resolvable && note.resolved) Meta(Icons.Filled.Check, "已解决")
        }
    }
}

@Composable
fun DiscussionView(discussion: Discussion) {
    if (discussion.individualNote || discussion.notes.size == 1) {
        discussion.notes.forEach { NoteView(it) }
        return
    }
    Surface(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp),
        shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(vertical = 4.dp)) {
            discussion.notes.forEachIndexed { index, note ->
                if (index > 0) HorizontalDivider(Modifier.padding(start = 60.dp), color = MaterialTheme.colorScheme.outlineVariant)
                NoteView(note)
            }
        }
    }
}

/** Comment box pinned to the bottom of discussion screens. */
@Composable
fun Composer(busy: Boolean, enabled: Boolean, onSend: (String, () -> Unit) -> Unit, placeholder: String = "添加评论（支持 Markdown）") {
    var text by rememberSaveable { mutableStateOf("") }
    Surface(tonalElevation = 3.dp, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.navigationBarsPadding().imePadding().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                value = text, onValueChange = { text = it }, modifier = Modifier.weight(1f), maxLines = 6,
                placeholder = { Text(if (enabled) placeholder else "令牌为只读，无法评论") }, enabled = enabled && !busy,
                shape = MaterialTheme.shapes.extraLarge,
            )
            IconButton(onClick = { onSend(text.trim()) { text = "" } }, enabled = enabled && !busy && text.isNotBlank()) {
                if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Icon(Icons.AutoMirrored.Filled.Send, "发送")
            }
        }
    }
}

@Composable
fun InfoLine(label: String, value: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().padding(vertical = 3.dp)) {
        Text(label, Modifier.width(88.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun rememberToggle(initial: Boolean = false) = remember { mutableStateOf(initial) }
