import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
/// Layanan Autentikasi Biometrik (Sidik Jari / Face ID) dengan penyimpanan aman
class BiometricService {
  static const String _flagKey = 'biometric_enabled';
  static const String _bioEmailKey = 'biometric_user_email';
  static const String _bioPasswordKey = 'biometric_user_password';
  static const String _bioNameKey = 'biometric_user_name';
  static const String _bioRoleKey = 'biometric_user_role';

  static int _activeAuthCount = 0;
  static DateTime? _lastAuthFinishedAt;

  static bool get isAuthenticating => _activeAuthCount > 0;
  static bool get recentlyFinishedAuth {
    final finishedAt = _lastAuthFinishedAt;
    if (finishedAt == null) return false;
    return DateTime.now().difference(finishedAt) < const Duration(milliseconds: 800);
  }

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_flagKey) ?? false;
    } catch (_) {
      return false;
    }
  }
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flagKey, enabled);
    if (!enabled) {
      await clearBiometricSession();
    }
  }

  /// Simpan kredensial terenkripsi di Hardware Keystore untuk login biometrik cepat
  Future<void> saveBiometricCredentials({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    await SafeSecureStorage.write(_bioEmailKey, email);
    await SafeSecureStorage.write(_bioPasswordKey, password);
    await SafeSecureStorage.write(_bioNameKey, name);
    await SafeSecureStorage.write(_bioRoleKey, role);
  }

  /// Ambil info profil tersimpan untuk tampilan kartu di layar Login
  Future<Map<String, String>?> getSavedBiometricUser() async {
    final email = await SafeSecureStorage.read(_bioEmailKey);
    final password = await SafeSecureStorage.read(_bioPasswordKey);
    if (email == null || email.isEmpty || password == null || password.isEmpty) {
      return null;
    }

    final name = await SafeSecureStorage.read(_bioNameKey) ?? 'Pengguna';
    final role = await SafeSecureStorage.read(_bioRoleKey) ?? 'user';
    return {
      'email': email,
      'name': name,
      'role': role,
    };
  }

  /// Ambil kredensial lengkap saat verifikasi sidik jari sukses untuk login ke server
  Future<Map<String, String>?> getBiometricCredentials() async {
    final email = await SafeSecureStorage.read(_bioEmailKey);
    final password = await SafeSecureStorage.read(_bioPasswordKey);
    final role = await SafeSecureStorage.read(_bioRoleKey) ?? 'user';
    final name = await SafeSecureStorage.read(_bioNameKey) ?? 'Pengguna';
    if (email != null && email.isNotEmpty && password != null && password.isNotEmpty) {
      return {
        'email': email,
        'password': password,
        'role': role,
        'name': name,
      };
    }
    return null;
  }

  /// Hapus kredensial biometrik yang tersimpan
  Future<void> clearBiometricSession() async {
    await SafeSecureStorage.delete(_bioEmailKey);
    await SafeSecureStorage.delete(_bioPasswordKey);
    await SafeSecureStorage.delete(_bioNameKey);
    await SafeSecureStorage.delete(_bioRoleKey);
  }

  /// Cek apakah perangkat mendukung dan memiliki sensor biometrik aktif
  Future<bool> canAuthenticate() async {
    if (kIsWeb) return false;
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();
      return isSupported && (canCheck || available.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Tampilkan dialog sensor sidik jari / Face ID native OS
  Future<bool> authenticate({
    String reason = 'Pindai sidik jari untuk masuk ke Halo APU',
  }) async {
    if (kIsWeb) return false;
    _activeAuthCount++;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    } finally {
      _activeAuthCount = (_activeAuthCount - 1).clamp(0, 999);
      _lastAuthFinishedAt = DateTime.now();
    }
  }
}
