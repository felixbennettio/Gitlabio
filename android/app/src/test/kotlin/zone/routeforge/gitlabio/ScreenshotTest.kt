package zone.routeforge.gitlabio

import android.app.Application
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import zone.routeforge.gitlabio.core.DemoGitLabApi
import zone.routeforge.gitlabio.data.AccountRepository
import zone.routeforge.gitlabio.data.Session
import zone.routeforge.gitlabio.data.SettingsRepository
import zone.routeforge.gitlabio.ui.AppDependencies
import zone.routeforge.gitlabio.ui.CommitRoute
import zone.routeforge.gitlabio.ui.FileRoute
import zone.routeforge.gitlabio.ui.HomeRoute
import zone.routeforge.gitlabio.ui.InboxRoute
import zone.routeforge.gitlabio.ui.IssueRoute
import zone.routeforge.gitlabio.ui.JobRoute
import zone.routeforge.gitlabio.ui.LocalDependencies
import zone.routeforge.gitlabio.ui.MainShell
import zone.routeforge.gitlabio.ui.MergeRequestRoute
import zone.routeforge.gitlabio.ui.MergeRequestsRoute
import zone.routeforge.gitlabio.ui.PipelineRoute
import zone.routeforge.gitlabio.ui.PipelinesRoute
import zone.routeforge.gitlabio.ui.ProjectRoute
import zone.routeforge.gitlabio.ui.ProjectsRoute
import zone.routeforge.gitlabio.ui.SettingsRoute
import zone.routeforge.gitlabio.ui.TreeRoute
import zone.routeforge.gitlabio.ui.screens.WelcomeScreen
import zone.routeforge.gitlabio.ui.state.LocalAutoRefresh
import zone.routeforge.gitlabio.ui.state.LocalNow
import zone.routeforge.gitlabio.ui.theme.GitlabioTheme
import java.time.Instant

private const val PHONE = "w411dp-h891dp-xxhdpi"
private const val TABLET = "w1280dp-h800dp-land-xhdpi"

/**
 * Renders the main screens with the demo data set and records PNGs under
 * build/outputs/roborazzi for review in CI artifacts. Times are fixed so output is stable.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = PHONE)
class ScreenshotTest {
    @get:Rule val compose = createComposeRule()
    private val now = Instant.parse("2026-10-28T12:00:00Z")

    private fun show(dark: Boolean = false, content: @Composable () -> Unit) {
        val app = RuntimeEnvironment.getApplication()
        val dependencies = AppDependencies(AccountRepository(app), SettingsRepository(app))
        compose.setContent {
            GitlabioTheme(dark = dark, dynamicColor = false) {
                CompositionLocalProvider(LocalDependencies provides dependencies, LocalNow provides now, LocalAutoRefresh provides false) {
                    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { content() }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        compose.onRoot().captureRoboImage("build/outputs/roborazzi/$name.png")
    }

    private fun screen(name: String, route: Any, dark: Boolean = false) {
        val demo = DemoGitLabApi(now)
        val session = Session("demo:screenshot", demo, null, demo.me)
        show(dark) { MainShell(session, start = route) }
        capture(name)
    }

    @Test fun welcome() {
        show { WelcomeScreen() }
        capture("01_welcome")
    }

    @Test fun home() = screen("02_home", HomeRoute)

    @Test fun homeDark() = screen("03_home_dark", HomeRoute, dark = true)

    @Test fun projects() = screen("04_projects", ProjectsRoute)

    @Test fun project() = screen("05_project", ProjectRoute(101))

    @Test fun tree() = screen("06_tree", TreeRoute(101, "main", "android"))

    @Test fun file() = screen("07_file", FileRoute(101, "main", "android/core/src/main/kotlin/GitLabClient.kt"))

    @Test fun fileDark() = screen("08_file_dark", FileRoute(101, "main", "android/core/src/main/kotlin/GitLabClient.kt"), dark = true)

    @Test fun mergeRequests() = screen("09_merge_requests", MergeRequestsRoute(101))

    @Test fun mergeRequest() = screen("10_merge_request", MergeRequestRoute(101, 41))

    @Test fun mergeRequestDiscussion() {
        screen("11_merge_request_discussion", MergeRequestRoute(101, 42))
        compose.onNodeWithText("讨论 3").performClick()
        capture("11_merge_request_discussion")
    }

    @Test fun mergeRequestDiff() {
        screen("12_merge_request_diff", MergeRequestRoute(101, 42))
        compose.onNodeWithText("变更 3").performClick()
        capture("12_merge_request_diff")
    }

    @Test fun issue() = screen("13_issue", IssueRoute(101, 57))

    @Test fun pipelines() = screen("14_pipelines", PipelinesRoute(101))

    @Test fun pipeline() = screen("15_pipeline", PipelineRoute(101, 9001))

    @Test fun jobLog() = screen("16_job_log", JobRoute(101, 89992))

    @Test fun commit() = screen("17_commit", CommitRoute(101, DemoGitLabApi.sha("101-0-feat(android): adaptive navigation with NavigationSuiteScaffold")))

    @Test fun inbox() = screen("18_inbox", InboxRoute)

    @Test fun settings() = screen("19_settings", SettingsRoute)

    @Test @Config(qualifiers = TABLET)
    fun tabletHome() = screen("20_tablet_home", HomeRoute)

    @Test @Config(qualifiers = TABLET)
    fun tabletMergeRequest() = screen("21_tablet_merge_request", MergeRequestRoute(101, 41), dark = true)
}
