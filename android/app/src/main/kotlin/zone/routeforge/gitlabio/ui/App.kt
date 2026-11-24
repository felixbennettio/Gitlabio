package zone.routeforge.gitlabio.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import kotlinx.coroutines.flow.MutableStateFlow
import zone.routeforge.gitlabio.R
import zone.routeforge.gitlabio.data.AccountRepository
import zone.routeforge.gitlabio.data.Session
import zone.routeforge.gitlabio.data.SettingsRepository
import zone.routeforge.gitlabio.data.ThemeMode
import zone.routeforge.gitlabio.ui.screens.AccountEditorScreen
import zone.routeforge.gitlabio.ui.screens.BasketScreen
import zone.routeforge.gitlabio.ui.screens.BranchesScreen
import zone.routeforge.gitlabio.ui.screens.CommitScreen
import zone.routeforge.gitlabio.ui.screens.CommitsScreen
import zone.routeforge.gitlabio.ui.screens.EditFileScreen
import zone.routeforge.gitlabio.ui.screens.FileScreen
import zone.routeforge.gitlabio.ui.screens.HomeScreen
import zone.routeforge.gitlabio.ui.screens.InboxScreen
import zone.routeforge.gitlabio.ui.screens.IssueEditorScreen
import zone.routeforge.gitlabio.ui.screens.IssueScreen
import zone.routeforge.gitlabio.ui.screens.IssuesScreen
import zone.routeforge.gitlabio.ui.screens.JobScreen
import zone.routeforge.gitlabio.ui.screens.MergeRequestScreen
import zone.routeforge.gitlabio.ui.screens.MergeRequestsScreen
import zone.routeforge.gitlabio.ui.screens.NewMergeRequestScreen
import zone.routeforge.gitlabio.ui.screens.PipelineScreen
import zone.routeforge.gitlabio.ui.screens.PipelinesScreen
import zone.routeforge.gitlabio.ui.screens.ProjectScreen
import zone.routeforge.gitlabio.ui.screens.ProjectsScreen
import zone.routeforge.gitlabio.ui.screens.RunPipelineScreen
import zone.routeforge.gitlabio.ui.screens.SettingsScreen
import zone.routeforge.gitlabio.ui.screens.TreeScreen
import zone.routeforge.gitlabio.ui.screens.WelcomeScreen
import zone.routeforge.gitlabio.ui.state.LocalSession
import zone.routeforge.gitlabio.ui.state.LocalSnackbar
import zone.routeforge.gitlabio.ui.state.rememberResource
import zone.routeforge.gitlabio.ui.theme.GitlabioTheme

/** Everything the UI needs from outside Compose; tests pass their own. */
class AppDependencies(val accounts: AccountRepository, val settings: SettingsRepository)

val LocalDependencies = androidx.compose.runtime.staticCompositionLocalOf<AppDependencies> { error("No dependencies") }

@Composable
fun GitlabioRoot(accounts: AccountRepository, settings: SettingsRepository, pendingInbox: MutableStateFlow<String?>) {
    val appSettings by settings.settings.collectAsStateWithLifecycle()
    val dark = when (appSettings.theme) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    GitlabioTheme(dark = dark, dynamicColor = appSettings.dynamicColor) {
        val ready by accounts.ready.collectAsStateWithLifecycle()
        val session by accounts.session.collectAsStateWithLifecycle()
        val inbox by pendingInbox.collectAsStateWithLifecycle()
        val dependencies = remember(accounts, settings) { AppDependencies(accounts, settings) }
        LaunchedEffect(inbox, ready) {
            val target = inbox ?: return@LaunchedEffect
            if (ready && target.isNotEmpty() && session?.account?.id != target) accounts.select(target)
        }
        CompositionLocalProvider(LocalDependencies provides dependencies) {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                val current = session
                when {
                    !ready -> Splash()
                    current == null -> WelcomeScreen()
                    else -> key(current.id) {
                        MainShell(current, openInbox = inbox != null, onInboxOpened = { pendingInbox.value = null })
                    }
                }
            }
        }
    }
}

@Composable
private fun Splash() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Image(painterResource(R.drawable.ic_gitlabio), contentDescription = null, modifier = Modifier.size(72.dp))
    }
}

enum class TopLevel(val route: Any, val label: String, val icon: ImageVector, val selectedIcon: ImageVector) {
    HOME(HomeRoute, "首页", Icons.Outlined.Home, Icons.Filled.Home),
    PROJECTS(ProjectsRoute, "项目", Icons.Outlined.Folder, Icons.Filled.Folder),
    INBOX(InboxRoute, "待办", Icons.Outlined.Inbox, Icons.Filled.Inbox),
    ME(SettingsRoute, "我", Icons.Outlined.AccountCircle, Icons.Filled.AccountCircle),
}

@Composable
fun MainShell(session: Session, openInbox: Boolean = false, onInboxOpened: () -> Unit = {}, start: Any = HomeRoute) {
    val navController = rememberNavController()
    val snackbar = remember { SnackbarHostState() }
    val navigator = remember(navController) { ControllerNavigator(navController) }
    var lastTop by rememberSaveable { mutableStateOf((TopLevel.entries.firstOrNull { it.route == start } ?: TopLevel.HOME).name) }
    val entry by navController.currentBackStackEntryAsState()
    val currentTop = TopLevel.entries.firstOrNull { top -> entry?.destination?.hierarchy?.any { it.hasRoute(top.route::class) } == true }
    LaunchedEffect(currentTop) { currentTop?.let { lastTop = it.name } }
    // Detail screens keep the tab they were opened from highlighted.
    val selectedTop = currentTop?.name ?: lastTop

    CompositionLocalProvider(LocalSession provides session, LocalSnackbar provides snackbar, LocalNavigator provides navigator) {
        val todos = rememberResource("todo-count") { todos() }
        LaunchedEffect(openInbox) {
            if (openInbox) {
                navigator.top(TopLevel.INBOX)
                onInboxOpened()
            }
        }
        NavigationSuiteScaffold(
            navigationSuiteItems = {
                TopLevel.entries.forEach { top ->
                    val selected = selectedTop == top.name
                    item(
                        selected = selected,
                        onClick = { navigator.top(top) },
                        icon = {
                            val count = if (top == TopLevel.INBOX) todos.value?.items?.size ?: 0 else 0
                            BadgedBox(badge = {
                                if (count > 0) Badge { Text(if (todos.value?.next != null) "50+" else "$count") }
                            }) { Icon(if (selected) top.selectedIcon else top.icon, contentDescription = null) }
                        },
                        label = { Text(top.label) },
                    )
                }
            },
        ) {
            Box(Modifier.fillMaxSize()) {
                NavHost(navController, startDestination = start) {
                    composable<HomeRoute> { HomeScreen() }
                    composable<ProjectsRoute> { ProjectsScreen() }
                    composable<InboxRoute> { InboxScreen() }
                    composable<SettingsRoute> { SettingsScreen() }
                    composable<AccountEditorRoute> { AccountEditorScreen(it.toRoute<AccountEditorRoute>().accountId) }
                    composable<ProjectRoute> { ProjectScreen(it.toRoute<ProjectRoute>().project) }
                    composable<TreeRoute> { TreeScreen(it.toRoute()) }
                    composable<FileRoute> { FileScreen(it.toRoute()) }
                    composable<EditFileRoute> { EditFileScreen(it.toRoute()) }
                    composable<BasketRoute> { BasketScreen(it.toRoute()) }
                    composable<BranchesRoute> { BranchesScreen(it.toRoute<BranchesRoute>().project) }
                    composable<CommitsRoute> { CommitsScreen(it.toRoute()) }
                    composable<CommitRoute> { CommitScreen(it.toRoute()) }
                    composable<MergeRequestsRoute> { MergeRequestsScreen(it.toRoute()) }
                    composable<MergeRequestRoute> { MergeRequestScreen(it.toRoute()) }
                    composable<NewMergeRequestRoute> { NewMergeRequestScreen(it.toRoute()) }
                    composable<IssuesRoute> { IssuesScreen(it.toRoute()) }
                    composable<IssueRoute> { IssueScreen(it.toRoute()) }
                    composable<IssueEditorRoute> { IssueEditorScreen(it.toRoute()) }
                    composable<PipelinesRoute> { PipelinesScreen(it.toRoute<PipelinesRoute>().project) }
                    composable<PipelineRoute> { PipelineScreen(it.toRoute()) }
                    composable<JobRoute> { JobScreen(it.toRoute()) }
                    composable<RunPipelineRoute> { RunPipelineScreen(it.toRoute()) }
                }
                SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 8.dp))
            }
        }
    }
}

private class ControllerNavigator(private val controller: NavHostController) : Navigator {
    override fun open(route: Any) = controller.navigate(route) { launchSingleTop = true }

    override fun replace(route: Any) {
        val current = controller.currentDestination?.id
        controller.navigate(route) {
            if (current != null) popUpTo(current) { inclusive = true }
        }
    }

    override fun back() {
        controller.popBackStack()
    }

    fun top(top: TopLevel) {
        controller.navigate(top.route) {
            popUpTo(controller.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
}
