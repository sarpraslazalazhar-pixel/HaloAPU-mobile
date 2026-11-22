import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../../core/services/attachment_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/device_service.dart';
import '../../core/services/session_manager.dart';
import '../../core/storage/secure_storage_helper.dart';
import '../../domain/models/user_profile_model.dart';
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthRepository(apiClient);
});

class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository(this._apiClient);

  /// Login with email/username and password.
  /// Returns the user profile data on success.
  Future<UserProfile> login(String email, String password, {bool isAdmin = false}) async {
    try {
      final deviceId = await DeviceService.getDeviceId();
      final deviceName = await DeviceService.getDeviceName();
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}

      final response = await _apiClient.dio.post(
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

      if (response.statusCode == 200) {
        final data = response.data['data'];
        final token = data['token'];
        final userData = data['user'];
        final role = (data['role'] ?? (isAdmin ? 'admin' : 'user')).toString();
        final name = (userData['name'] ?? userData['username'] ?? 'Pengguna').toString();

        // Save token
        AttachmentService.setCachedToken(token);
        await SafeSecureStorage.write('auth_token', token);
        await SafeSecureStorage.write('user_role', role);

        // Save user data as JSON
        await SafeSecureStorage.write('user_data', jsonEncode(userData));

        await AuthService.syncBiometricCredentialsOnLogin(
          biometricService: BiometricService(),
          email: email,
          password: password,
          name: name,
          role: role,
        );

        SessionManager.instance.notifyLoginSuccess();
        return UserProfile.fromJson(userData);
      } else {
        throw Exception('Gagal login: ${response.data['message']}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        final retryAfter = AuthService.parseRetryAfterSeconds(e.response);
        final data = e.response?.data;
        final rawMsg = (data is Map ? data['message'] : null)?.toString().trim();
        final message = (rawMsg != null && rawMsg.isNotEmpty && rawMsg != 'Too Many Attempts.')
            ? rawMsg
            : 'Terlalu banyak percobaan login. Silakan coba lagi dalam $retryAfter detik.';
        throw Exception(message);
      }
      if (e.response != null && e.response!.statusCode == 401) {
        final data = e.response!.data;
        final msg = (data is Map ? data['message'] : null)?.toString().trim();
        throw Exception(
          (msg != null && msg.isNotEmpty && msg != 'Unauthenticated.')
              ? msg
              : 'Email/username atau password salah',
        );
      }
      if (e.response != null && e.response!.statusCode == 422) {
        final errors = e.response!.data['errors'];
        if (errors != null) {
          final firstError = (errors as Map).values.first;
          throw Exception(firstError is List ? firstError.first : firstError.toString());
        }
      }
      throw Exception('Gagal menghubungi server: ${e.error ?? e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Terjadi kesalahan: $e');
    }
  }

  /// Logout user and clear stored data via AuthService (instant & non-blocking).
  Future<void> logout() => AuthService().logout();

  /// Check if user is currently logged in (has a stored token).
  Future<bool> isLoggedIn() async {
    final token = await SafeSecureStorage.read('auth_token');
    return token != null && token.isNotEmpty;
  }

  /// Get stored user data from secure storage (cached from last login/fetch).
  Future<UserProfile?> getStoredUser() async {
    final userData = await SafeSecureStorage.read('user_data');
    if (userData != null) {
      try {
        return UserProfile.fromJson(jsonDecode(userData));
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Fetch latest user profile from API and update local cache.
  Future<UserProfile> fetchProfile() async {
    try {
      final response = await _apiClient.dio.get('/user');
      if (response.statusCode == 200) {
        final userData = response.data['data'];
        // Update cached user data
        await SafeSecureStorage.write('user_data', jsonEncode(userData));
        return UserProfile.fromJson(userData);
      } else {
        throw Exception('Gagal memuat profil');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception(SessionManager.extractUnauthorizedMessage(e.response?.data));
      }
      throw Exception('Gagal menghubungi server: ${e.error ?? e.message}');
    }
  }

  /// Update user profile.
  Future<UserProfile> updateProfile({
    String? name,
    String? username,
    String? email,
    String? phone,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (username != null) data['username'] = username;
    if (email != null) data['email'] = email;
    if (phone != null) data['no_wa'] = phone;

    try {
      final response = await _apiClient.dio.put('/user', data: data);
      if (response.statusCode == 200) {
        final userData = response.data['data'];
        await SafeSecureStorage.write('user_data', jsonEncode(userData));
        return UserProfile.fromJson(userData);
      } else {
        throw Exception('Gagal memperbarui profil');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        final errors = e.response!.data['errors'];
        if (errors != null) {
          final firstError = (errors as Map).values.first;
          throw Exception(firstError is List ? firstError.first : firstError.toString());
        }
      }
      throw Exception('Gagal memperbarui profil: ${e.message}');
    }
  }

  /// Upload avatar image.
  Future<UserProfile> uploadAvatar(String filePath) async {
    try {
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _apiClient.dio.post('/user/avatar', data: formData);
      if (response.statusCode == 200) {
        final userData = response.data['data'];
        await SafeSecureStorage.write('user_data', jsonEncode(userData));
        return UserProfile.fromJson(userData);
      } else {
        throw Exception(response.data?['message'] ?? 'Gagal mengupload foto profil');
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? 'Gagal mengupload foto';
      throw Exception(msg);
    }
  }

  /// Change password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      final response = await _apiClient.dio.post('/user/change-password', data: {
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': confirmPassword,
      });

      if (response.statusCode != 200) {
        throw Exception(response.data['message'] ?? 'Gagal mengubah password');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        final message = e.response!.data['message'] ?? 'Password lama tidak sesuai';
        throw Exception(message);
      }
      throw Exception('Gagal mengubah password: ${e.message}');
    }
  }

  /// Fetch list of users for device management
  Future<Map<String, dynamic>> getAdminUsersList({String search = ''}) async {
    try {
      final response = await _apiClient.dio.get(
        '/admin/users',
        queryParameters: {'search': search},
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Gagal mengambil daftar pengguna');
    } catch (e) {
      throw Exception('Gagal mengambil data user: $e');
    }
  }

  /// Reset device lock for a user
  Future<void> resetUserDevice(int userId) async {
    try {
      final response = await _apiClient.dio.post('/admin/users/$userId/reset-device');
      if (response.statusCode != 200) {
        throw Exception(response.data['message'] ?? 'Gagal membuka kunci perangkat');
      }
    } catch (e) {
      throw Exception('Gagal membuka kunci perangkat: $e');
    }
  }

  /// Activate / deactivate a requester account.
  Future<Map<String, dynamic>> updateUserStatus(int userId, bool isActive) async {
    try {
      final response = await _apiClient.dio.patch(
        '/admin/users/$userId/status',
        data: {'is_active': isActive},
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'Status akun diperbarui',
          'data': response.data['data'],
        };
      }
      throw Exception(response.data['message'] ?? 'Gagal memperbarui status akun');
    } on DioException catch (e) {
      return {
        'success': false,
        'message': e.response?.data?['message'] ?? e.error?.toString() ?? 'Gagal memperbarui status akun',
      };
    } catch (e) {
      return {'success': false, 'message': 'Gagal memperbarui status akun: $e'};
    }
  }

  /// Toggle device lock setting
  Future<bool> toggleDeviceLockSetting(bool enabled) async {
    try {
      final response = await _apiClient.dio.post(
        '/admin/settings/device-lock',
        data: {'enabled': enabled},
      );
      return response.data['enabled'] ?? enabled;
    } catch (e) {
      throw Exception('Gagal mengubah pengaturan kunci perangkat: $e');
    }
  }

  /// Request password reset link for user/admin email or username
  Future<Map<String, dynamic>> forgotPassword(String identifier, {bool isAdmin = false}) async {
    try {
      final response = await _apiClient.dio.post('/forgot-password', data: {
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

  /// Send message to admin
  Future<Map<String, dynamic>> contactAdmin({
    required String message,
    String? subject,
    String? email,
    String? name,
  }) async {
    try {
      final response = await _apiClient.dio.post('/contact-admin', data: {
        'message': message,
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (email != null && email.isNotEmpty) 'email': email,
        if (name != null && name.isNotEmpty) 'name': name,
      });
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
}
