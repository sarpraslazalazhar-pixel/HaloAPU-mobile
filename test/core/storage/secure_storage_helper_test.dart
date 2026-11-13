import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:halo_apu_mobile/data/api/api_client.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> store = {};
  int failReadsRemaining = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failReadsRemaining > 0) {
      failReadsRemaining--;
      throw Exception('Transient KeyStore failure');
    }
    return store[key];
  }

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

void main() {
  late _FakeSecureStorage fakeStorage;

  setUp(() {
    fakeStorage = _FakeSecureStorage();
    SafeSecureStorage.setStorageForTesting(fakeStorage);
  });

  tearDown(() {
    SafeSecureStorage.clearMemoryCacheForTesting();
  });

  test('SafeSecureStorage retries transient read failures and preserves session on clearSession', () async {
    await SafeSecureStorage.write('auth_token', 'tok_123');
    await SafeSecureStorage.write('user_role', 'user');
    await SafeSecureStorage.write('user_data', '{"name":"Budi"}');
    await SafeSecureStorage.write('app_device_hardware_id', 'AND_123456');

    // Simulate cold-start cache cleared + 1 transient KeyStore failure before succeeding
    SafeSecureStorage.clearMemoryCacheForTesting();
    fakeStorage.failReadsRemaining = 1;

    final token = await SafeSecureStorage.read('auth_token');
    expect(token, equals('tok_123'));

    // Subsequent read uses in-memory cache even if KeyStore errors
    fakeStorage.failReadsRemaining = 5;
    expect(await SafeSecureStorage.read('auth_token'), equals('tok_123'));

    // clearSession only deletes session keys, keeping device ID
    await SafeSecureStorage.clearSession();
    expect(await SafeSecureStorage.read('auth_token', bypassCache: true), isNull);
    expect(await SafeSecureStorage.read('user_role', bypassCache: true), isNull);
    expect(await SafeSecureStorage.read('user_data', bypassCache: true), isNull);
    expect(fakeStorage.store['app_device_hardware_id'], equals('AND_123456'));
  });

  test('ApiClient 401 interceptor ignores tokenless/stale requests and clears matching active token', () async {
    await SafeSecureStorage.write('auth_token', 'active_token');

    final client = ApiClient();
    client.dio.httpClientAdapter = _Mock401Adapter();

    // 1. Tokenless request returning 401 (simulated via explicit null/empty override) must not wipe active_token
    try {
      await client.dio.get(
        '/test-stale',
        options: Options(headers: {'Authorization': 'Bearer stale_token'}),
      );
    } on DioException catch (_) {}
    expect(await SafeSecureStorage.read('auth_token', bypassCache: true), equals('active_token'));

    // 2. Request with matching active_token returning 401 clears session
    try {
      await client.dio.get('/test-active');
    } on DioException catch (_) {}
    expect(await SafeSecureStorage.read('auth_token', bypassCache: true), isNull);
  });
}

class _Mock401Adapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"message":"Unauthenticated."}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
