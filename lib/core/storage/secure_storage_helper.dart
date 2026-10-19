import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Helper Secure Storage dengan konfigurasi anti-hang untuk Xiaomi/MIUI & Samsung
/// Menggunakan `resetOnError: true` dan timeout pengaman agar KeyStore deadlock tidak membuat splash screen freeze
class SafeSecureStorage {
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: true,
  );

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static const FlutterSecureStorage storage = FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iosOptions,
  );

  /// Membaca value dengan batas waktu timeout agar router/splash tidak macet jika KeyStore error
  static Future<String?> read(String key, {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      return await storage.read(key: key).timeout(timeout);
    } catch (e) {
      debugPrint('SafeSecureStorage read error ($key): $e');
      return null;
    }
  }

  /// Menulis value dengan penanganan timeout
  static Future<void> write(String key, String? value, {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      await storage.write(key: key, value: value).timeout(timeout);
    } catch (e) {
      debugPrint('SafeSecureStorage write error ($key): $e');
    }
  }

  /// Menghapus value
  static Future<void> delete(String key, {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      await storage.delete(key: key).timeout(timeout);
    } catch (e) {
      debugPrint('SafeSecureStorage delete error ($key): $e');
    }
  }

  /// Menghapus seluruh data sesi
  static Future<void> deleteAll({Duration timeout = const Duration(seconds: 2)}) async {
    try {
      await storage.deleteAll().timeout(timeout);
    } catch (e) {
      debugPrint('SafeSecureStorage deleteAll error: $e');
    }
  }
}
