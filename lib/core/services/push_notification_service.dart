import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:halo_apu_mobile/core/config/api_config.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/core/router/app_router.dart';
import 'package:halo_apu_mobile/core/services/app_update_service.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:halo_apu_mobile/data/api/api_client.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationDiagnosticStatus {
  final bool permissionGranted;
  final bool fcmReady;
  final bool isPlaceholderConfig;
  final bool backgroundWorkerActive;
  final bool realtimePollerActive;

  const NotificationDiagnosticStatus({
    required this.permissionGranted,
    required this.fcmReady,
    required this.isPlaceholderConfig,
    required this.backgroundWorkerActive,
    required this.realtimePollerActive,
  });
}

/// Top-level background message handler for Firebase Messaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('FCM Background message received: ${message.messageId}');

  final notifId = message.data['notification_id']?.toString().trim() ??
      message.data['id']?.toString().trim() ??
      message.messageId?.trim();
  if (notifId != null && notifId.isNotEmpty) {
    await PushNotificationService.recordSeenNotificationId(notifId);
  }

  // Hanya tampilkan notifikasi lokal untuk pesan data-only;
  // jika message.notification != null, Android OS sudah merender banner-nya.
  if (message.notification == null &&
      !PushNotificationService.shouldIgnoreAppUpdatePayload(message.data)) {
    final title = message.data['title']?.toString().trim();
    final body =
        (message.data['body'] ?? message.data['message'])?.toString().trim();
    if ((title != null && title.isNotEmpty) ||
        (body != null && body.isNotEmpty)) {
      await PushNotificationService.showNotificationAlert(
        title: (title != null && title.isNotEmpty) ? title : 'Halo APU',
        body: (body != null && body.isNotEmpty)
            ? body
            : 'Ada pembaruan baru.',
        data: message.data,
        notificationKey: notifId,
      );
    }
  }
}

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    // Harus sama dengan meta-data default_notification_channel_id di AndroidManifest,
    // kalau tidak push background memakai channel fallback (importance default).
    'high_importance_channel',
    'Notifikasi Tiket Halo APU',
    description: 'Channel prioritas tinggi untuk pembaruan tiket dan pesan masuk.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  /// Ikon small notification: siluet putih (mipmap launcher tampil kotak putih di Android 8+).
  static const String _icon = 'ic_stat_notify';

  static const MethodChannel _workerChannel =
      MethodChannel('id.haloapu.mobile/background_worker');
  static const String notifiedIdsPrefsKey = 'notified_notification_ids_v1';
  static const int maxNotifiedIdsHistory = 50;

  static bool _isInitialized = false;
  static bool _localReady = false;
  static bool _fcmWired = false;
  static bool _workerHandlerWired = false;
  static bool _backgroundWorkerConfigured = false;
  static String? _lastFcmToken;
  static Future<void>? _initFuture;
  static Timer? _pollingTimer;
  static String? _lastKnownNotifId;
  static int _notifIdCounter = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static VoidCallback? onNotificationReceived;

  @visibleForTesting
  static Future<bool> Function()? requestLocalPermissionOverride;

  @visibleForTesting
  static Future<bool?> Function()? areLocalNotificationsEnabledOverride;

  @visibleForTesting
  static bool isPlaceholderOptions({
    required String projectId,
    required String apiKey,
    required String appId,
  }) {
    final p = projectId.trim().toLowerCase();
    final k = apiKey.trim().toLowerCase();
    final a = appId.trim().toLowerCase();
    return p.isEmpty ||
        p == 'haloapu-dev' ||
        k.isEmpty ||
        k.startsWith('fake_') ||
        a.isEmpty ||
        a.contains('123456789012');
  }

  static bool get isPlaceholderFirebaseConfig {
    try {
      if (Firebase.apps.isEmpty) return true;
      final options = Firebase.app().options;
      return isPlaceholderOptions(
        projectId: options.projectId,
        apiKey: options.apiKey,
        appId: options.appId,
      );
    } catch (_) {
      return true;
    }
  }

  static Future<NotificationDiagnosticStatus> getDiagnosticStatus() async {
    bool permissionGranted = (await areLocalNotificationsEnabled()) ?? false;
    if (!permissionGranted) {
      try {
        final settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        permissionGranted =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus ==
                    AuthorizationStatus.provisional;
      } catch (_) {}
    }

    final isPlaceholder = isPlaceholderFirebaseConfig;
    final fcmReady = Firebase.apps.isNotEmpty &&
        !isPlaceholder &&
        _lastFcmToken != null &&
        _lastFcmToken!.isNotEmpty;

    return NotificationDiagnosticStatus(
      permissionGranted: permissionGranted,
      fcmReady: fcmReady,
      isPlaceholderConfig: isPlaceholder,
      backgroundWorkerActive: _backgroundWorkerConfigured,
      realtimePollerActive: _pollingTimer != null,
    );
  }

  /// Inisialisasi Firebase Messaging dan Flutter Local Notifications
  static Future<void> init() {
    if (_isInitialized) return Future<void>.value();
    // Gate agar pemanggil lain (token sync, show) menunggu init yang sama,
    // dan retry tetap mungkin bila init gagal.
    return _initFuture ??= _init().whenComplete(() {
      if (!_isInitialized) _initFuture = null;
    });
  }

  static Future<void> _init() async {
    try {
      // 1. Inisialisasi Firebase App jika belum (dengan timeout 3 detik)
      bool hasFirebase = false;
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp().timeout(const Duration(seconds: 3));
        }
        hasFirebase = Firebase.apps.isNotEmpty;
      } catch (e) {
        debugPrint('Firebase already initialized or initialization error: $e');
      }

      // 2. Setup Background Handler jika Firebase tersedia
      if (hasFirebase) {
        try {
          FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        } catch (e) {
          debugPrint('FCM background message registration error: $e');
        }
      }

      // 3. Inisialisasi Local Notifications
      await _initLocal();

      // 5-9. Setup FCM listener hanya jika Firebase tersedia & belum terpasang
      if (hasFirebase && !_fcmWired) {
        try {
          await FirebaseMessaging.instance
              .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          ).timeout(const Duration(seconds: 2));

          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
            debugPrint('FCM Foreground message: ${message.notification?.title}');
            _showLocalNotification(message);
            onNotificationReceived?.call();
          });

          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
            debugPrint('FCM Notification tapped from background: ${message.data}');
            _handleNotificationData(message.data);
          });

          final RemoteMessage? initialMessage =
              await FirebaseMessaging.instance.getInitialMessage().timeout(const Duration(seconds: 2));
          if (initialMessage != null) {
            debugPrint('FCM Initial message found: ${initialMessage.data}');
            Future.delayed(const Duration(milliseconds: 800), () {
              _handleNotificationData(initialMessage.data);
            });
          }

          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
            debugPrint('FCM Token refreshed: $newToken');
            syncFcmTokenWithBackend(token: newToken);
          });
          _fcmWired = true;
        } catch (e) {
          debugPrint('FCM listeners setup error: $e');
        }
      }

      // 10. Mulai Real-time Poller otomatis
      startRealtimePoller();

      // 11. Sinkronkan token bila sesi sudah ada (mis. app dibuka via deep link
      // tanpa melewati dashboard).
      unawaited(syncFcmTokenWithBackend());

      _isInitialized = true;
      debugPrint('PushNotificationService initialized successfully');
    } catch (e) {
      debugPrint('PushNotificationService init error: $e');
    }
  }

  /// Siapkan plugin notifikasi lokal + channel. Terpisah agar bisa dicoba
  /// ulang tanpa mendaftarkan ulang listener FCM.
  static Future<void> _initLocal() async {
    if (_localReady) return;
    const InitializationSettings initSettings = InitializationSettings(
      android: AndroidInitializationSettings(_icon),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    try {
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            _handleNotificationData(jsonDecode(payload) as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Error parsing notification payload: $e');
          }
        },
      ).timeout(const Duration(seconds: 2));

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
      _localReady = true;
    } catch (e) {
      debugPrint('Local notifications init error: $e');
    }

    // Tap notifikasi lokal saat app terminated (tidak lewat getInitialMessage).
    try {
      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      final payload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 800), () {
          try {
            _handleNotificationData(jsonDecode(payload) as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Error parsing launch payload: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('Notification launch details error: $e');
    }

    _ensureWorkerChannelHandler();

    // Tap notifikasi yang dibuat oleh Native Android WorkManager saat app terminated.
    try {
      final workerPayload =
          await _safeWorkerInvoke<String?>('consumeLaunchPayload');
      if (workerPayload != null && workerPayload.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 800), () {
          try {
            _handleNotificationData(
              jsonDecode(workerPayload) as Map<String, dynamic>,
            );
          } catch (e) {
            debugPrint('Error parsing worker launch payload: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('Worker launch details error: $e');
    }
  }

  static void _ensureWorkerChannelHandler() {
    if (_workerHandlerWired) return;
    _workerHandlerWired = true;
    try {
      _workerChannel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'onNotificationTapped') {
          final raw = call.arguments;
          if (raw is String && raw.isNotEmpty) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map) {
                await _handleNotificationData(
                  Map<String, dynamic>.from(decoded),
                );
              }
            } catch (e) {
              debugPrint('Error parsing worker tap payload: $e');
            }
          } else if (raw is Map) {
            await _handleNotificationData(Map<String, dynamic>.from(raw));
          }
        }
      });
    } catch (e) {
      _workerHandlerWired = false;
      debugPrint('Worker channel handler error: $e');
    }
  }

  @visibleForTesting
  static void ensureWorkerHandlerForTest() => _ensureWorkerChannelHandler();

  static Future<T?> _safeWorkerInvoke<T>(
    String method, [
    dynamic arguments,
  ]) async {
    try {
      return await _workerChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Worker MethodChannel error ($method): $e');
      return null;
    } catch (e) {
      debugPrint('Worker MethodChannel unexpected error ($method): $e');
      return null;
    }
  }

  static Future<bool> requestLocalNotificationPermission() async {
    if (requestLocalPermissionOverride != null) {
      return requestLocalPermissionOverride!();
    }
    try {
      if (!_localReady) await _initLocal();
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Local notification permission request error: $e');
      return false;
    }
  }

  static Future<bool?> areLocalNotificationsEnabled() async {
    if (areLocalNotificationsEnabledOverride != null) {
      return areLocalNotificationsEnabledOverride!();
    }
    try {
      if (!_localReady) await _initLocal();
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.areNotificationsEnabled();
    } catch (e) {
      debugPrint('Local notification status check error: $e');
      return null;
    }
  }

  @visibleForTesting
  static Future<bool> hasSeenNotificationId(
    String id, {
    SharedPreferences? prefs,
  }) async {
    final normalized = id.trim();
    if (normalized.isEmpty) return false;
    final store = prefs ?? await SharedPreferences.getInstance();
    final list = store.getStringList(notifiedIdsPrefsKey) ?? const <String>[];
    return list.contains(normalized);
  }

  @visibleForTesting
  static Future<List<String>> recordSeenNotificationId(
    String id, {
    SharedPreferences? prefs,
    bool syncNative = true,
  }) async {
    final normalized = id.trim();
    final store = prefs ?? await SharedPreferences.getInstance();
    final current = List<String>.from(
      store.getStringList(notifiedIdsPrefsKey) ?? const <String>[],
    );
    if (normalized.isEmpty) return current;

    current.remove(normalized);
    current.add(normalized);
    while (current.length > maxNotifiedIdsHistory) {
      current.removeAt(0);
    }
    await store.setStringList(notifiedIdsPrefsKey, current);

    if (syncNative) {
      unawaited(_safeWorkerInvoke<bool>('markNotificationSeen', {'id': normalized}));
    }
    return current;
  }

  @visibleForTesting
  static Future<List<String>> getSeenNotificationIds({
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final local = List<String>.from(
      store.getStringList(notifiedIdsPrefsKey) ?? const <String>[],
    );
    final nativeIds =
        await _safeWorkerInvoke<List<dynamic>>('getSeenNotificationIds');
    if (nativeIds != null && nativeIds.isNotEmpty) {
      for (final raw in nativeIds) {
        final item = raw?.toString().trim() ?? '';
        if (item.isEmpty) continue;
        local.remove(item);
        local.add(item);
      }
      while (local.length > maxNotifiedIdsHistory) {
        local.removeAt(0);
      }
      await store.setStringList(notifiedIdsPrefsKey, local);
    }
    return local;
  }

  static Future<void> clearSeenNotificationIds({
    SharedPreferences? prefs,
  }) async {
    try {
      final store = prefs ?? await SharedPreferences.getInstance();
      await store.remove(notifiedIdsPrefsKey);
    } catch (_) {}
  }

  static Future<bool> configureBackgroundWorker({
    bool? baselineSet,
  }) async {
    try {
      final authToken = await SafeSecureStorage.read('auth_token');
      if (authToken == null || authToken.trim().isEmpty) {
        return false;
      }
      final seenIds = await getSeenNotificationIds();
      final result = await _safeWorkerInvoke<bool>('configureWorker', {
        'authToken': authToken,
        'baseUrl': ApiConfig.baseUrl,
        'releaseChannel': FlavorConfig.releaseChannel,
        'seenIds': seenIds,
        'baselineSet': baselineSet ?? _baselineSet,
      });
      if (result == true) {
        _backgroundWorkerConfigured = true;
      }
      return result == true;
    } catch (e) {
      debugPrint('Error configuring background worker: $e');
      return false;
    }
  }

  static Future<void> onAppPaused() async {
    try {
      final authToken = await SafeSecureStorage.read('auth_token');
      if (authToken == null || authToken.trim().isEmpty) return;
      await _safeWorkerInvoke<bool>('scheduleQuickCheck');
    } catch (_) {}
  }

  static Future<void> openBatteryOptimizationSettings() async {
    await _safeWorkerInvoke<bool>('openBatteryOptimizationSettings');
  }

  static int _lastUnreadCount = 0;
  static bool _baselineSet = false;
  static bool _isCheckingNotifs = false;

  /// Memulai Real-time Poller untuk memeriksa notifikasi baru secara instan
  static void startRealtimePoller() {
    unawaited(configureBackgroundWorker());
    // Sudah berjalan: jangan re-baseline (bisa melewatkan notif yang baru masuk).
    if (_pollingTimer != null) return;

    // Polling setiap 25 detik (hemat baterai & ramah server)
    _pollingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _checkNewNotifications();
    });
    _checkNewNotifications();
  }

  /// Menghentikan Poller saat logout
  static void stopRealtimePoller() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _lastUnreadCount = 0;
    _baselineSet = false;
    _lastKnownNotifId = null;
    _lastFcmToken = null;
    _backgroundWorkerConfigured = false;
    unawaited(clearSeenNotificationIds());
    unawaited(_safeWorkerInvoke<bool>('clearWorker'));
  }

  /// Memeriksa notifikasi baru secara efisien dan membunyikan alert lokal jika ada pembaruan status
  static Future<void> _checkNewNotifications() async {
    if (_isCheckingNotifs) return;
    _isCheckingNotifs = true;
    try {
      final token = await SafeSecureStorage.read('auth_token');
      if (token == null || token.isEmpty) return;
      final apiClient = ApiClient();
      // 1. Cek jumlah unread secara ringan terlebih dahulu
      final countRes = await apiClient.dio.get('/notifications/unread-count');
      if (countRes.statusCode != 200) return;

      final int currentUnread = countRes.data['data']?['count'] ?? 0;

      // Poll pertama hanya menetapkan baseline; jangan notifikasi item lama.
      if (!_baselineSet) {
        _baselineSet = true;
        _lastUnreadCount = currentUnread;
        if (currentUnread > 0) {
          try {
            final seedRes = await apiClient.dio.get(
              '/notifications',
              queryParameters: {'page': 1, 'per_page': 5},
            );
            if (seedRes.statusCode == 200) {
              final List<dynamic> seedList = seedRes.data['data'] ?? [];
              for (final rawItem in seedList.reversed) {
                if (rawItem is Map) {
                  final seedId = rawItem['id']?.toString().trim();
                  if (seedId != null && seedId.isNotEmpty) {
                    await recordSeenNotificationId(seedId, syncNative: false);
                  }
                }
              }
              if (seedList.isNotEmpty && seedList.first is Map) {
                _lastKnownNotifId =
                    (seedList.first as Map)['id']?.toString().trim();
              }
            }
          } catch (_) {}
        }
        unawaited(configureBackgroundWorker(baselineSet: true));
        return;
      }

      if (currentUnread > _lastUnreadCount) {
        _lastUnreadCount = currentUnread;
        onNotificationReceived?.call();

        // 2. Ambil notifikasi teratas untuk menampilkan banner & suara
        final notifListResponse = await apiClient.dio.get(
          '/notifications',
          queryParameters: {'page': 1, 'per_page': 1},
        );

        if (notifListResponse.statusCode == 200) {
          final List<dynamic> list = notifListResponse.data['data'] ?? [];
          if (list.isNotEmpty && list.first is Map) {
            final latest = Map<String, dynamic>.from(list.first as Map);
            final id = latest['id']?.toString().trim();

            if (id != null &&
                id.isNotEmpty &&
                id != _lastKnownNotifId &&
                !await hasSeenNotificationId(id)) {
              _lastKnownNotifId = id;
              await recordSeenNotificationId(id);
              final alert = buildAlertFromNotificationJson(latest);
              if (alert != null) {
                await showNotificationAlert(
                  title: alert.title,
                  body: alert.body,
                  data: alert.data,
                  notificationKey: id,
                );
              }
            }
          }
        }
      } else {
        _lastUnreadCount = currentUnread;
      }
    } catch (_) {
      // Abaikan error jaringan sementara
    } finally {
      _isCheckingNotifs = false;
    }
  }

  /// Menampilkan banner notifikasi pop-up native OS + suara + getar
  static Future<void> showNotificationAlert({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? notificationKey,
  }) async {
    // WAJIB menunggu inisialisasi plugin lokal; jangan jalankan poller di background isolate.
    if (!_localReady) await _initLocal();
    if (!_localReady) {
      debugPrint('Skip local notification: local notifications not ready');
      return;
    }

    final resolvedKey = (notificationKey ??
            data?['notification_id']?.toString() ??
            data?['id']?.toString())
        ?.trim();
    final String? notifTag = (resolvedKey != null && resolvedKey.isNotEmpty)
        ? 'haloapu_notif_$resolvedKey'
        : null;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.max,
      icon: _icon,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ticker: title,
      category: AndroidNotificationCategory.message,
      tag: notifTag,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Deterministic ID per notification_id agar balapan FCM/Worker menimpa kartu yang sama.
    final int notifId = (resolvedKey != null && resolvedKey.isNotEmpty)
        ? resolvedKey.hashCode
        : _notifIdCounter++;
    try {
      await _localNotifications.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: platformDetails,
        payload: data != null ? jsonEncode(data) : null,
      );
    } catch (e) {
      debugPrint('Gagal menampilkan notifikasi lokal: $e');
    }
  }

  /// Membentuk payload banner lokal dari item `GET /api/notifications`.
  /// Mengembalikan `null` jika item adalah `app_update` untuk channel lain.
  @visibleForTesting
  static ({String title, String body, Map<String, dynamic> data})?
      buildAlertFromNotificationJson(
    Map<String, dynamic> latest, {
    String? currentChannel,
  }) {
    final nestedData = latest['data'] is Map
        ? Map<String, dynamic>.from(latest['data'] as Map)
        : null;
    final nestedMeta = latest['meta'] is Map
        ? Map<String, dynamic>.from(latest['meta'] as Map)
        : null;

    String? pickText(List<dynamic> candidates) {
      for (final candidate in candidates) {
        final text = candidate?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    }

    final id = pickText([latest['id']]);
    final rawType = pickText([
      latest['type'],
      nestedData?['type'],
      nestedMeta?['type'],
    ]);

    if (rawType == 'app_update') {
      final channel = pickText([
        latest['channel'],
        nestedData?['channel'],
        nestedMeta?['channel'],
      ]);
      final versionName = pickText([
        latest['version_name'],
        latest['versionName'],
        nestedData?['version_name'],
        nestedData?['versionName'],
        nestedMeta?['version_name'],
        nestedMeta?['versionName'],
      ]);
      final buildNumber = pickText([
        latest['build_number'],
        latest['buildNumber'],
        nestedData?['build_number'],
        nestedData?['buildNumber'],
        nestedMeta?['build_number'],
        nestedMeta?['buildNumber'],
      ]);

      final payload = <String, dynamic>{
        'type': 'app_update',
        if (channel != null) 'channel': channel,
        if (versionName != null) 'version_name': versionName,
        if (buildNumber != null) 'build_number': buildNumber,
        if (id != null) 'id': id,
      };

      if (shouldIgnoreAppUpdatePayload(payload, currentChannel: currentChannel)) {
        return null;
      }

      return (
        title: pickText([latest['title'], nestedData?['title']]) ??
            'Pembaruan Aplikasi Tersedia',
        body: pickText([
              latest['body'],
              latest['message'],
              nestedData?['body'],
              nestedData?['message'],
            ]) ??
            'Versi baru Halo APU tersedia untuk diunduh.',
        data: payload,
      );
    }

    final ticketId = latest['ticketId'] ??
        latest['ticket_id'] ??
        nestedData?['ticketId'] ??
        nestedData?['ticket_id'];

    return (
      title: pickText([latest['title']]) ?? 'Pembaruan Tiket',
      body: pickText([latest['body'], latest['message']]) ??
          'Ada perubahan status pada tiket Anda',
      data: <String, dynamic>{
        if (rawType != null) 'type': rawType,
        'ticket_id': ticketId,
        if (id != null) 'id': id,
      },
    );
  }

  /// Mengembalikan `true` jika payload `app_update` ditujukan untuk channel lain
  /// sehingga tidak memicu banner atau dialog pada flavor yang berbeda.
  @visibleForTesting
  static bool shouldIgnoreAppUpdatePayload(
    Map<String, dynamic> data, {
    String? currentChannel,
  }) {
    if (data['type'] != 'app_update') return false;
    final payloadChannel = data['channel']?.toString().trim().toLowerCase();
    if (payloadChannel == null || payloadChannel.isEmpty) return false;
    final activeChannel =
        (currentChannel ?? FlavorConfig.releaseChannel).trim().toLowerCase();
    return payloadChannel != activeChannel;
  }

  @visibleForTesting
  static Future<void> handleNotificationDataForTest(
    Map<String, dynamic> data,
  ) =>
      _handleNotificationData(data);

  /// Menampilkan notifikasi lokal heads-up banner saat pesan diterima dari FCM foreground
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    if (shouldIgnoreAppUpdatePayload(data)) return;

    final notifId = data['notification_id']?.toString().trim() ??
        data['id']?.toString().trim() ??
        message.messageId?.trim();
    if (notifId != null && notifId.isNotEmpty) {
      if (await hasSeenNotificationId(notifId)) return;
      await recordSeenNotificationId(notifId);
    }

    final title = notification?.title ?? data['title'] ?? 'Halo APU';
    final body = notification?.body ?? data['body'] ?? data['message'] ?? 'Ada pembaruan tiket baru';

    await showNotificationAlert(
      title: title,
      body: body,
      data: data,
      notificationKey: notifId,
    );
  }

  /// Mengirimkan FCM Token ke backend Laravel agar device terdaftar
  static Future<void> syncFcmTokenWithBackend({String? token}) async {
    try {
      await init();
      final authToken = await SafeSecureStorage.read('auth_token');
      if (authToken == null || authToken.isEmpty) {
        debugPrint('Skip FCM sync: User not logged in yet');
        return;
      }

      unawaited(configureBackgroundWorker());

      final fcmToken = token ?? await FirebaseMessaging.instance.getToken();
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('Skip FCM sync: FCM token is null or empty');
        return;
      }

      _lastFcmToken = fcmToken;
      debugPrint('Sending FCM token to backend: $fcmToken');
      final apiClient = ApiClient();
      final response = await apiClient.dio.post(
        '/fcm-token',
        data: {'fcm_token': fcmToken},
      );

      debugPrint('FCM Token synced to backend: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error syncing FCM token with backend: $e');
    }
  }

  /// Menangani navigasi / Deep Linking saat notifikasi diklik
  static Future<void> _handleNotificationData(Map<String, dynamic> data) async {
    try {
      // Notifikasi pembaruan aplikasi boleh dibuka bahkan sebelum user login
      if (data['type'] == 'app_update') {
        if (shouldIgnoreAppUpdatePayload(data)) return;
        AppUpdateService.instance.triggerFromNotification();
        return;
      }

      final role = await SafeSecureStorage.read('user_role');
      final authToken = await SafeSecureStorage.read('auth_token');
      if (authToken == null || authToken.isEmpty) {
        debugPrint('Cannot navigate to ticket: User not authenticated');
        return;
      }

      final ticketId = data['ticket_id']?.toString() ??
          data['ticketId']?.toString() ??
          (data['id'] != null && int.tryParse(data['id'].toString().replaceAll('-', '')) != null
              ? data['id'].toString()
              : null);

      if (ticketId != null && ticketId.isNotEmpty) {
        final cleanId = ticketId.replaceAll('-', '').trim();
        try {
          final apiClient = ApiClient();
          final response = await apiClient.dio.get('/tickets/$cleanId');
          if (response.statusCode == 200) {
            final ticketData = response.data['data'] ?? response.data;
            final ticket = TicketModel.safeFromJson(ticketData);

            if (role == 'admin') {
              appRouter.push('/tickets/admin/detail', extra: ticket);
            } else {
              appRouter.push('/tickets/user/detail', extra: ticket);
            }
            return;
          }
        } catch (e) {
          debugPrint('Error fetching ticket detail for notification deep link: $e');
        }

        // Fallback navigasi jika jaringan offline/gagal: tetap buka detail tiket
        final fallbackTicket = TicketModel(
          id: cleanId,
          title: data['title']?.toString() ?? 'Tiket #$cleanId',
          category: 'Umum',
          status: TicketStatus.open,
          createdAt: DateTime.now(),
          requesterName: 'Pengguna',
          description: data['body']?.toString() ?? data['message']?.toString() ?? '',
        );
        if (role == 'admin') {
          appRouter.push('/tickets/admin/detail', extra: fallbackTicket);
        } else {
          appRouter.push('/tickets/user/detail', extra: fallbackTicket);
        }
        return;
      }

      // Jika tipe CSAT / Rating
      if (data['type'] == 'csat') {
        if (role == 'admin') {
          appRouter.push('/ratings/admin');
        } else {
          appRouter.push('/ratings/history');
        }
        return;
      }

      // Fallback: Navigasi ke halaman notifikasi
      if (role == 'admin') {
        appRouter.push('/notifications/admin');
      } else {
        appRouter.push('/notifications');
      }
    } catch (e) {
      debugPrint('Error handling notification tap navigation: $e');
    }
  }
}
