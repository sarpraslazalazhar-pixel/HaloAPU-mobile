import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:halo_apu_mobile/core/config/api_config.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';
import 'package:halo_apu_mobile/core/services/device_service.dart';
import 'package:halo_apu_mobile/core/services/biometric_service.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';

class AuthService {
  final Dio? _customDio;
  final Future<String?> Function()? _fcmTokenProvider;
  final Future<String> Function()? _deviceIdProvider;
  final Future<String> Function()? _deviceNameProvider;
  final BiometricService? _biometricService;

  AuthService({
    Dio? dio,
    Future<String?> Function()? fcmTokenProvider,
    Future<String> Function()? deviceIdProvider,
    Future<String> Function()? deviceNameProvider,
    BiometricService? biometricService,
  })  : _customDio = dio,
        _fcmTokenProvider = fcmTokenProvider,
        _deviceIdProvider = deviceIdProvider,
        _deviceNameProvider = deviceNameProvider,
        _biometricService = biometricService;

  Dio get _dio =>
      _customDio ??
      Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ));

  Future<Map<String, dynamic>> login(String email, String password, bool isAdmin) async {
    try {
      final deviceId = await (_deviceIdProvider ?? DeviceService.getDeviceId)();
      final deviceName = await (_deviceNameProvider ?? DeviceService.getDeviceName)();
      String? fcmToken;
      try {
        final provider = _fcmTokenProvider ?? () => FirebaseMessaging.instance.getToken();
        fcmToken = await provider().timeout(const Duration(seconds: 3));
      } catch (_) {}

      final response = await _dio.post(
        '/login',
        data: {
          'email': email,
          'password': password,
          'is_admin': isAdmin,
          'device_id': deviceId,
          'device_name': deviceName,
          'fcm_token': fcmToken,
        },
      );

      final data = response.data;

      if (response.statusCode == 200) {
        final token = data['data']['token'] as String;
        final userData = data['data']['user'] as Map<String, dynamic>;
        final role = (data['data']['role'] ?? (isAdmin ? 'admin' : 'user')) as String;
        final userDataJson = jsonEncode(userData);
        final name = (userData['name'] ?? userData['username'] ?? 'Pengguna') as String;

        // Simpan token & user info di secure storage terpusat untuk persistensi sesi
        AttachmentService.setCachedToken(token);
        await SafeSecureStorage.write('auth_token', token);
        await SafeSecureStorage.write('user_data', userDataJson);
        await SafeSecureStorage.write('user_role', role);
        // Jika biometrik diaktifkan, hanya perbarui kredensial untuk akun & role yang sama;
        // jika berbeda akun, nonaktifkan & hapus kredensial lama agar tidak tertimpa diam-diam.
        final biometricService = _biometricService ?? BiometricService();
        await syncBiometricCredentialsOnLogin(
          biometricService: biometricService,
          email: email,
          password: password,
          name: name,
          role: role,
        );

        SessionManager.instance.notifyLoginSuccess();
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message': data['message'] ?? 'Login gagal',
        };
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final respData = e.response?.data;

      if (statusCode == 429) {
        final retryAfter = parseRetryAfterSeconds(e.response);
        final rawMsg = (respData is Map ? respData['message'] : null)?.toString().trim();
        final message = (rawMsg != null && rawMsg.isNotEmpty && rawMsg != 'Too Many Attempts.')
            ? rawMsg
            : 'Terlalu banyak percobaan login. Silakan coba lagi dalam $retryAfter detik.';
        return {
          'success': false,
          'statusCode': 429,
          'retry_after': retryAfter,
          'error_code': 'RATE_LIMITED',
          'message': message,
        };
      }

      if (respData != null && respData is Map && respData['message'] != null) {
        return {
          'success': false,
          'statusCode': statusCode,
          'message': respData['message'],
          'error_code': respData['error_code'],
        };
      }

      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        return {
          'success': false,
          'statusCode': statusCode,
          'message': 'Koneksi timeout ke ${ApiConfig.baseUrl}. Periksa jaringan atau setting Host.'
        };
      }

      return {
        'success': false,
        'statusCode': statusCode,
        'message': 'Gagal terhubung ke ${ApiConfig.baseUrl}. Pastikan server aktif & satu jaringan.'
      };
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan: $e'};
    }
  }

  /// Menjaga keamanan kredensial biometrik saat login: perbarui hanya jika
  /// akun & role sama; jika berganti akun, matikan biometrik dan hapus kredensial lama.
  static Future<void> syncBiometricCredentialsOnLogin({
    required BiometricService biometricService,
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    if (!await biometricService.isEnabled()) return;

    final savedUser = await biometricService.getSavedBiometricUser();
    final savedEmail = (savedUser?['email'] ?? '').trim().toLowerCase();
    final savedRole = savedUser?['role'];

    if (savedUser != null &&
        savedEmail == email.trim().toLowerCase() &&
        savedRole == role) {
      await biometricService.saveBiometricCredentials(
        email: email,
        password: password,
        name: name,
        role: role,
      );
    } else {
      await biometricService.setEnabled(false);
    }
  }

  /// Mengekstrak nilai `retry_after` (detik) dari body JSON atau header `Retry-After`.
  static int parseRetryAfterSeconds(Response<dynamic>? response) {
    int? parsed;
    final data = response?.data;
    if (data is Map && data['retry_after'] != null) {
      final raw = data['retry_after'];
      if (raw is num) {
        parsed = raw.toInt();
      } else {
        parsed = int.tryParse(raw.toString().trim());
      }
    }
    parsed ??= int.tryParse(response?.headers.value('retry-after')?.trim() ?? '');
    final value = parsed ?? 60;
    return value < 1 ? 1 : value;
  }

  Future<void> logout() async {
    final token = await SafeSecureStorage.read('auth_token');
    await clearLocalSession();
    if (token != null && token.isNotEmpty) {
      unawaited(_revokeTokenOnServer(token));
    }
  }

  Future<void> _revokeTokenOnServer(String token) async {
    try {
      String? fcmToken;
      try {
        final provider = _fcmTokenProvider ?? () => FirebaseMessaging.instance.getToken();
        fcmToken = await provider().timeout(const Duration(milliseconds: 500));
      } catch (_) {}

      final client = _customDio ??
          Dio(BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ));

      await client.post(
        '/logout',
        data: {
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      // Abaikan jika token gagal di-revoke di server saat offline atau timeout
    }
  }

  /// Clear everything that belongs to the signed-in session while keeping the
  /// device id and biometric setting. Shared by logout and account deactivation.
  Future<void> clearLocalSession() async {
    await SessionManager.instance.markLoggedOut();
  }

  Future<Map<String, dynamic>> forgotPassword(String identifier, {bool isAdmin = false}) async {
    try {
      final response = await _dio.post('/forgot-password', data: {
        'email': identifier,
        'is_admin': isAdmin,
      });
      return {
        'success': true,
        'message': response.data['message'] ?? 'Tautan reset password telah dikirim ke email Anda.'
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['message'] ?? 'Gagal mengirim permintaan reset password.'
      };
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan: $e'};
    }
  }

  Future<Map<String, dynamic>> contactAdmin({
    required String message,
    String? subject,
    String? email,
    String? name,
  }) async {
    try {
      final token = await SafeSecureStorage.read('auth_token');
      final response = await _dio.post(
        '/contact-admin',
        data: {
          'message': message,
          if (subject != null && subject.isNotEmpty) 'subject': subject,
          if (email != null && email.isNotEmpty) 'email': email,
          if (name != null && name.isNotEmpty) 'name': name,
        },
        options: token != null
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );
      return {
        'success': true,
        'message': response.data['message'] ?? 'Pesan Anda telah berhasil dikirim ke Admin.'
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data['message'] ?? 'Gagal mengirim pesan ke Admin.'
      };
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadAvatar(String filePath) async {
    try {
      final token = await SafeSecureStorage.read('auth_token');
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        '/user/avatar',
        data: formData,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final userData = response.data['data'];
        await SafeSecureStorage.write('user_data', jsonEncode(userData));
        return {'success': true, 'data': userData};
      }
      return {
        'success': false,
        'message': response.data?['message'] ?? 'Gagal mengupload foto profil',
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data?['message'] ?? e.message ?? 'Gagal mengupload foto profil',
      };
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan: $e'};
    }
  }
}
