package io.github.hkrb7p794w.gym

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.github.hkrb7p794w.gym.core.AppData
import io.github.hkrb7p794w.gym.core.Backup
import io.github.hkrb7p794w.gym.core.Reminders
import java.io.File
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Erinnerungen an Mahlzeiten und „Tag auswerten“: immer nur die nächste Mitteilung ist als Alarm geplant. Beim Auslösen
 * liest der Empfänger den aktuellen Stand – ist die Mahlzeit schon eingetragen, bleibt die Mitteilung aus – und plant
 * die nächste. Ungenaue Alarme (`setAndAllowWhileIdle`) genügen und brauchen keine Sonderberechtigung.
 */
object ReminderScheduler {
    private const val CHANNEL = "reminders"
    private const val EXTRA_TITLE = "title"
    private const val EXTRA_BODY = "body"
    private const val EXTRA_CATEGORY = "category"
    private const val EXTRA_AT = "at"

    fun load(context: Context): AppData? {
        val file = File(context.filesDir, "gym.json")
        return if (file.exists()) Backup.decode(file.readText()) else null
    }

    fun schedule(context: Context, data: AppData) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context, null)
        alarms.cancel(pending)
        if (!data.reminders.anyEnabled) return
        val note = Reminders.upcoming(data.reminders, LocalDateTime.now(), data.meals).firstOrNull() ?: return
        val millis = note.at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra(EXTRA_TITLE, note.title)
            .putExtra(EXTRA_BODY, note.body)
            .putExtra(EXTRA_CATEGORY, note.category?.name)
            .putExtra(EXTRA_AT, note.at.toString())
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, pendingIntent(context, intent))
    }

    private fun pendingIntent(context: Context, intent: Intent?): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        intent ?: Intent(context, ReminderReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun notify(context: Context, intent: Intent) {
        if (!canNotify(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(NotificationChannel(CHANNEL, "Erinnerungen", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(
            context, 1, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE) ?: "IronLudi")
            .setContentText(intent.getStringExtra(EXTRA_BODY))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(EXTRA_BODY)))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify((intent.getStringExtra(EXTRA_CATEGORY) ?: "review").hashCode(), notification)
        } catch (_: SecurityException) {
            // Berechtigung inzwischen entzogen: still auslassen.
        }
    }

    /** Beim Auslösen: noch nicht eingetragen? Dann melden. In jedem Fall die nächste Erinnerung planen. */
    fun fire(context: Context, intent: Intent) {
        val data = load(context) ?: return
        val category = intent.getStringExtra(EXTRA_CATEGORY)
        val at = intent.getStringExtra(EXTRA_AT)?.let { runCatching { LocalDateTime.parse(it) }.getOrNull() }
        val day = (at ?: LocalDateTime.now()).toLocalDate().toString()
        val logged = category != null && data.meals.any { it.day == day && it.category.name == category }
        if (!logged) notify(context, intent)
        schedule(context, data)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.fire(context, intent)
    }
}

/** Nach dem Neustart des Handys und nach App-Updates sind Alarme weg: neu planen. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.load(context)?.let { ReminderScheduler.schedule(context, it) }
    }
}
