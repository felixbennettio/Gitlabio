package zone.routeforge.gitlabio.ui.screens

import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.MergeType
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.WrapText
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.NoteAdd
import androidx.compose.material.icons.outlined.ShoppingBasket
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import zone.routeforge.gitlabio.core.Branch
import zone.routeforge.gitlabio.core.Commit
import zone.routeforge.gitlabio.core.FileDiff
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.MergeRequest
import zone.routeforge.gitlabio.core.MergeRequestDraft
import zone.routeforge.gitlabio.core.Syntax
import zone.routeforge.gitlabio.data.BasketChange
import zone.routeforge.gitlabio.data.ChangeKind
import zone.routeforge.gitlabio.ui.BasketRoute
import zone.routeforge.gitlabio.ui.BranchesRoute
import zone.routeforge.gitlabio.ui.CommitRoute
import zone.routeforge.gitlabio.ui.CommitsRoute
import zone.routeforge.gitlabio.ui.EditFileRoute
import zone.routeforge.gitlabio.ui.FileRoute
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.MergeRequestRoute
import zone.routeforge.gitlabio.ui.NewMergeRequestRoute
import zone.routeforge.gitlabio.ui.TreeRoute
import zone.routeforge.gitlabio.ui.components.Avatar
import zone.routeforge.gitlabio.ui.components.CodeView
import zone.routeforge.gitlabio.ui.components.CommitRow
import zone.routeforge.gitlabio.ui.components.ConfirmDialog
import zone.routeforge.gitlabio.ui.components.EmptyPane
import zone.routeforge.gitlabio.ui.components.ErrorPane
import zone.routeforge.gitlabio.ui.components.HighlightedSource
import zone.routeforge.gitlabio.ui.components.LabelChip
import zone.routeforge.gitlabio.ui.components.LoadingPane
import zone.routeforge.gitlabio.ui.components.Markdown
import zone.routeforge.gitlabio.ui.components.MessagePane
import zone.routeforge.gitlabio.ui.components.Meta
import zone.routeforge.gitlabio.ui.components.PagedList
import zone.routeforge.gitlabio.ui.components.ResourceContent
import zone.routeforge.gitlabio.ui.components.diffItems
import zone.routeforge.gitlabio.ui.components.prepareDiffs
import zone.routeforge.gitlabio.ui.components.rememberOpenUrl
import zone.routeforge.gitlabio.ui.state.Load
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.LocalSnackbar
import zone.routeforge.gitlabio.ui.state.PagedModel
import zone.routeforge.gitlabio.ui.state.now
import zone.routeforge.gitlabio.ui.state.rememberActions
import zone.routeforge.gitlabio.ui.state.rememberPaged
import zone.routeforge.gitlabio.ui.state.rememberResource
import zone.routeforge.gitlabio.ui.theme.AppTheme
import zone.routeforge.gitlabio.ui.theme.CodeFont
import zone.routeforge.gitlabio.ui.theme.ToneKey

@Composable
private fun BasketButton(project: Long, ref: String) {
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    val count = session.basket.changes(project, ref).size
    if (count == 0) return
    IconButton(onClick = { navigator.open(BasketRoute(project, ref)) }) {
        BadgedBox(badge = { Badge { Text("$count") } }) { Icon(Icons.Outlined.ShoppingBasket, "变更篮") }
    }
}

@Composable
private fun Breadcrumbs(root: String, path: String, onOpen: (String) -> Unit) {
    val segments = if (path.isEmpty()) emptyList() else path.split('/')
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Crumb(root, segments.isEmpty()) { onOpen("") }
        segments.forEachIndexed { index, segment ->
            Text("/", Modifier.padding(horizontal = 2.dp), color = MaterialTheme.colorScheme.outline)
            Crumb(segment, index == segments.lastIndex) { onOpen(segments.take(index + 1).joinToString("/")) }
        }
    }
}

@Composable
private fun Crumb(label: String, current: Boolean, onClick: () -> Unit) {
    Text(
        label,
        Modifier.clickable(enabled = !current, onClick = onClick).padding(horizontal = 6.dp, vertical = 6.dp),
        style = MaterialTheme.typography.labelLarge,
        color = if (current) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.primary,
        fontWeight = if (current) FontWeight.SemiBold else null,
    )
}

@Composable
fun TreeScreen(route: TreeRoute) {
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    var picker by remember { mutableStateOf(false) }
    val project = rememberResource("project", route.project) { project(route.project) }
    val entries = rememberPaged("tree", route.project, route.ref, route.path) { page -> tree(route.project, route.ref, route.path, page) }
    val pending = session.basket.changes(route.project, route.ref)
    val prefix = if (route.path.isEmpty()) "" else route.path + "/"
    val created = pending.filter { it.kind == ChangeKind.CREATE && it.path.startsWith(prefix) && '/' !in it.path.removePrefix(prefix) }

    ScreenScaffold(
        title = project.value?.name ?: "代码",
        subtitle = route.path.ifEmpty { null },
        actions = {
            BasketButton(route.project, route.ref)
            IconButton(onClick = { navigator.open(CommitsRoute(route.project, route.ref, route.path)) }) { Icon(Icons.Outlined.History, "提交历史") }
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { navigator.open(EditFileRoute(route.project, route.ref, prefix, create = true)) },
                icon = { Icon(Icons.Outlined.NoteAdd, null) }, text = { Text("新建文件") },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                AssistChip(onClick = { picker = true }, label = { Text(route.ref, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    leadingIcon = { Icon(Icons.AutoMirrored.Filled.CallSplit, null, Modifier.size(18.dp)) })
                Spacer(Modifier.width(8.dp))
                AssistChip(onClick = { navigator.open(BranchesRoute(route.project)) }, label = { Text("分支") },
                    leadingIcon = { Icon(Icons.Outlined.AccountTree, null, Modifier.size(18.dp)) })
            }
            Breadcrumbs(project.value?.name ?: "根目录", route.path) { navigator.open(TreeRoute(route.project, route.ref, it)) }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            PagedList(entries, key = { it.path }, empty = { if (created.isEmpty()) EmptyPane("空目录") }, header = {
                items(created, key = { "new:${it.path}" }) { change ->
                    TreeRow(change.path.substringAfterLast('/'), false, change) { navigator.open(FileRoute(route.project, route.ref, change.path)) }
                }
            }) { entry ->
                TreeRow(entry.name, entry.isDirectory, pending.firstOrNull { it.path == entry.path }) {
                    navigator.open(if (entry.isDirectory) TreeRoute(route.project, route.ref, entry.path) else FileRoute(route.project, route.ref, entry.path))
                }
            }
        }
    }
    if (picker) BranchPicker(route.project, route.ref, onPick = { navigator.replace(TreeRoute(route.project, it, "")) }, onDismiss = { picker = false })
}

@Composable
private fun TreeRow(name: String, directory: Boolean, change: BasketChange?, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(
            if (directory) Icons.Outlined.Folder else Icons.Outlined.InsertDriveFile, null,
            tint = if (directory) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(16.dp))
        Text(
            name, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis,
            textDecoration = if (change?.kind == ChangeKind.DELETE) TextDecoration.LineThrough else null,
        )
        if (change != null) ChangeBadge(change.kind)
    }
}

@Composable
private fun ChangeBadge(kind: ChangeKind) {
    val (label, tone) = when (kind) {
        ChangeKind.CREATE -> "新增" to ToneKey.SUCCESS
        ChangeKind.UPDATE -> "已修改" to ToneKey.WARNING
        ChangeKind.DELETE -> "删除" to ToneKey.DANGER
    }
    val colors = AppTheme.colors.tone(tone)
    Surface(shape = MaterialTheme.shapes.small, color = colors.container) {
        Text(label, Modifier.padding(horizontal = 6.dp, vertical = 2.dp), color = colors.content, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
fun FileScreen(route: FileRoute) {
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    val snackbar = LocalSnackbar.current
    val scope = rememberCoroutineScope()
    val openUrl = rememberOpenUrl()
    val pending = session.basket.change(route.project, route.ref, route.path)
    val remote = rememberResource("file", route.project, route.ref, route.path, pending?.kind == ChangeKind.CREATE) {
        if (pending?.kind == ChangeKind.CREATE) null else file(route.project, route.ref, route.path)
    }
    val project = rememberResource("project", route.project) { project(route.project) }
    var wrap by rememberSaveable { mutableStateOf(false) }
    val markdown = route.path.endsWith(".md", true) || route.path.endsWith(".markdown", true)
    var preview by rememberSaveable { mutableStateOf(markdown) }
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val name = route.path.substringAfterLast('/')

    ScreenScaffold(
        title = name, subtitle = "${route.ref} · ${route.path}", maxContentWidth = Dp.Unspecified,
        actions = {
            BasketButton(route.project, route.ref)
            if (markdown) IconButton(onClick = { preview = !preview }) { Icon(if (preview) Icons.Outlined.Description else Icons.Outlined.Visibility, if (preview) "查看源码" else "预览") }
            if (!preview) IconButton(onClick = { wrap = !wrap }) { Icon(Icons.AutoMirrored.Filled.WrapText, if (wrap) "取消换行" else "自动换行") }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, "更多") }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem(text = { Text("编辑") }, leadingIcon = { Icon(Icons.Outlined.Edit, null) }, enabled = pending?.kind != ChangeKind.DELETE,
                        onClick = { menu = false; navigator.open(EditFileRoute(route.project, route.ref, route.path)) })
                    DropdownMenuItem(text = { Text("删除文件") }, leadingIcon = { Icon(Icons.Outlined.Delete, null) }, enabled = pending?.kind != ChangeKind.DELETE,
                        onClick = { menu = false; confirmDelete = true })
                    DropdownMenuItem(text = { Text("提交历史") }, leadingIcon = { Icon(Icons.Outlined.History, null) },
                        onClick = { menu = false; navigator.open(CommitsRoute(route.project, route.ref, route.path)) })
                    val webUrl = project.value?.webUrl
                    if (!session.isDemo && webUrl != null) DropdownMenuItem(text = { Text("在浏览器中打开") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.OpenInNew, null) }, onClick = {
                        menu = false
                        openUrl("$webUrl/-/blob/${Uri.encode(route.ref, "/")}/${Uri.encode(route.path, "/")}")
                    })
                }
            }
        },
        floatingActionButton = {
            if (pending?.kind != ChangeKind.DELETE) {
                ExtendedFloatingActionButton(onClick = { navigator.open(EditFileRoute(route.project, route.ref, route.path)) },
                    icon = { Icon(Icons.Outlined.Edit, null) }, text = { Text("编辑") })
            }
        },
    ) { padding ->
        ResourceContent(remote, Modifier.padding(padding)) { file ->
            val text = pending?.content ?: file?.textOrNull()
            Column(Modifier.fillMaxSize()) {
                when (pending?.kind) {
                    ChangeKind.CREATE, ChangeKind.UPDATE -> Banner("显示的是变更篮中尚未提交的版本。", ToneKey.WARNING)
                    ChangeKind.DELETE -> Banner("此文件已在变更篮中标记为删除。", ToneKey.DANGER)
                    null -> Unit
                }
                when {
                    text == null -> MessagePane(
                        Icons.Outlined.InsertDriveFile, "无法预览此文件",
                        "二进制文件或超过 1 MiB 的文件不能在应用内显示（${Format.bytes(file?.size ?: 0)}）。",
                    )
                    preview && markdown -> LazyColumn(contentPadding = PaddingValues(16.dp)) { item { Markdown(text) } }
                    else -> {
                        val language = Syntax.languageFor(route.path)
                        var source by remember { mutableStateOf<HighlightedSource?>(null) }
                        LaunchedEffect(text) { source = withContext(Dispatchers.Default) { HighlightedSource(text, language) } }
                        source?.let { CodeView(it, wrap) } ?: LoadingPane()
                    }
                }
            }
        }
    }
    if (confirmDelete) {
        ConfirmDialog(
            "删除 $name？", "删除会先放进变更篮，提交后才会生效。", "加入变更篮",
            onConfirm = {
                session.basket.put(route.project, route.ref, BasketChange(route.path, ChangeKind.DELETE, lastCommitId = remote.value?.lastCommitId))
                scope.launch { snackbar.showSnackbar("已加入变更篮") }
            },
            onDismiss = { confirmDelete = false }, destructive = true,
        )
    }
}

@Composable
private fun Banner(text: String, tone: ToneKey) {
    val colors = AppTheme.colors.tone(tone)
    Surface(color = colors.container, modifier = Modifier.fillMaxWidth()) {
        Text(text, Modifier.padding(horizontal = 16.dp, vertical = 10.dp), color = colors.content, style = MaterialTheme.typography.bodySmall)
    }
}

private fun validPath(path: String) = path.isNotBlank() && !path.startsWith("/") && !path.endsWith("/") &&
    path.split('/').none { it.isEmpty() || it == "." || it == ".." }

@Composable
fun EditFileScreen(route: EditFileRoute) {
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    val snackbar = LocalSnackbar.current
    val scope = rememberCoroutineScope()
    val pending = session.basket.change(route.project, route.ref, route.path)
    val remote = rememberResource("edit-file", route.project, route.ref, route.path, route.create) {
        if (route.create || pending?.kind == ChangeKind.CREATE) null else file(route.project, route.ref, route.path)
    }
    var path by rememberSaveable { mutableStateOf(route.path) }
    var text by remember { mutableStateOf<String?>(null) }
    var original by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(remote.state) {
        val state = remote.state
        if (text == null && state is Load.Ready) {
            val file = state.value
            if (file != null && file.textOrNull() == null) error = "此文件不是可编辑的 UTF-8 文本或超过 1 MiB。"
            original = file?.textOrNull() ?: ""
            text = pending?.content ?: original
        }
    }

    fun save() {
        val content = text ?: return
        if (route.create && !validPath(path)) { error = "请填写有效的文件路径，例如 docs/notes.md"; return }
        val target = if (route.create) path.trim() else route.path
        if (route.create && session.basket.change(route.project, route.ref, target) != null) { error = "变更篮中已有同名文件。"; return }
        if (!route.create && pending == null && content == original) { navigator.back(); return }
        session.basket.put(
            route.project, route.ref,
            BasketChange(target, if (route.create) ChangeKind.CREATE else pending?.kind ?: ChangeKind.UPDATE, content, remote.value?.lastCommitId ?: pending?.lastCommitId),
        )
        scope.launch { snackbar.showSnackbar("已加入变更篮，共 ${session.basket.changes(route.project, route.ref).size} 项") }
        navigator.back()
    }

    ScreenScaffold(
        title = if (route.create) "新建文件" else route.path.substringAfterLast('/'),
        subtitle = "分支 ${route.ref}",
        actions = { TextButton(onClick = ::save, enabled = text != null && error?.startsWith("此文件") != true) { Text("加入变更篮") } },
    ) { padding ->
        ResourceContent(remote, Modifier.padding(padding)) {
            Column(Modifier.fillMaxSize().imePadding().padding(horizontal = 12.dp)) {
                if (route.create) {
                    OutlinedTextField(
                        path, { path = it; error = null }, Modifier.fillMaxWidth(), label = { Text("文件路径") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont),
                    )
                    Spacer(Modifier.size(8.dp))
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(bottom = 6.dp)) }
                OutlinedTextField(
                    value = text ?: "", onValueChange = { text = it }, enabled = text != null,
                    modifier = Modifier.fillMaxWidth().weight(1f).padding(bottom = 8.dp),
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                    placeholder = { Text("文件内容") },
                )
            }
        }
    }
}

@Composable
fun BasketScreen(route: BasketRoute) {
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    val actions = rememberActions()
    val changes = session.basket.changes(route.project, route.ref)
    val branch = rememberResource("basket-branch", route.project, route.ref) {
        branches(route.project, route.ref).items.firstOrNull { it.name == route.ref }
    }
    val defaultMessage = when (changes.size) {
        1 -> "${verb(changes[0].kind)} ${changes[0].path.substringAfterLast('/')}"
        else -> "Update ${changes.size} files"
    }
    var message by rememberSaveable { mutableStateOf("") }
    var newBranch by rememberSaveable { mutableStateOf(false) }
    var branchName by rememberSaveable { mutableStateOf("gitlabio/edit-${System.currentTimeMillis() / 1000 % 100000}") }
    var openMr by rememberSaveable { mutableStateOf(true) }
    val protected = branch.value?.let { it.protected && !it.canPush } ?: false
    val useNewBranch = newBranch || protected

    ScreenScaffold(title = "变更篮", subtitle = "${changes.size} 项更改 · ${route.ref}") { padding ->
        if (changes.isEmpty()) {
            EmptyPane("变更篮是空的", "在代码浏览中编辑、新建或删除文件，它们会先放在这里，再一次性提交。", Icons.Outlined.ShoppingBasket, Modifier.padding(padding))
            return@ScreenScaffold
        }
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).imePadding()) {
            changes.forEach { change ->
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    ChangeBadge(change.kind)
                    Spacer(Modifier.width(12.dp))
                    Text(change.path, Modifier.weight(1f).clickable { navigator.open(FileRoute(route.project, route.ref, change.path)) },
                        style = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    IconButton(onClick = { session.basket.remove(route.project, route.ref, change.path) }) { Icon(Icons.Filled.Close, "移出变更篮") }
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.outlineVariant)
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(message, { message = it }, Modifier.fillMaxWidth(), label = { Text("提交说明") }, placeholder = { Text(defaultMessage) }, minLines = 2)
                Text("提交到", style = MaterialTheme.typography.titleSmall)
                Row(Modifier.fillMaxWidth().selectable(!useNewBranch, enabled = !protected) { newBranch = false }, verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = !useNewBranch, onClick = null, enabled = !protected)
                    Spacer(Modifier.width(8.dp))
                    Column {
                        Text("当前分支 ${route.ref}")
                        if (protected) Text("受保护分支，你不能直接推送", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                    }
                }
                Row(Modifier.fillMaxWidth().selectable(useNewBranch) { newBranch = true }, verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = useNewBranch, onClick = null)
                    Spacer(Modifier.width(8.dp))
                    Text("新建分支并提交")
                }
                if (useNewBranch) {
                    OutlinedTextField(branchName, { branchName = it.trim() }, Modifier.fillMaxWidth(), label = { Text("新分支名") }, singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CodeFont))
                    Row(Modifier.fillMaxWidth().clickable { openMr = !openMr }, verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(openMr, null)
                        Spacer(Modifier.width(8.dp))
                        Text("同时创建合并请求到 ${route.ref}")
                    }
                }
                Spacer(Modifier.size(4.dp))
                Button(
                    onClick = {
                        val text = message.ifBlank { defaultMessage }
                        val target = if (useNewBranch) branchName else route.ref
                        val commitActions = session.basket.actions(route.project, route.ref)
                        actions.run<Pair<Commit, MergeRequest?>>(
                            "已提交 ${commitActions.size} 项更改",
                            onSuccess = { (commit, mr) ->
                                session.basket.clear(route.project, route.ref)
                                navigator.replace(if (mr != null) MergeRequestRoute(mr.projectId, mr.iid) else CommitRoute(route.project, commit.id))
                            },
                        ) {
                            val commit = commitChanges(route.project, target, text, commitActions, startBranch = if (useNewBranch) route.ref else null)
                            val mr = if (useNewBranch && openMr) createMergeRequest(route.project, MergeRequestDraft(target, route.ref, text.lineSequence().first(), removeSourceBranch = true)) else null
                            commit to mr
                        }
                    },
                    enabled = !actions.busy && (!useNewBranch || branchName.isNotBlank()) && session.capabilities.canWrite,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (actions.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("提交 ${changes.size} 项更改")
                }
                if (!session.capabilities.canWrite) Text("当前令牌没有 api 范围，无法提交。", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                Text("使用 Commits API 一次提交；若文件在服务器上已被他人修改，提交会被拒绝且变更篮保留。",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.size(24.dp))
            }
        }
    }
}

private fun verb(kind: ChangeKind) = when (kind) {
    ChangeKind.CREATE -> "Add"
    ChangeKind.UPDATE -> "Update"
    ChangeKind.DELETE -> "Delete"
}

@Composable
fun BranchesScreen(projectId: Long) {
    val navigator = LocalNavigator.current
    val actions = rememberActions()
    var search by rememberSaveable { mutableStateOf("") }
    var creating by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<Branch?>(null) }
    val project = rememberResource("project", projectId) { project(projectId) }
    val branches = rememberPaged("branches", projectId, search) { page -> branches(projectId, search, page) }
    val now = now()

    ScreenScaffold(
        title = "分支", subtitle = project.value?.pathWithNamespace,
        floatingActionButton = {
            ExtendedFloatingActionButton(onClick = { creating = true }, icon = { Icon(Icons.Outlined.Add, null) }, text = { Text("新建分支") })
        },
    ) { padding ->
        Column(Modifier.padding(padding)) {
            SearchField(search, { search = it }, "搜索分支")
            PagedList(branches, key = { it.name }, empty = { EmptyPane("没有匹配的分支") }) { branch ->
                var menu by remember { mutableStateOf(false) }
                Row(
                    Modifier.fillMaxWidth().clickable { navigator.open(TreeRoute(projectId, branch.name)) }.padding(start = 16.dp, end = 4.dp, top = 10.dp, bottom = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.AutoMirrored.Filled.CallSplit, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(16.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(branch.name, style = MaterialTheme.typography.bodyLarge.copy(fontFamily = CodeFont), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (branch.default) LabelChip("默认")
                            if (branch.protected) LabelChip("受保护")
                            if (branch.merged) LabelChip("已合并")
                        }
                        branch.commit?.let { Meta(null, "${it.title} · ${Format.relative(it.committedDate ?: it.createdAt, now)}") }
                    }
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, "更多") }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem(text = { Text("提交历史") }, leadingIcon = { Icon(Icons.Outlined.History, null) },
                                onClick = { menu = false; navigator.open(CommitsRoute(projectId, branch.name)) })
                            if (!branch.default) DropdownMenuItem(text = { Text("新建合并请求") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.MergeType, null) },
                                onClick = { menu = false; navigator.open(NewMergeRequestRoute(projectId, branch.name)) })
                            DropdownMenuItem(text = { Text("删除分支") }, leadingIcon = { Icon(Icons.Outlined.Delete, null) }, enabled = !branch.default && !branch.protected,
                                onClick = { menu = false; deleting = branch })
                        }
                    }
                }
            }
        }
    }
    if (creating) {
        var name by remember { mutableStateOf("") }
        var from by remember { mutableStateOf(project.value?.defaultBranch ?: "main") }
        AlertDialog(
            onDismissRequest = { creating = false },
            title = { Text("新建分支") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(name, { name = it.trim() }, label = { Text("分支名") }, singleLine = true)
                    OutlinedTextField(from, { from = it.trim() }, label = { Text("基于（分支、标签或提交）") }, singleLine = true)
                }
            },
            confirmButton = {
                Button(enabled = name.isNotBlank() && from.isNotBlank() && !actions.busy, onClick = {
                    actions.run<Branch>("已创建分支 $name", onSuccess = { creating = false; navigator.open(TreeRoute(projectId, it.name)) }) { createBranch(projectId, name, from) }
                }) { Text("创建") }
            },
            dismissButton = { TextButton(onClick = { creating = false }) { Text("取消") } },
        )
    }
    deleting?.let { branch ->
        ConfirmDialog("删除分支 ${branch.name}？", "此操作会删除远程分支，无法在应用内撤销。", "删除",
            onConfirm = { actions.run<Unit>("已删除分支 ${branch.name}") { deleteBranch(projectId, branch.name) } },
            onDismiss = { deleting = null }, destructive = true)
    }
}

@Composable
fun CommitsScreen(route: CommitsRoute) {
    val navigator = LocalNavigator.current
    var picker by remember { mutableStateOf(false) }
    val commits = rememberPaged("commits", route.project, route.ref, route.path) { page -> commits(route.project, route.ref, route.path, page) }
    ScreenScaffold(title = "提交历史", subtitle = listOf(route.ref, route.path).filter { it.isNotEmpty() }.joinToString(" · ")) { padding ->
        Column(Modifier.padding(padding)) {
            Row(Modifier.padding(horizontal = 16.dp)) {
                AssistChip(onClick = { picker = true }, label = { Text(route.ref) }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.CallSplit, null, Modifier.size(18.dp)) })
            }
            PagedList(commits, key = { it.id }, empty = { EmptyPane("没有提交") }) { commit ->
                CommitRow(commit) { navigator.open(CommitRoute(route.project, commit.id)) }
            }
        }
    }
    if (picker) BranchPicker(route.project, route.ref, onPick = { navigator.replace(CommitsRoute(route.project, it, route.path)) }, onDismiss = { picker = false })
}

@Composable
fun CommitScreen(route: CommitRoute) {
    val clipboard = LocalClipboardManager.current
    val snackbar = LocalSnackbar.current
    val scope = rememberCoroutineScope()
    val openUrl = rememberOpenUrl()
    val session = LocalSession.current
    val commit = rememberResource("commit", route.project, route.sha) { commit(route.project, route.sha) }
    val diffs = rememberPaged("commit-diff", route.project, route.sha) { page -> commitDiff(route.project, route.sha, page) }
    ScreenScaffold(
        title = commit.value?.title ?: "提交", subtitle = route.sha.take(8),
        actions = {
            IconButton(onClick = {
                clipboard.setText(AnnotatedString(route.sha))
                scope.launch { snackbar.showSnackbar("已复制提交 SHA") }
            }) { Icon(Icons.Outlined.ContentCopy, "复制 SHA") }
            if (!session.isDemo) commit.value?.webUrl?.let { url -> IconButton(onClick = { openUrl(url) }) { Icon(Icons.AutoMirrored.Filled.OpenInNew, "在浏览器中打开") } }
        },
    ) { padding ->
        DiffPane(diffs, Modifier.padding(padding)) {
            item {
                val value = commit.value
                if (value != null) CommitHeader(value)
                else if (commit.state is Load.Failed) ErrorPane((commit.state as Load.Failed).message, { commit.reload() })
            }
        }
    }
}

@Composable
private fun CommitHeader(commit: Commit) {
    val now = now()
    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(commit.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        val body = commit.message?.substringAfter('\n', "")?.trim().orEmpty()
        if (body.isNotEmpty()) Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(commit.authorName ?: "?", size = 28.dp)
            Spacer(Modifier.width(8.dp))
            Text("${commit.authorName ?: ""} · ${Format.relative(commit.authoredDate ?: commit.createdAt, now)}", style = MaterialTheme.typography.bodySmall)
        }
        Text(commit.id, style = MaterialTheme.typography.labelSmall.copy(fontFamily = CodeFont), color = MaterialTheme.colorScheme.onSurfaceVariant)
        commit.stats?.let { stats ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("+${stats.additions}", color = AppTheme.colors.tone(ToneKey.SUCCESS).content, style = MaterialTheme.typography.labelLarge)
                Text("−${stats.deletions}", color = AppTheme.colors.tone(ToneKey.DANGER).content, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
}

/** Paged file diffs with collapsible files; [header] scrolls with the diff. */
@Composable
fun DiffPane(model: PagedModel<FileDiff>, modifier: Modifier = Modifier, header: LazyListScope.() -> Unit = {}) {
    val colors = AppTheme.colors
    val rows = remember(model.items) { prepareDiffs(model.items) }
    var collapsed by remember { mutableStateOf(setOf<String>()) }
    val state = rememberLazyListState()
    val nearEnd by remember(state) {
        derivedStateOf { state.layoutInfo.let { (it.visibleItemsInfo.lastOrNull()?.index ?: 0) >= it.totalItemsCount - 10 } }
    }
    LaunchedEffect(state, model) { snapshotFlow { nearEnd }.collect { if (it) model.loadMore() } }
    PullToRefreshBox(isRefreshing = model.refreshing, onRefresh = { model.reload() }, modifier = modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), state = state, contentPadding = PaddingValues(bottom = 96.dp)) {
            header()
            when (val load = model.state) {
                Load.Loading -> item { LoadingPane() }
                is Load.Failed -> item { ErrorPane(load.message, { model.reload() }) }
                is Load.Ready -> {
                    if (rows.isEmpty()) item { EmptyPane("没有文件变更") }
                    else item {
                        Text(
                            "${rows.size}${if (model.hasMore) "+" else ""} 个文件 · +${rows.sumOf { it.added }} −${rows.sumOf { it.removed }}",
                            Modifier.padding(horizontal = 16.dp, vertical = 10.dp), style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    diffItems(rows, colors, collapsed) { path -> collapsed = if (path in collapsed) collapsed - path else collapsed + path }
                    if (model.loadingMore) item { Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp)) } }
                    model.moreError?.let { message -> item { Text(message, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error) } }
                }
            }
        }
    }
}
