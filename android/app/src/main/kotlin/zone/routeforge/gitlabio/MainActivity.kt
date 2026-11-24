package zone.routeforge.gitlabio

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import kotlinx.coroutines.flow.MutableStateFlow
import zone.routeforge.gitlabio.ui.GitlabioRoot

class MainActivity : ComponentActivity() {
    /** Set when a notification asks to show the inbox; consumed by the UI. */
    private val pendingInbox = MutableStateFlow<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handle(intent)
        val app = application as GitlabioApplication
        setContent { GitlabioRoot(app.accounts, app.settings, pendingInbox) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent?.action == ACTION_OPEN_INBOX) pendingInbox.value = intent.getStringExtra(EXTRA_ACCOUNT) ?: ""
    }

    companion object {
        const val ACTION_OPEN_INBOX = "zone.routeforge.gitlabio.OPEN_INBOX"
        const val EXTRA_ACCOUNT = "account"
    }
}
