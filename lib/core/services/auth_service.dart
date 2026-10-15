import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:halo_apu_mobile/core/config/api_config.dart';
import 'package:halo_apu_mobile/core/services/device_service.dart';
import 'package:halo_apu_mobile/core/services/biometric_service.dart';

class AuthService {
  Dio get _dio => Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  ));

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> login(String email, String password, bool isAdmin) async {
    try {
      final deviceId = await DeviceService.getDeviceId();
      final deviceName = await DeviceService.getDeviceName();
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
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

        // Simpan token & user info di secure storage untuk persistensi sesi
        await _storage.write(key: 'auth_token', value: token);
        await _storage.write(key: 'user_data', value: userDataJson);
        await _storage.write(key: 'user_role', value: role);

        // Jika biometrik diaktifkan, simpan kredensial terenkripsi untuk 1-touch login
        final biometricService = BiometricService();
        if (await biometricService.isEnabled()) {
          await biometricService.saveBiometricCredentials(
            email: email,
            password: password,
            name: name,
            role: role,
          );
        }

        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login gagal'};
      }
    } on DioException catch (e) {
      if (e.response?.data != null && e.response?.data is Map && e.response?.data['message'] != null) {
        return {
          'success': false,
          'message': e.response?.data['message'],
          'error_code': e.response?.data['error_code'],
        };
      }
      
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        return {
          'success': false,
          'message': 'Koneksi timeout ke ${ApiConfig.baseUrl}. Periksa jaringan atau setting Host.'
        };
      }
      
      return {
        'success': false,
        'message': 'Gagal terhubung ke ${ApiConfig.baseUrl}. Pastikan server aktif & satu jaringan.'
      };
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan: $e'};
    }
  }

  Future<void> logout() async {
    try {
      final token = await _storage.read(key: 'auth_token');

      if (token != null) {
        await _dio.post(
          '/logout',
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
            },
          ),
        );
      }
    } catch (_) {
      // Abaikan jika token gagal di-revoke di server saat offline
    } finally {
      // Hanya hapus sesi user, pertahankan device_id dan biometric setting
      await _storage.delete(key: 'auth_token');
      await _storage.delete(key: 'user_data');
      await _storage.delete(key: 'user_role');
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await _dio.post('/forgot-password', data: {'email': email});
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
      final token = await _storage.read(key: 'auth_token');
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
      final token = await _storage.read(key: 'auth_token');
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
        await _storage.write(key: 'user_data', value: jsonEncode(userData));
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
