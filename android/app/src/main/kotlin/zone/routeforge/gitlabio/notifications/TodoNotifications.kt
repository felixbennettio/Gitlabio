package zone.routeforge.gitlabio.notifications

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import zone.routeforge.gitlabio.GitlabioApplication
import zone.routeforge.gitlabio.MainActivity
import zone.routeforge.gitlabio.R
import zone.routeforge.gitlabio.core.Todo
import zone.routeforge.gitlabio.data.AppSettings
import java.util.concurrent.TimeUnit

object TodoNotifications {
    const val CHANNEL = "todos"
    private const val WORK = "todo-poll"

    fun createChannel(context: Context) {
        val channel = NotificationChannel(CHANNEL, context.getString(R.string.notification_channel_todos), NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = context.getString(R.string.notification_channel_todos_description) }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun canPost(context: Context) = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun schedule(context: Context, settings: AppSettings) {
        val work = WorkManager.getInstance(context)
        if (!settings.notifications) {
            work.cancelUniqueWork(WORK)
            return
        }
        val request = PeriodicWorkRequestBuilder<TodoPollWorker>(settings.pollMinutes.toLong(), TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        work.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    fun describe(todo: Todo): String = when (todo.actionName) {
        "assigned" -> "指派给你"
        "mentioned", "directly_addressed" -> "提及了你"
        "review_requested" -> "请求你审阅"
        "build_failed" -> "流水线失败"
        "approval_required" -> "需要你批准"
        "unmergeable" -> "无法合并"
        "marked" -> "已加入待办"
        "member_access_requested" -> "申请访问"
        "review_submitted" -> "提交了审阅"
        else -> "新的待办"
    }

    @SuppressLint("MissingPermission")
    fun post(context: Context, accountId: String, accountLabel: String, todos: List<Todo>) {
        if (todos.isEmpty() || !canPost(context)) return
        val manager = NotificationManagerCompat.from(context)
        val intent = Intent(context, MainActivity::class.java)
            .setAction(MainActivity.ACTION_OPEN_INBOX)
            .putExtra(MainActivity.EXTRA_ACCOUNT, accountId)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(context, accountId.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        todos.take(5).forEach { todo ->
            val title = "${todo.author?.name ?: "GitLab"} ${describe(todo)}"
            val text = listOfNotNull(todo.target?.title ?: todo.body.takeIf { it.isNotBlank() }, todo.project?.pathWithNamespace).joinToString(" · ")
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setSubText(accountLabel)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setGroup("todos-$accountId")
                .setCategory(NotificationCompat.CATEGORY_SOCIAL)
                .build()
            manager.notify("todo-$accountId", todo.id.toInt(), notification)
        }
        if (todos.size > 1) {
            val summary = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("${todos.size} 条新的待办")
                .setSubText(accountLabel)
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setGroup("todos-$accountId")
                .setGroupSummary(true)
                .build()
            manager.notify("todo-summary", accountId.hashCode(), summary)
        }
    }
}

/**
 * Checks each account's pending to-dos and notifies about ones not seen before. The first run for an
 * account only records what exists, so enabling notifications does not replay an old backlog.
 */
class TodoPollWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as GitlabioApplication
        if (!app.settings.settings.value.notifications) return Result.success()
        val accounts = try { app.accounts.storedAccounts() } catch (_: Exception) { return Result.success() }
        val seen = applicationContext.getSharedPreferences("todo-notifications", Context.MODE_PRIVATE)
        var failed = false
        for (account in accounts) {
            try {
                val todos = app.accounts.client(account).todos().items
                val key = "seen-${account.id}"
                val known = seen.getStringSet(key, null)
                val fresh = if (known == null) emptyList() else todos.filter { it.id.toString() !in known }
                TodoNotifications.post(applicationContext, account.id, "${account.username} @ ${account.instance.removePrefix("https://")}", fresh)
                seen.edit().putStringSet(key, todos.map { it.id.toString() }.toSet()).apply()
            } catch (_: Exception) {
                failed = true
            }
        }
        return if (failed && runAttemptCount < 2) Result.retry() else Result.success()
    }
}
