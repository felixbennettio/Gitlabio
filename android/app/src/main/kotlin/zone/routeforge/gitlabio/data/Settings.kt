package zone.routeforge.gitlabio.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class ThemeMode(val label: String) { SYSTEM("跟随系统"), LIGHT("浅色"), DARK("深色") }

data class AppSettings(
    val theme: ThemeMode = ThemeMode.SYSTEM,
    val dynamicColor: Boolean = false,
    val notifications: Boolean = false,
    val pollMinutes: Int = 15,
)

class SettingsRepository(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val _settings = MutableStateFlow(read())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    private fun read() = AppSettings(
        theme = ThemeMode.entries.firstOrNull { it.name == prefs.getString("theme", null) } ?: ThemeMode.SYSTEM,
        dynamicColor = prefs.getBoolean("dynamicColor", false),
        notifications = prefs.getBoolean("notifications", false),
        pollMinutes = prefs.getInt("pollMinutes", 15).coerceIn(15, 24 * 60),
    )

    fun update(transform: (AppSettings) -> AppSettings): AppSettings {
        val next = transform(_settings.value)
        prefs.edit()
            .putString("theme", next.theme.name)
            .putBoolean("dynamicColor", next.dynamicColor)
            .putBoolean("notifications", next.notifications)
            .putInt("pollMinutes", next.pollMinutes)
            .apply()
        _settings.value = next
        return next
    }
}
