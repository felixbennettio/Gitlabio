package zone.routeforge.gitlabio.ui.screens

import android.Manifest
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Fingerprint
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import zone.routeforge.gitlabio.BuildConfig
import zone.routeforge.gitlabio.R
import zone.routeforge.gitlabio.core.CertificateSummary
import zone.routeforge.gitlabio.core.Certificates
import zone.routeforge.gitlabio.core.Format
import zone.routeforge.gitlabio.core.GitLabInstance
import zone.routeforge.gitlabio.core.TrustPolicy
import zone.routeforge.gitlabio.core.describeError
import zone.routeforge.gitlabio.data.StoredAccount
import zone.routeforge.gitlabio.data.ThemeMode
import zone.routeforge.gitlabio.data.Verification
import zone.routeforge.gitlabio.notifications.TodoNotifications
import zone.routeforge.gitlabio.ui.AccountEditorRoute
import zone.routeforge.gitlabio.ui.LocalDependencies
import zone.routeforge.gitlabio.ui.LocalNavigator
import zone.routeforge.gitlabio.ui.components.Avatar
import zone.routeforge.gitlabio.ui.components.ConfirmDialog
import zone.routeforge.gitlabio.ui.components.LabelChip
import zone.routeforge.gitlabio.ui.components.SectionTitle
import zone.routeforge.gitlabio.ui.components.rememberOpenUrl
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.LocalSnackbar
import zone.routeforge.gitlabio.ui.theme.AppTheme
import zone.routeforge.gitlabio.ui.theme.CodeFont
import zone.routeforge.gitlabio.ui.theme.ToneKey

/** First screen without any account: sign in or try the demo. */
@Composable
fun WelcomeScreen() {
    val accounts = LocalDependencies.current.accounts
    val error by accounts.error.collectAsStateWithLifecycle()
    Box(Modifier.fillMaxSize().safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 560.dp).fillMaxWidth().verticalScroll(rememberScrollState()).imePadding().padding(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Image(painterResource(R.drawable.ic_gitlabio), null, Modifier.size(64.dp))
                Text("Gitlabio", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                Text("gitlab.com 与自建 GitLab 的原生客户端", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            AccountForm(existing = null, onSaved = {})
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            OutlinedButton(onClick = { accounts.startDemo() }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Outlined.Science, null)
                Spacer(Modifier.width(8.dp))
                Text("不登录，先体验演示数据")
            }
            Text("演示模式使用内置的合成数据，不会连接任何服务器。", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }
    }
}

@Composable
fun AccountEditorScreen(accountId: String) {
    val navigator = LocalNavigator.current
    val accounts by LocalDependencies.current.accounts.accounts.collectAsStateWithLifecycle()
    val existing = accounts.firstOrNull { it.id == accountId }
    ScreenScaffold(title = if (existing != null) "编辑账户" else "添加账户", subtitle = existing?.let { "${it.username} @ ${hostOf(it.instance)}" }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).imePadding().padding(16.dp)) {
            AccountForm(existing, onSaved = { navigator.back() })
        }
    }
}

private fun hostOf(instance: String) = runCatching { GitLabInstance(instance).host }.getOrDefault(instance)

private enum class TrustChoice(val label: String) { SYSTEM("系统信任（推荐）"), CA("导入自建 CA 证书"), PIN("固定服务器证书指纹") }

/** Instance, token and certificate trust; verifies the token before anything is stored. */
@Composable
fun AccountForm(existing: StoredAccount?, onSaved: () -> Unit) {
    val dependencies = LocalDependencies.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val openUrl = rememberOpenUrl()
    var selfManaged by rememberSaveable { mutableStateOf(existing != null && existing.instance != GitLabInstance.GITLAB_COM) }
    var instance by rememberSaveable { mutableStateOf(existing?.instance?.takeIf { it != GitLabInstance.GITLAB_COM } ?: "https://") }
    var token by remember { mutableStateOf("") }
    var showToken by remember { mutableStateOf(false) }
    val initialTrust = existing?.trust ?: TrustPolicy.System
    var trust by rememberSaveable {
        mutableStateOf(when (initialTrust) { is TrustPolicy.CustomCa -> TrustChoice.CA; is TrustPolicy.PinnedLeaf -> TrustChoice.PIN; else -> TrustChoice.SYSTEM })
    }
    var caPems by remember { mutableStateOf((initialTrust as? TrustPolicy.CustomCa)?.certificates.orEmpty()) }
    var pin by rememberSaveable { mutableStateOf((initialTrust as? TrustPolicy.PinnedLeaf)?.sha256?.firstOrNull()?.let(Certificates::displayFingerprint).orEmpty()) }
    var probe by remember { mutableStateOf<List<CertificateSummary>?>(null) }
    var pinConfirmed by rememberSaveable { mutableStateOf(existing != null && initialTrust is TrustPolicy.PinnedLeaf) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var verification by remember { mutableStateOf<Verification?>(null) }

    val instanceUrl = if (selfManaged) instance.trim() else GitLabInstance.GITLAB_COM
    fun policy(): TrustPolicy = when (if (selfManaged) trust else TrustChoice.SYSTEM) {
        TrustChoice.SYSTEM -> TrustPolicy.System
        TrustChoice.CA -> TrustPolicy.CustomCa(caPems.also { require(it.isNotEmpty()) { "请先导入 CA 证书。" } })
        TrustChoice.PIN -> {
            require(pinConfirmed) { "请先核对并确认服务器证书指纹。" }
            TrustPolicy.PinnedLeaf(listOf(Certificates.normalizeFingerprint(pin)))
        }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            problem = try {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { stream -> stream.readNBytesCompat(256 * 1024) } ?: error("无法读取文件。")
                }
                caPems = Certificates.parse(bytes).map(Certificates::toPem)
                verification = null
                null
            } catch (e: Exception) {
                "无法读取证书：${e.message ?: "格式不受支持"}"
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SegmentedButton(!selfManaged, { selfManaged = false; verification = null }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("gitlab.com") }
            SegmentedButton(selfManaged, { selfManaged = true; verification = null }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("自建实例") }
        }
        if (selfManaged) {
            OutlinedTextField(
                instance, { instance = it; verification = null; probe = null; pinConfirmed = false }, Modifier.fillMaxWidth(),
                label = { Text("实例地址") }, placeholder = { Text("https://git.example.com") }, singleLine = true,
                supportingText = { Text("仅支持 HTTPS；可包含子路径。") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, autoCorrectEnabled = false),
            )
        }
        OutlinedTextField(
            token, { token = it; verification = null }, Modifier.fillMaxWidth(),
            label = { Text("个人访问令牌") }, singleLine = true,
            placeholder = { Text(if (existing != null) "留空则保留当前令牌" else "glpat-…") },
            visualTransformation = if (showToken) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
            trailingIcon = {
                IconButton(onClick = { showToken = !showToken }) {
                    Icon(if (showToken) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, if (showToken) "隐藏令牌" else "显示令牌")
                }
            },
            supportingText = { Text("需要 api 范围；只读浏览可用 read_api。令牌加密保存在本机。") },
        )
        TextButton(onClick = {
            runCatching { GitLabInstance(instanceUrl) }.getOrNull()?.let {
                openUrl("${it.canonical}/-/user_settings/personal_access_tokens?name=Gitlabio&scopes=api,read_user")
            } ?: run { problem = "请先填写有效的实例地址。" }
        }) {
            Icon(Icons.AutoMirrored.Filled.OpenInNew, null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("在 GitLab 中创建令牌")
        }

        if (selfManaged) {
            Text("证书信任", style = MaterialTheme.typography.titleSmall)
            TrustChoice.entries.forEach { choice ->
                Row(Modifier.fillMaxWidth().selectable(trust == choice) { trust = choice; verification = null }, verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(trust == choice, null)
                    Spacer(Modifier.width(8.dp))
                    Text(choice.label)
                }
            }
            when (trust) {
                TrustChoice.SYSTEM -> Unit
                TrustChoice.CA -> Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("只信任由所导入 CA 签发的证书；域名校验保持开启。", style = MaterialTheme.typography.bodySmall)
                        caPems.forEach { pem ->
                            runCatching { Certificates.summarize(Certificates.parse(pem.toByteArray()).first()) }.getOrNull()?.let { CertificateCard(it) }
                        }
                        FilledTonalButton(onClick = { picker.launch(arrayOf("application/x-x509-ca-cert", "application/x-pem-file", "application/pkix-cert", "application/octet-stream", "text/plain", "*/*")) }) {
                            Icon(Icons.Outlined.UploadFile, null)
                            Spacer(Modifier.width(8.dp))
                            Text(if (caPems.isEmpty()) "选择 PEM / DER 证书" else "重新选择")
                        }
                    }
                }
                TrustChoice.PIN -> Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("只接受 SHA-256 指纹匹配的服务器证书。证书轮换后需要重新固定。", style = MaterialTheme.typography.bodySmall)
                        FilledTonalButton(enabled = !busy, onClick = {
                            busy = true
                            problem = null
                            scope.launch {
                                try {
                                    val chain = withContext(Dispatchers.IO) { Certificates.probe(GitLabInstance(instanceUrl)) }
                                    probe = chain
                                    pin = Certificates.displayFingerprint(chain.first().sha256)
                                    pinConfirmed = false
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    problem = describeError(e)
                                } finally { busy = false }
                            }
                        }) {
                            Icon(Icons.Outlined.Fingerprint, null)
                            Spacer(Modifier.width(8.dp))
                            Text("读取服务器证书")
                        }
                        probe?.firstOrNull()?.let { CertificateCard(it) }
                        OutlinedTextField(
                            pin, { pin = it; pinConfirmed = false; verification = null }, Modifier.fillMaxWidth(), label = { Text("SHA-256 指纹") },
                            textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = CodeFont), minLines = 2,
                        )
                        Row(Modifier.fillMaxWidth().clickable { pinConfirmed = !pinConfirmed }, verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(pinConfirmed, null)
                            Spacer(Modifier.width(8.dp))
                            Text("我已通过其他渠道（如管理员）核对此指纹", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }

        problem?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

        val result = verification
        if (result == null) {
            Button(
                onClick = {
                    busy = true
                    problem = null
                    scope.launch {
                        try {
                            verification = dependencies.accounts.verify(instanceUrl, token, policy(), existing)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            problem = describeError(e)
                        } finally { busy = false }
                    }
                },
                enabled = !busy && (token.isNotBlank() || existing != null), modifier = Modifier.fillMaxWidth(),
            ) { if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text("验证令牌") }
        } else {
            VerificationCard(result)
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        try {
                            dependencies.accounts.save(result)
                            onSaved()
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            problem = describeError(e)
                        } finally { busy = false }
                    }
                },
                enabled = !busy, modifier = Modifier.fillMaxWidth(),
            ) { Text(if (existing != null) "保存更改" else "保存并登录") }
        }
    }
}

private fun java.io.InputStream.readNBytesCompat(limit: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
        val read = read(buffer)
        if (read < 0) break
        out.write(buffer, 0, read)
        require(out.size() <= limit) { "文件过大，不像是证书。" }
    }
    return out.toByteArray()
}

@Composable
private fun CertificateCard(summary: CertificateSummary) {
    val expired = summary.notAfter < System.currentTimeMillis()
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(summary.subject, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        Text("签发者：${summary.issuer}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            "有效期至 ${Format.dateTime(java.time.Instant.ofEpochMilli(summary.notAfter).toString())}${if (expired) "（已过期）" else ""}",
            style = MaterialTheme.typography.bodySmall, color = if (expired) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(Certificates.displayFingerprint(summary.sha256), style = MaterialTheme.typography.labelSmall.copy(fontFamily = CodeFont))
    }
}

@Composable
private fun VerificationCard(result: Verification) {
    val tone = AppTheme.colors.tone(ToneKey.SUCCESS)
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(result.user.name, size = 40.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(result.user.name, style = MaterialTheme.typography.titleMedium)
                    Text("@${result.user.username} · ${result.instance.host}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Icon(Icons.Filled.Check, "已验证", tint = tone.content)
            }
            val info = result.tokenInfo
            if (info == null) {
                Text("实例未返回令牌范围（可能是较旧的 GitLab 或非个人令牌）；写操作失败时会提示权限不足。", style = MaterialTheme.typography.bodySmall)
            } else {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { info.scopes.forEach { LabelChip(it) } }
                info.expiresAt?.let { Text("令牌到期：$it", style = MaterialTheme.typography.bodySmall) }
                result.capabilities?.warnings?.forEach { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
            }
        }
    }
}

private fun trustLabel(policy: TrustPolicy) = when (policy) {
    TrustPolicy.System -> "系统信任"
    is TrustPolicy.CustomCa -> "自建 CA（${policy.certificates.size} 个）"
    is TrustPolicy.PinnedLeaf -> "固定证书指纹"
}

@Composable
fun SettingsScreen() {
    val dependencies = LocalDependencies.current
    val session = LocalSession.current
    val navigator = LocalNavigator.current
    val snackbar = LocalSnackbar.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val accounts by dependencies.accounts.accounts.collectAsStateWithLifecycle()
    val settings by dependencies.settings.settings.collectAsStateWithLifecycle()
    var removing by remember { mutableStateOf<StoredAccount?>(null) }

    fun setNotifications(enabled: Boolean) {
        TodoNotifications.schedule(context, dependencies.settings.update { it.copy(notifications = enabled) })
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) setNotifications(true) else scope.launch { snackbar.showSnackbar("未授予通知权限，无法发送待办提醒。") }
    }

    ScreenScaffold(title = "我", back = false) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(bottom = 32.dp)) {
            Card(Modifier.fillMaxWidth().padding(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(session.user.name, size = 52.dp)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(session.user.name, style = MaterialTheme.typography.titleLarge)
                        Text("@${session.user.username} · ${session.instanceHost}", style = MaterialTheme.typography.bodyMedium)
                        val account = session.account
                        if (account == null) Text("演示模式 · 合成数据", style = MaterialTheme.typography.bodySmall)
                        else {
                            Text("${trustLabel(account.trust)}${account.tokenExpiresAt?.let { " · 令牌到期 $it" } ?: ""}", style = MaterialTheme.typography.bodySmall)
                            if (account.scopes.isNotEmpty()) FlowRow(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) { account.scopes.forEach { LabelChip(it) } }
                        }
                    }
                }
            }

            SectionTitle("账户")
            accounts.forEach { account ->
                var menu by remember { mutableStateOf(false) }
                ListItem(
                    headlineContent = { Text(account.name) },
                    supportingContent = { Text("@${account.username} · ${hostOf(account.instance)}") },
                    leadingContent = { Avatar(account.name) },
                    trailingContent = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (session.account?.id == account.id) Icon(Icons.Filled.Check, "当前账户", tint = MaterialTheme.colorScheme.primary)
                            Box {
                                IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, "账户操作") }
                                DropdownMenu(menu, { menu = false }) {
                                    DropdownMenuItem(text = { Text("更新令牌或证书信任") }, leadingIcon = { Icon(Icons.Outlined.Shield, null) },
                                        onClick = { menu = false; navigator.open(AccountEditorRoute(account.id)) })
                                    DropdownMenuItem(text = { Text("移除账户") }, leadingIcon = { Icon(Icons.Outlined.Delete, null) },
                                        onClick = { menu = false; removing = account })
                                }
                            }
                        }
                    },
                    modifier = Modifier.clickable(enabled = session.account?.id != account.id) { dependencies.accounts.select(account.id) },
                )
            }
            ListItem(
                headlineContent = { Text("添加账户") }, leadingContent = { Icon(Icons.Outlined.Add, null) },
                modifier = Modifier.clickable { navigator.open(AccountEditorRoute()) },
            )
            if (session.isDemo) ListItem(
                headlineContent = { Text("退出演示模式") }, leadingContent = { Icon(Icons.AutoMirrored.Filled.Logout, null) },
                modifier = Modifier.clickable { dependencies.accounts.exitDemo() },
            ) else ListItem(
                headlineContent = { Text("体验演示模式") }, supportingContent = { Text("使用合成数据，不影响你的账户") },
                leadingContent = { Icon(Icons.Outlined.Science, null) },
                modifier = Modifier.clickable { dependencies.accounts.startDemo() },
            )

            SectionTitle("外观")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                ThemeMode.entries.forEachIndexed { index, mode ->
                    SegmentedButton(settings.theme == mode, { dependencies.settings.update { it.copy(theme = mode) } }, SegmentedButtonDefaults.itemShape(index, ThemeMode.entries.size)) {
                        Text(mode.label)
                    }
                }
            }
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                SwitchRow("动态取色", settings.dynamicColor && Build.VERSION.SDK_INT >= 31,
                    if (Build.VERSION.SDK_INT >= 31) "跟随壁纸配色" else "需要 Android 12 或更高版本", enabled = Build.VERSION.SDK_INT >= 31) { enabled ->
                    dependencies.settings.update { it.copy(dynamicColor = enabled) }
                }
            }

            SectionTitle("通知")
            Column(Modifier.padding(horizontal = 16.dp)) {
                SwitchRow("待办提醒", settings.notifications, "后台定期检查所有账户的新待办（演示模式不会提醒）") { enabled ->
                    if (enabled && !TodoNotifications.canPost(context) && Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
                    else setNotifications(enabled)
                }
                if (settings.notifications) {
                    Text("检查间隔", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 8.dp))
                }
            }
            if (settings.notifications) {
                ChoiceChips(listOf(15 to "15 分钟", 30 to "30 分钟", 60 to "1 小时", 180 to "3 小时"), settings.pollMinutes, { minutes ->
                    TodoNotifications.schedule(context, dependencies.settings.update { it.copy(pollMinutes = minutes) })
                })
            }

            SectionTitle("关于")
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Gitlabio ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(4.dp))
            }
        }
    }
    removing?.let { account ->
        ConfirmDialog("移除 ${account.username}？", "会从本机删除该账户和令牌。GitLab 上的令牌不会被吊销，如不再使用请在 GitLab 中撤销。", "移除",
            onConfirm = { scope.launch { runCatching { dependencies.accounts.remove(account.id) }.onFailure { snackbar.showSnackbar(describeError(it)) } } },
            onDismiss = { removing = null }, destructive = true)
    }
}
