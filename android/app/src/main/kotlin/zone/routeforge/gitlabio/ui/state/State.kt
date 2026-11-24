package zone.routeforge.gitlabio.ui.state

import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import zone.routeforge.gitlabio.core.GitLabApi
import zone.routeforge.gitlabio.core.Page
import zone.routeforge.gitlabio.core.describeError
import zone.routeforge.gitlabio.data.Session
import java.time.Instant

val LocalSession = staticCompositionLocalOf<Session> { error("No session") }
val LocalSnackbar = staticCompositionLocalOf { SnackbarHostState() }
/** "Now" for relative times; fixed in screenshot tests so output is stable. */
val LocalNow = staticCompositionLocalOf<Instant?> { null }

/** Whether running pipelines and logs poll for updates; off in screenshot tests. */
val LocalAutoRefresh = staticCompositionLocalOf { true }

@Composable
fun now(): Instant = LocalNow.current ?: remember { Instant.now() }

sealed interface Load<out T> {
    data object Loading : Load<Nothing>
    data class Ready<T>(val value: T) : Load<T>
    data class Failed(val message: String) : Load<Nothing>
}

/**
 * One request's result for a screen. Survives configuration changes, reloads quietly whenever the
 * session reports a write, and keeps showing old data if a refresh fails.
 */
class ResourceModel<T>(private val session: Session, private val loader: suspend GitLabApi.() -> T) : ViewModel() {
    var state by mutableStateOf<Load<T>>(Load.Loading)
        private set
    var refreshing by mutableStateOf(false)
        private set
    /** Error from the last refresh while older data is still shown. */
    var staleError by mutableStateOf<String?>(null)
        private set
    private var job: Job? = null
    private var generations = 0

    val value: T? get() = (state as? Load.Ready<T>)?.value

    init {
        reload()
        viewModelScope.launch { session.version.drop(1).collect { reload(quiet = true) } }
    }

    fun reload(quiet: Boolean = false) {
        job?.cancel()
        val hadValue = state is Load.Ready
        if (!hadValue) state = Load.Loading else if (!quiet) refreshing = true
        val generation = ++generations
        job = viewModelScope.launch {
            try {
                state = Load.Ready(session.api.loader())
                staleError = null
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                if (hadValue) staleError = describeError(error) else state = Load.Failed(describeError(error))
            } finally {
                if (generation == generations) refreshing = false
            }
        }
    }

    fun update(value: T) { state = Load.Ready(value) }
}

/** A paged list: first page on load, more pages as the user scrolls. */
class PagedModel<T>(private val session: Session, private val loader: suspend GitLabApi.(Int) -> Page<T>) : ViewModel() {
    var items by mutableStateOf<List<T>>(emptyList())
        private set
    var state by mutableStateOf<Load<Unit>>(Load.Loading)
        private set
    var refreshing by mutableStateOf(false)
        private set
    var loadingMore by mutableStateOf(false)
        private set
    var moreError by mutableStateOf<String?>(null)
        private set
    private var next: Int? = null
    private var job: Job? = null
    private var generations = 0

    val hasMore get() = next != null

    init {
        reload()
        viewModelScope.launch { session.version.drop(1).collect { reload(quiet = true) } }
    }

    fun reload(quiet: Boolean = false) {
        job?.cancel()
        val hadValue = state is Load.Ready
        if (!hadValue) state = Load.Loading else if (!quiet) refreshing = true
        val generation = ++generations
        job = viewModelScope.launch {
            try {
                val page = session.api.loader(1)
                items = page.items
                next = page.next
                moreError = null
                state = Load.Ready(Unit)
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                if (hadValue) moreError = describeError(error) else state = Load.Failed(describeError(error))
            } finally {
                if (generation == generations) { refreshing = false; loadingMore = false }
            }
        }
    }

    fun loadMore() {
        val page = next ?: return
        if (loadingMore || state !is Load.Ready) return
        loadingMore = true
        moreError = null
        val generation = ++generations
        job = viewModelScope.launch {
            try {
                val result = session.api.loader(page)
                items = items + result.items
                next = result.next
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                moreError = describeError(error)
            } finally {
                if (generation == generations) loadingMore = false
            }
        }
    }
}

private fun key(session: Session, kind: String, keys: Array<out Any?>) = kind + ":" + session.id + ":" + keys.joinToString("|")

/** A [ResourceModel] scoped to the current screen and identified by [keys]. */
@Composable
fun <T> rememberResource(vararg keys: Any?, loader: suspend GitLabApi.() -> T): ResourceModel<T> {
    val session = LocalSession.current
    return viewModel(key = key(session, "r", keys)) { ResourceModel(session, loader) }
}

@Composable
fun <T> rememberPaged(vararg keys: Any?, loader: suspend GitLabApi.(Int) -> Page<T>): PagedModel<T> {
    val session = LocalSession.current
    return viewModel(key = key(session, "p", keys)) { PagedModel(session, loader) }
}

/** Runs writes, reports the outcome in the snackbar and tells open screens to refresh. */
class Actions(private val scope: CoroutineScope, private val snackbar: SnackbarHostState, private val session: Session) {
    var busy by mutableStateOf(false)
        private set

    fun <T> run(success: String? = null, onSuccess: (T) -> Unit = {}, onError: (String) -> Unit = {}, block: suspend GitLabApi.() -> T) {
        if (busy) return
        busy = true
        scope.launch {
            try {
                val result = session.api.block()
                session.invalidate()
                busy = false
                onSuccess(result)
                success?.let { launch { snackbar.showSnackbar(it) } }
            } catch (cancel: CancellationException) {
                busy = false
                throw cancel
            } catch (error: Exception) {
                busy = false
                val message = describeError(error)
                onError(message)
                snackbar.showSnackbar(message)
            }
        }
    }
}

@Composable
fun rememberActions(): Actions {
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbar.current
    val session = LocalSession.current
    return remember(session) { Actions(scope, snackbar, session) }
}
