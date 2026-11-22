import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';
import 'package:halo_apu_mobile/core/services/auth_service.dart';
import 'package:halo_apu_mobile/core/services/biometric_service.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.clear();
  }
}

class _StubAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemorySecureStorage fakeStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeStorage = _InMemorySecureStorage();
    SafeSecureStorage.setStorageForTesting(fakeStorage);
    AttachmentService.clearTokenCache();
    SessionManager.instance.resetForTest();
  });

  tearDown(() {
    SessionManager.instance.resetForTest();
    SafeSecureStorage.clearMemoryCacheForTesting();
    AttachmentService.clearTokenCache();
  });

  test('logout completes instantly even when server /logout hangs or fails', () async {
    await SafeSecureStorage.write('auth_token', 'tok_secret');
    await SafeSecureStorage.write('user_data', '{"name":"Andi"}');
    await SafeSecureStorage.write('user_role', 'user');
    await SafeSecureStorage.write('dashboard_cache', '{"stats":{}}');
    AttachmentService.setCachedToken('tok_secret');

    var invalidated = false;
    var lockReset = false;
    SessionManager.instance.notifyLoginSuccess();
    SessionManager.instance.onInvalidateProviders = () => invalidated = true;
    SessionManager.instance.onResetAppLock = () => lockReset = true;

    final serverCompleter = Completer<ResponseBody>();
    final requestStarted = Completer<void>();
    String? sentAuthHeader;
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = _StubAdapter((options) {
        sentAuthHeader = options.headers['Authorization']?.toString();
        if (!requestStarted.isCompleted) {
          requestStarted.complete();
        }
        return serverCompleter.future;
      });

    final authService = AuthService(
      dio: dio,
      fcmTokenProvider: () async => 'fcm_123',
      deviceIdProvider: () async => 'DEV-1',
      deviceNameProvider: () async => 'Pixel',
      biometricService: BiometricService(),
    );

    final sw = Stopwatch()..start();
    await authService.logout();
    sw.stop();

    expect(sw.elapsedMilliseconds, lessThan(500));
    expect(fakeStorage.store['auth_token'], isNull);
    expect(fakeStorage.store['user_data'], isNull);
    expect(fakeStorage.store['user_role'], isNull);
    expect(fakeStorage.store['dashboard_cache'], isNull);
    expect(AttachmentService.cachedToken, isNull);
    expect(SessionManager.instance.isAuthenticated, isFalse);
    expect(invalidated, isTrue);
    expect(lockReset, isTrue);

    // Wait for background /logout call to fire and verify Bearer token was sent
    await requestStarted.future.timeout(const Duration(seconds: 2));
    expect(sentAuthHeader, equals('Bearer tok_secret'));

    // Complete with error to ensure no unhandled exception escapes
    serverCompleter.completeError(
      DioException(
        requestOptions: RequestOptions(path: '/logout'),
        type: DioExceptionType.connectionError,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  });

  test('login parses 429 retry_after from JSON body and replaces generic message', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = _StubAdapter((_) async {
        return ResponseBody.fromString(
          '{"message":"Too Many Attempts.","retry_after":45}',
          429,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    final authService = AuthService(
      dio: dio,
      fcmTokenProvider: () async => null,
      deviceIdProvider: () async => 'DEV-1',
      deviceNameProvider: () async => 'Pixel',
      biometricService: BiometricService(),
    );

    final res = await authService.login('user@example.com', 'wrong', false);

    expect(res['success'], isFalse);
    expect(res['statusCode'], 429);
    expect(res['error_code'], 'RATE_LIMITED');
    expect(res['retry_after'], 45);
    expect(res['message'], contains('45 detik'));
  });

  test('login parses 429 Retry-After header when body omits retry_after and clamps minimum 1s', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = _StubAdapter((_) async {
        return ResponseBody.fromString(
          '{"message":"Terlalu banyak percobaan login."}',
          429,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            'retry-after': ['30'],
          },
        );
      });

    final authService = AuthService(
      dio: dio,
      fcmTokenProvider: () async => null,
      deviceIdProvider: () async => 'DEV-1',
      deviceNameProvider: () async => 'Pixel',
      biometricService: BiometricService(),
    );

    final res = await authService.login('user@example.com', 'wrong', false);

    expect(res['success'], isFalse);
    expect(res['statusCode'], 429);
    expect(res['error_code'], 'RATE_LIMITED');
    expect(res['retry_after'], 30);
    expect(res['message'], equals('Terlalu banyak percobaan login.'));

    // Test minimum clamp = 1
    final dioZero = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = _StubAdapter((_) async {
        return ResponseBody.fromString(
          '{"retry_after":0}',
          429,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final resZero = await AuthService(
      dio: dioZero,
      fcmTokenProvider: () async => null,
      deviceIdProvider: () async => 'DEV-1',
      deviceNameProvider: () async => 'Pixel',
      biometricService: BiometricService(),
    ).login('user@example.com', 'wrong', false);
    expect(resZero['retry_after'], 1);
  });

  test('login notifies SessionManager on 200 success and saves session', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = _StubAdapter((_) async {
        return ResponseBody.fromString(
          '{"data":{"token":"new_tok","role":"user","user":{"name":"Budi","username":"budi"}}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    await SessionManager.instance.handleSessionExpired(
      reason: 'Old session',
      navigate: false,
    );
    expect(SessionManager.instance.pendingSessionMessage, equals('Old session'));

    final authService = AuthService(
      dio: dio,
      fcmTokenProvider: () async => 'fcm_tok',
      deviceIdProvider: () async => 'DEV-1',
      deviceNameProvider: () async => 'Pixel',
      biometricService: BiometricService(),
    );

    final res = await authService.login('budi', 'secret', false);

    expect(res['success'], isTrue);
    expect(SessionManager.instance.isAuthenticated, isTrue);
    expect(SessionManager.instance.pendingSessionMessage, isNull);
    expect(fakeStorage.store['auth_token'], equals('new_tok'));
    expect(AttachmentService.cachedToken, equals('new_tok'));
  });

  test('switching accounts disables biometric and clears previous user credentials instead of overwriting with new user password', () async {
    final biometricService = BiometricService();
    await biometricService.setEnabled(true);
    await biometricService.saveBiometricCredentials(
      email: 'usera@example.com',
      password: 'passwordA',
      name: 'User A',
      role: 'user',
    );

    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = _StubAdapter((_) async {
        return ResponseBody.fromString(
          '{"data":{"token":"tok_b","role":"user","user":{"name":"User B","username":"userb"}}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    final authService = AuthService(
      dio: dio,
      fcmTokenProvider: () async => null,
      deviceIdProvider: () async => 'DEV-1',
      deviceNameProvider: () async => 'Pixel',
      biometricService: biometricService,
    );

    // User B logs in manually
    final res = await authService.login('userb@example.com', 'passwordB', false);
    expect(res['success'], isTrue);

    // Biometric must be disabled and User A's credentials cleared; User B's password MUST NOT be stored
    expect(await biometricService.isEnabled(), isFalse);
    expect(await biometricService.getSavedBiometricUser(), isNull);
    expect(await biometricService.getBiometricCredentials(), isNull);
    expect(fakeStorage.store['biometric_user_email'], isNull);
    expect(fakeStorage.store['biometric_user_password'], isNull);
  });

  test('logging in with the same account updates biometric credentials when biometric is enabled', () async {
    final biometricService = BiometricService();
    await biometricService.setEnabled(true);
    await biometricService.saveBiometricCredentials(
      email: 'usera@example.com',
      password: 'oldPassword',
      name: 'User A',
      role: 'user',
    );

    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = _StubAdapter((_) async {
        return ResponseBody.fromString(
          '{"data":{"token":"tok_a2","role":"user","user":{"name":"User A Updated","username":"usera"}}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    final authService = AuthService(
      dio: dio,
      fcmTokenProvider: () async => null,
      deviceIdProvider: () async => 'DEV-1',
      deviceNameProvider: () async => 'Pixel',
      biometricService: biometricService,
    );

    final res = await authService.login('UserA@example.com', 'newPassword', false);
    expect(res['success'], isTrue);

    expect(await biometricService.isEnabled(), isTrue);
    final creds = await biometricService.getBiometricCredentials();
    expect(creds?['email'], equals('UserA@example.com'));
    expect(creds?['password'], equals('newPassword'));
    expect(creds?['name'], equals('User A Updated'));
  });
}
