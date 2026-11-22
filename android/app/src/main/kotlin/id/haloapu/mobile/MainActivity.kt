package id.haloapu.mobile

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val WORKER_CHANNEL = "id.haloapu.mobile/background_worker"
    }

    private var workerChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WORKER_CHANNEL,
        )
        workerChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "configureWorker" -> {
                    val authToken = call.argument<String>("authToken")?.trim().orEmpty()
                    val baseUrl = call.argument<String>("baseUrl")?.trim().orEmpty()
                    val releaseChannel =
                        call.argument<String>("releaseChannel")?.trim().orEmpty()
                    val seenIds = call.argument<List<String>>("seenIds") ?: emptyList()
                    val baselineSet = call.argument<Boolean>("baselineSet")

                    if (authToken.isEmpty() || baseUrl.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    SecureWorkerStore.saveConfig(
                        context = this,
                        authToken = authToken,
                        baseUrl = baseUrl,
                        releaseChannel = releaseChannel,
                        seenIds = seenIds,
                        baselineSet = baselineSet,
                    )
                    HaloApuNotificationWorker.schedulePeriodicWork(this)
                    HaloApuNotificationWorker.scheduleQuickCheck(this)
                    result.success(true)
                }

                "scheduleQuickCheck" -> {
                    val hasToken = !SecureWorkerStore.getAuthToken(this).isNullOrBlank()
                    if (hasToken) {
                        HaloApuNotificationWorker.scheduleQuickCheck(this)
                    }
                    result.success(hasToken)
                }

                "markNotificationSeen" -> {
                    val id = call.argument<String>("id")?.trim().orEmpty()
                    if (id.isNotEmpty()) {
                        SecureWorkerStore.markNotificationIdSeen(this, id)
                    }
                    result.success(true)
                }

                "getSeenNotificationIds" -> {
                    result.success(SecureWorkerStore.getSeenNotificationIds(this))
                }

                "clearWorker" -> {
                    SecureWorkerStore.clearAuth(this)
                    HaloApuNotificationWorker.cancelAllWork(this)
                    result.success(true)
                }

                "consumeLaunchPayload" -> {
                    val payload =
                        intent?.getStringExtra(HaloApuNotificationWorker.EXTRA_PAYLOAD)
                    if (!payload.isNullOrBlank()) {
                        intent?.removeExtra(HaloApuNotificationWorker.EXTRA_PAYLOAD)
                    }
                    result.success(payload)
                }

                "openBatteryOptimizationSettings" -> {
                    openBatterySettings()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = intent.getStringExtra(HaloApuNotificationWorker.EXTRA_PAYLOAD)
        if (!payload.isNullOrBlank()) {
            intent.removeExtra(HaloApuNotificationWorker.EXTRA_PAYLOAD)
            workerChannel?.invokeMethod("onNotificationTapped", payload)
        }
    }

    private fun openBatterySettings() {
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", packageName, null),
                    ),
                )
            } catch (_: Exception) {
                // Abaikan jika perangkat tidak memiliki aktivitas pengaturan ini
            }
        }
    }
}
