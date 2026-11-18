import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  static const String _promptShownKey = 'app_permission_prompt_shown_v1';
  static const String _notificationGrantedKey = 'notification_permission_granted';

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

  /// Meminta izin Notifikasi (Firebase Messaging & Android 13+)
  static Future<bool> requestNotificationPermission() async {
    try {
      // 1. Request via Firebase Messaging
      final NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final bool fcmGranted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      // Firebase Messaging di Android 13+ sudah memicu dialog POST_NOTIFICATIONS,
      // jadi tidak perlu plugin lokal kedua (instance baru = dialog tak muncul).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notificationGrantedKey, fcmGranted);

      return fcmGranted;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return false;
    }
  }

  /// Cek apakah izin notifikasi saat ini aktif
  static Future<bool> isNotificationPermissionGranted() async {
    try {
      final NotificationSettings settings = await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Error checking notification permission: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_notificationGrantedKey) ?? false;
    }
  }
}
