import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  static const String _promptShownKey = 'app_permission_prompt_shown_v1';
  static const String _notificationGrantedKey = 'notification_permission_granted';

  @visibleForTesting
  static Future<bool> Function()? fcmRequestPermissionOverride;

  /// Cek apakah dialog pengantar izin perlu ditampilkan ke pengguna
  static Future<bool> shouldShowPermissionPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_promptShownKey) ?? false);
  }

  /// Tandai bahwa dialog pengantar izin sudah pernah ditampilkan
  static Future<void> markPermissionPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptShownKey, true);
  }

  /// Reset status dialog pengantar izin (berguna untuk testing / logout)
  static Future<void> resetPermissionPromptStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_promptShownKey);
  }

  /// Meminta izin Notifikasi (Android 13+ local fallback & Firebase Messaging)
  static Future<bool> requestNotificationPermission() async {
    // 1. Selalu minta izin OS melalui AndroidFlutterLocalNotificationsPlugin terlebih dahulu
    // agar dialog POST_NOTIFICATIONS Android 13+ tetap muncul meski Firebase gagal/placeholder.
    final bool localGranted =
        await PushNotificationService.requestLocalNotificationPermission();

    bool fcmGranted = false;
    try {
      if (fcmRequestPermissionOverride != null) {
        fcmGranted = await fcmRequestPermissionOverride!()
            .timeout(const Duration(seconds: 3));
      } else {
        final NotificationSettings settings = await FirebaseMessaging.instance
            .requestPermission(
              alert: true,
              announcement: false,
              badge: true,
              carPlay: false,
              criticalAlert: false,
              provisional: false,
              sound: true,
            )
            .timeout(const Duration(seconds: 3));

        fcmGranted =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
      }
    } catch (e) {
      debugPrint('FCM notification permission request error: $e');
    }

    final bool granted = localGranted || fcmGranted;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notificationGrantedKey, granted);
    } catch (_) {}

    return granted;
  }

  /// Cek apakah izin notifikasi saat ini aktif
  static Future<bool> isNotificationPermissionGranted() async {
    try {
      final bool? localEnabled =
          await PushNotificationService.areLocalNotificationsEnabled();
      if (localEnabled != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_notificationGrantedKey, localEnabled);
        } catch (_) {}
        return localEnabled;
      }
    } catch (e) {
      debugPrint('Local notification permission check error: $e');
    }

    try {
      final NotificationSettings settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Error checking notification permission: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_notificationGrantedKey) ?? false;
    }
  }
}
