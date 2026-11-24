package zone.routeforge.gitlabio.data

import android.content.Context
import androidx.compose.runtime.mutableStateMapOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import zone.routeforge.gitlabio.core.CommitAction
import zone.routeforge.gitlabio.core.DemoGitLabApi
import zone.routeforge.gitlabio.core.GitLabApi
import zone.routeforge.gitlabio.core.GitLabClient
import zone.routeforge.gitlabio.core.GitLabInstance
import zone.routeforge.gitlabio.core.TokenCapabilities
import zone.routeforge.gitlabio.core.TokenInfo
import zone.routeforge.gitlabio.core.TrustPolicy
import zone.routeforge.gitlabio.core.User
import java.util.UUID

/** One signed-in account (or the demo) with its API and per-session state. Recreated on every switch. */
class Session(
    val id: String,
    val api: GitLabApi,
    val account: StoredAccount?,
    val user: User,
) {
    val isDemo get() = account == null
    val instanceHost: String get() = account?.let { runCatching { GitLabInstance(it.instance).host }.getOrNull() } ?: "demo.gitlabio"
    val webBase: String get() = account?.instance ?: "https://gitlab.example.test"
    val capabilities get() = TokenCapabilities(account?.scopes?.takeIf { it.isNotEmpty() } ?: listOf("api"))

    private val _version = MutableStateFlow(0L)
    /** Bumped after every successful write so open screens reload quietly. */
    val version: StateFlow<Long> = _version.asStateFlow()
    fun invalidate() = _version.update { it + 1 }

    val basket = ChangeBasket()
}

/** Result of checking a token before it is saved. */
data class Verification(
    val instance: GitLabInstance,
    val token: String,
    val trust: TrustPolicy,
    val user: User,
    val tokenInfo: TokenInfo?,
    val replacesId: String?,
) {
    val capabilities get() = tokenInfo?.let { TokenCapabilities(it.scopes) }
}

class AccountRepository(context: Context, private val vault: CredentialVault = CredentialVault(context)) {
    private val prefs = context.getSharedPreferences("account-selection", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _accounts = MutableStateFlow<List<StoredAccount>>(emptyList())
    val accounts: StateFlow<List<StoredAccount>> = _accounts.asStateFlow()
    private val _session = MutableStateFlow<Session?>(null)
    val session: StateFlow<Session?> = _session.asStateFlow()
    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        scope.launch {
            try {
                _accounts.value = withContext(Dispatchers.IO) { vault.read() }
            } catch (_: Exception) {
                _error.value = "无法解锁账户存储。请重新添加账户。"
            }
            when {
                prefs.getBoolean(DEMO, false) -> startDemo()
                else -> (_accounts.value.firstOrNull { it.id == prefs.getString(SELECTED, null) } ?: _accounts.value.firstOrNull())?.let { select(it.id) }
            }
            _ready.value = true
        }
    }

    fun client(account: StoredAccount): GitLabClient = GitLabClient(GitLabInstance(account.instance), account.token, account.trust)

    fun select(id: String) {
        val account = _accounts.value.firstOrNull { it.id == id } ?: return
        prefs.edit().putString(SELECTED, id).putBoolean(DEMO, false).apply()
        _session.value = Session(account.id + ":" + UUID.randomUUID(), client(account), account, User(0, account.username, account.name))
    }

    fun startDemo() {
        prefs.edit().putBoolean(DEMO, true).apply()
        val demo = DemoGitLabApi(latencyMillis = 250)
        _session.value = Session("demo:" + UUID.randomUUID(), demo, null, demo.me)
    }

    fun exitDemo() {
        prefs.edit().putBoolean(DEMO, false).apply()
        _session.value = null
        _accounts.value.firstOrNull()?.let { select(it.id) }
    }

    /** Checks the token against the instance without saving anything. */
    suspend fun verify(instanceText: String, tokenText: String, trust: TrustPolicy, replacing: StoredAccount? = null): Verification {
        val instance = GitLabInstance(instanceText)
        val token = tokenText.trim().ifEmpty { replacing?.token.orEmpty() }
        require(token.isNotEmpty()) { "请填写个人访问令牌。" }
        val client = GitLabClient(instance, token, trust)
        val user = client.currentUser()
        val info = client.tokenInfo()
        return Verification(instance, token, trust, user, info, replacing?.id)
    }

    suspend fun save(verification: Verification) {
        val url = verification.instance.canonical
        val existing = _accounts.value.firstOrNull { it.id == verification.replacesId }
            ?: _accounts.value.firstOrNull { it.instance == url && it.username == verification.user.username }
        val account = StoredAccount(
            id = existing?.id ?: UUID.randomUUID().toString(),
            instance = url,
            username = verification.user.username,
            name = verification.user.name,
            token = verification.token,
            trust = verification.trust,
            scopes = verification.tokenInfo?.scopes.orEmpty(),
            tokenExpiresAt = verification.tokenInfo?.expiresAt,
        )
        val updated = _accounts.value.filterNot { it.id == account.id } + account
        withContext(Dispatchers.IO) { vault.write(updated) }
        _accounts.value = updated
        _error.value = null
        select(account.id)
    }

    suspend fun remove(id: String) {
        val updated = _accounts.value.filterNot { it.id == id }
        withContext(Dispatchers.IO) { vault.write(updated) }
        _accounts.value = updated
        if (_session.value?.account?.id == id) {
            prefs.edit().remove(SELECTED).apply()
            _session.value = null
            updated.firstOrNull()?.let { select(it.id) }
        }
    }

    /** Accounts for background work, read straight from the vault. */
    fun storedAccounts(): List<StoredAccount> = vault.read()

    private companion object {
        const val SELECTED = "selected"
        const val DEMO = "demo"
    }
}

enum class ChangeKind { CREATE, UPDATE, DELETE }

data class BasketChange(
    val path: String,
    val kind: ChangeKind,
    val content: String? = null,
    val lastCommitId: String? = null,
)

/** Pending file changes per project and branch, committed together through the Commits API. */
class ChangeBasket {
    private val entries = mutableStateMapOf<String, List<BasketChange>>()
    private fun key(project: Long, ref: String) = "$project@$ref"

    fun changes(project: Long, ref: String): List<BasketChange> = entries[key(project, ref)].orEmpty()

    fun change(project: Long, ref: String, path: String): BasketChange? = changes(project, ref).firstOrNull { it.path == path }

    val total: Int get() = entries.values.sumOf { it.size }

    fun put(project: Long, ref: String, change: BasketChange) {
        val current = changes(project, ref)
        val previous = current.firstOrNull { it.path == change.path }
        val merged = when {
            // Editing or deleting a file that only exists in the basket stays a create, or disappears.
            previous?.kind == ChangeKind.CREATE && change.kind == ChangeKind.UPDATE -> change.copy(kind = ChangeKind.CREATE, lastCommitId = null)
            previous?.kind == ChangeKind.CREATE && change.kind == ChangeKind.DELETE -> null
            else -> change
        }
        val rest = current.filterNot { it.path == change.path }
        entries[key(project, ref)] = if (merged == null) rest else rest + merged
    }

    fun remove(project: Long, ref: String, path: String) {
        entries[key(project, ref)] = changes(project, ref).filterNot { it.path == path }
    }

    fun clear(project: Long, ref: String) { entries.remove(key(project, ref)) }

    fun actions(project: Long, ref: String): List<CommitAction> = changes(project, ref).map { change ->
        when (change.kind) {
            ChangeKind.CREATE -> CommitAction("create", change.path, content = change.content.orEmpty(), encoding = "text")
            ChangeKind.UPDATE -> CommitAction("update", change.path, content = change.content.orEmpty(), encoding = "text", lastCommitId = change.lastCommitId)
            ChangeKind.DELETE -> CommitAction("delete", change.path, lastCommitId = change.lastCommitId)
        }
    }
}
