package id.haloapu.mobile

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Fallback background notification worker when FCM is unavailable or delayed.
 * Uses AndroidKeyStore-encrypted Bearer token from [SecureWorkerStore] and
 * 3-way notification ID deduplication across FCM, foreground poller, and WorkManager.
 */
class HaloApuNotificationWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {

    companion object {
        const val UNIQUE_PERIODIC_WORK = "haloapu_bg_notif_poll"
        const val UNIQUE_QUICK_WORK = "haloapu_bg_notif_quick"
        const val CHANNEL_ID = "high_importance_channel"
        const val CHANNEL_NAME = "Notifikasi Tiket Halo APU"
        const val CHANNEL_DESC =
            "Channel prioritas tinggi untuk pembaruan tiket dan pesan masuk."
        const val EXTRA_PAYLOAD = "haloapu_notification_payload"
        const val NOTIF_TAG_PREFIX = "haloapu_notif_"

        fun schedulePeriodicWork(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val periodicRequest = PeriodicWorkRequestBuilder<HaloApuNotificationWorker>(
                15,
                TimeUnit.MINUTES,
            )
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
                UNIQUE_PERIODIC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                periodicRequest,
            )
        }

        fun scheduleQuickCheck(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val quickRequest = OneTimeWorkRequestBuilder<HaloApuNotificationWorker>()
                .setInitialDelay(3, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                UNIQUE_QUICK_WORK,
                ExistingWorkPolicy.REPLACE,
                quickRequest,
            )
        }

        fun cancelAllWork(context: Context) {
            val wm = WorkManager.getInstance(context.applicationContext)
            wm.cancelUniqueWork(UNIQUE_PERIODIC_WORK)
            wm.cancelUniqueWork(UNIQUE_QUICK_WORK)
        }

        fun isAllowedBaseUrl(baseUrl: String, isDebuggable: Boolean): Boolean {
            return try {
                val parsed = Uri.parse(baseUrl.trim())
                val scheme = parsed.scheme?.lowercase() ?: return false
                val host = parsed.host
                if (host.isNullOrBlank()) return false
                when (scheme) {
                    "https" -> true
                    "http" -> isDebuggable
                    else -> false
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    override fun doWork(): Result {
        if (isAppInForeground(applicationContext)) {
            return Result.success()
        }

        val authToken = SecureWorkerStore.getAuthToken(applicationContext)
        val baseUrl = SecureWorkerStore.getBaseUrl(applicationContext)
        val isDebuggable =
            (applicationContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        if (authToken.isNullOrBlank() ||
            baseUrl.isNullOrBlank() ||
            !isAllowedBaseUrl(baseUrl, isDebuggable)
        ) {
            cancelAllWork(applicationContext)
            return Result.success()
        }

        val releaseChannel = SecureWorkerStore.getReleaseChannel(applicationContext)
        val cleanBase = baseUrl.trimEnd('/')
        val responseBody = fetchNotifications(cleanBase, authToken) ?: return Result.success()

        val root = try {
            JSONObject(responseBody)
        } catch (_: Exception) {
            return Result.success()
        }

        val dataArray = root.optJSONArray("data") ?: JSONArray()
        if (dataArray.length() == 0) {
            if (!SecureWorkerStore.isBaselineSet(applicationContext)) {
                SecureWorkerStore.setBaselineSet(applicationContext, true)
            }
            return Result.success()
        }

        // Baseline run: record existing notifications without spamming pop-ups.
        if (!SecureWorkerStore.isBaselineSet(applicationContext)) {
            for (i in 0 until dataArray.length()) {
                val item = dataArray.optJSONObject(i) ?: continue
                val id = item.optString("id", "").trim()
                if (id.isNotEmpty()) {
                    SecureWorkerStore.markNotificationIdSeen(applicationContext, id)
                }
            }
            SecureWorkerStore.setBaselineSet(applicationContext, true)
            return Result.success()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                applicationContext,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return Result.success()
        }

        val notificationManager =
            applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return Result.success()

        ensureNotificationChannel(notificationManager)

        // Iterate oldest-to-newest so newest unread item appears on top.
        for (i in (dataArray.length() - 1) downTo 0) {
            val item = dataArray.optJSONObject(i) ?: continue
            val isRead = item.optBoolean("isRead", false) || item.optBoolean("is_read", false)
            if (isRead) continue

            val id = item.optString("id", "").trim()
            if (id.isEmpty() || SecureWorkerStore.isNotificationIdSeen(applicationContext, id)) {
                continue
            }

            val nestedData = item.optJSONObject("data")
            val nestedMeta = item.optJSONObject("meta")

            val type = pickNonEmpty(item, nestedData, nestedMeta, "type")
            val channel = pickNonEmpty(item, nestedData, nestedMeta, "channel")
            if (type == "app_update" &&
                channel.isNotEmpty() &&
                !channel.equals(releaseChannel, ignoreCase = true)
            ) {
                SecureWorkerStore.markNotificationIdSeen(applicationContext, id)
                continue
            }

            val title = pickNonEmpty(item, nestedData, nestedMeta, "title").ifEmpty {
                if (type == "app_update") "Pembaruan Aplikasi Tersedia" else "Pembaruan Tiket"
            }
            val body = pickNonEmpty(item, nestedData, nestedMeta, "body", "message").ifEmpty {
                if (type == "app_update") {
                    "Versi baru Halo APU tersedia untuk diunduh."
                } else {
                    "Ada perubahan status pada tiket Anda"
                }
            }

            val tag = "$NOTIF_TAG_PREFIX$id"
            if (isAlreadyDisplayedInStatusBar(notificationManager, tag, title, body)) {
                SecureWorkerStore.markNotificationIdSeen(applicationContext, id)
                continue
            }

            SecureWorkerStore.markNotificationIdSeen(applicationContext, id)

            val ticketId = pickNonEmpty(item, nestedData, nestedMeta, "ticket_id", "ticketId")
            val versionName =
                pickNonEmpty(item, nestedData, nestedMeta, "version_name", "versionName")
            val buildNumber =
                pickNonEmpty(item, nestedData, nestedMeta, "build_number", "buildNumber")

            val payloadJson = JSONObject().apply {
                put("id", id)
                if (type.isNotEmpty()) put("type", type)
                if (ticketId.isNotEmpty()) put("ticket_id", ticketId)
                if (channel.isNotEmpty()) put("channel", channel)
                if (versionName.isNotEmpty()) put("version_name", versionName)
                if (buildNumber.isNotEmpty()) put("build_number", buildNumber)
                put("title", title)
                put("body", body)
            }.toString()

            showLocalNotification(
                notificationManager = notificationManager,
                tag = tag,
                notifId = id.hashCode(),
                title = title,
                body = body,
                payloadJson = payloadJson,
            )
        }

        return Result.success()
    }

    private fun fetchNotifications(cleanBase: String, authToken: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL("$cleanBase/notifications?page=1&per_page=5")
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8000
                readTimeout = 8000
                // Never forward Bearer Authorization header across unexpected HTTP redirects.
                instanceFollowRedirects = false
                setRequestProperty("Authorization", "Bearer $authToken")
                setRequestProperty("Accept", "application/json")
            }

            val code = conn.responseCode
            if (code == HttpURLConnection.HTTP_UNAUTHORIZED) {
                val cleared =
                    SecureWorkerStore.clearAuthIfTokenMatches(applicationContext, authToken)
                if (cleared || SecureWorkerStore.getAuthToken(applicationContext).isNullOrBlank()) {
                    cancelAllWork(applicationContext)
                }
                return null
            }

            if (code != HttpURLConnection.HTTP_OK) {
                return null
            }

            BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { reader ->
                reader.readText()
            }
        } catch (_: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun ensureNotificationChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) return

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = CHANNEL_DESC
            enableVibration(true)
            setShowBadge(true)
            setSound(soundUri, audioAttributes)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun isAlreadyDisplayedInStatusBar(
        notificationManager: NotificationManager,
        tag: String,
        title: String,
        body: String,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            val active = notificationManager.activeNotifications ?: return false
            active.any { sbn ->
                if (sbn.tag == tag) return@any true
                val extras = sbn.notification?.extras ?: return@any false
                val activeTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                val activeText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                activeTitle == title && activeText == body
            }
        } catch (_: Exception) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun showLocalNotification(
        notificationManager: NotificationManager,
        tag: String,
        notifId: Int,
        title: String,
        body: String,
        payloadJson: String,
    ) {
        val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_PAYLOAD, payloadJson)
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            notifId,
            launchIntent,
            pendingIntentFlags,
        )

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(tag, notifId, notification)
    }

    private fun isAppInForeground(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return false
            val processes = am.runningAppProcesses ?: return false
            val pkg = context.packageName
            processes.any { process ->
                process.processName == pkg &&
                    process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun pickNonEmpty(
        primary: JSONObject,
        secondary: JSONObject?,
        tertiary: JSONObject?,
        vararg keys: String,
    ): String {
        val sources = listOfNotNull(primary, secondary, tertiary)
        for (key in keys) {
            for (src in sources) {
                if (!src.has(key) || src.isNull(key)) continue
                val value = src.optString(key, "").trim()
                if (value.isNotEmpty() && value != "null") {
                    return value
                }
            }
        }
        return ""
    }
}
