import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Helper Secure Storage terpusat untuk seluruh aplikasi.
/// - `resetOnError: false` mencegah penghapusan permanen token saat terjadi error KeyStore sementara.
/// - `migrateWithBackup: true` melindungi migrasi cipher v10 agar tidak kehilangan data bila app terhenti.
/// - `IOSOptions(accessibility: KeychainAccessibility.first_unlock)` menjaga akses keychain saat app resume/background.
/// - In-memory cache & retry menjaga cold-start/resume tidak gagal membaca token akibat KeyStore lambat.
class SafeSecureStorage {
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  );

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iosOptions,
  );

  static FlutterSecureStorage get storage => _storage;

  static final Map<String, String> _memoryCache = <String, String>{};
  static final Map<String, Future<String?>> _inFlightReads = <String, Future<String?>>{};

  @visibleForTesting
  static void setStorageForTesting(FlutterSecureStorage customStorage) {
    _storage = customStorage;
    _memoryCache.clear();
    _inFlightReads.clear();
  }

  @visibleForTesting
  static void clearMemoryCacheForTesting() {
    _memoryCache.clear();
    _inFlightReads.clear();
  }

  /// Membaca value dengan in-memory cache, single-flight deduplication, retry ringan, dan batas timeout.
  static Future<String?> read(
    String key, {
    Duration timeout = const Duration(seconds: 2),
    bool bypassCache = false,
  }) async {
    if (!bypassCache && _memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    if (!bypassCache && _inFlightReads.containsKey(key)) {
      return _inFlightReads[key]!;
    }

    final future = _readInternal(key, timeout: timeout);
    _inFlightReads[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightReads[key], future)) {
        _inFlightReads.remove(key);
      }
    }
  }

  static Future<String?> _readInternal(String key, {required Duration timeout}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final value = await _storage.read(key: key).timeout(timeout);
        if (value != null) {
          _memoryCache[key] = value;
        } else {
          _memoryCache.remove(key);
        }
        return value;
      } on TimeoutException catch (e) {
        debugPrint('SafeSecureStorage read timeout ($key): $e');
        break;
      } catch (e) {
        final msg = e.toString();
        debugPrint('SafeSecureStorage read error ($key, attempt ${attempt + 1}): $msg');
        if (msg.contains('MissingPluginException')) break;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }
    }
    return _memoryCache[key];
  }

  /// Menulis value ke storage dan cache memori.
  static Future<void> write(
    String key,
    String? value, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (value == null) {
      await delete(key, timeout: timeout);
      return;
    }
    _memoryCache[key] = value;
    try {
      await _storage.write(key: key, value: value).timeout(timeout);
    } catch (e) {
      debugPrint('SafeSecureStorage write error ($key): $e');
    }
  }

  /// Menghapus value dari storage dan cache memori.
  static Future<void> delete(
    String key, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _memoryCache.remove(key);
    try {
      await _storage.delete(key: key).timeout(timeout);
    } catch (e) {
      debugPrint('SafeSecureStorage delete error ($key): $e');
    }
  }

  /// Menghapus data sesi autentikasi saja (mempertahankan device_id & pengaturan biometrik).
  static Future<void> clearSession({Duration timeout = const Duration(seconds: 4)}) async {
    await Future.wait([
      delete('auth_token', timeout: timeout),
      delete('user_data', timeout: timeout),
      delete('user_role', timeout: timeout),
    ]);
  }

  /// Menghapus seluruh data storage.
  static Future<void> deleteAll({Duration timeout = const Duration(seconds: 4)}) async {
    _memoryCache.clear();
    try {
      await _storage.deleteAll().timeout(timeout);
    } catch (e) {
      debugPrint('SafeSecureStorage deleteAll error: $e');
    }
  }
}
