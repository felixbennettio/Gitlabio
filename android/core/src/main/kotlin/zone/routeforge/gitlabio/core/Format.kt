package zone.routeforge.gitlabio.core

import java.time.Duration
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.util.Locale

/** Chinese, compact formatting for timestamps, durations and sizes shown in lists. */
object Format {
    fun parse(iso: String?): Instant? = iso?.let {
        try { OffsetDateTime.parse(it).toInstant() } catch (_: DateTimeParseException) { null }
    }

    fun relative(iso: String?, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        val time = parse(iso) ?: return ""
        val seconds = Duration.between(time, now).seconds
        return when {
            seconds < -60 -> date(time, now, zone)
            seconds < 60 -> "刚刚"
            seconds < 3600 -> "${seconds / 60} 分钟前"
            seconds < 86_400 -> "${seconds / 3600} 小时前"
            seconds < 2 * 86_400 -> "昨天"
            seconds < 7 * 86_400 -> "${seconds / 86_400} 天前"
            else -> date(time, now, zone)
        }
    }

    fun date(time: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        val local = time.atZone(zone)
        return if (local.year == now.atZone(zone).year) "${local.monthValue}月${local.dayOfMonth}日"
        else "${local.year}年${local.monthValue}月${local.dayOfMonth}日"
    }

    fun dateTime(iso: String?, zone: ZoneId = ZoneId.systemDefault()): String {
        val local = parse(iso)?.atZone(zone) ?: return ""
        return String.format(Locale.ROOT, "%d-%02d-%02d %02d:%02d", local.year, local.monthValue, local.dayOfMonth, local.hour, local.minute)
    }

    fun duration(seconds: Double?): String {
        val total = seconds?.toLong() ?: return ""
        val hours = total / 3600
        val minutes = total % 3600 / 60
        val rest = total % 60
        return when {
            hours > 0 -> "$hours 小时 $minutes 分"
            minutes > 0 -> "$minutes 分 $rest 秒"
            else -> "$rest 秒"
        }
    }

    fun bytes(value: Long): String {
        if (value < 1024) return "$value B"
        val units = listOf("KB", "MB", "GB", "TB")
        var size = value.toDouble() / 1024
        var unit = 0
        while (size >= 1024 && unit < units.lastIndex) { size /= 1024; unit++ }
        return String.format(Locale.ROOT, if (size >= 100) "%.0f %s" else "%.1f %s", size, units[unit])
    }

    fun count(value: Long): String = when {
        value >= 10_000 -> String.format(Locale.ROOT, "%.1f 万", value / 10_000.0)
        else -> value.toString()
    }
}
