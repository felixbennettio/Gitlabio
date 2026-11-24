package zone.routeforge.gitlabio

import android.app.Application
import zone.routeforge.gitlabio.data.AccountRepository
import zone.routeforge.gitlabio.data.SettingsRepository
import zone.routeforge.gitlabio.notifications.TodoNotifications

class GitlabioApplication : Application() {
    lateinit var accounts: AccountRepository
        private set
    lateinit var settings: SettingsRepository
        private set

    override fun onCreate() {
        super.onCreate()
        accounts = AccountRepository(this)
        settings = SettingsRepository(this)
        TodoNotifications.createChannel(this)
        TodoNotifications.schedule(this, settings.settings.value)
    }
}
