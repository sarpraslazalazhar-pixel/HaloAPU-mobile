import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/cache_service.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:halo_apu_mobile/data/api/api_client.dart';
import 'package:halo_apu_mobile/data/repositories/csat_repository.dart';
import 'package:halo_apu_mobile/data/repositories/dashboard_repository.dart';
import 'package:halo_apu_mobile/data/repositories/ticket_repository.dart';
import 'package:hive/hive.dart';

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

class _Status401Adapter implements HttpClientAdapter {
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

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _InMemorySecureStorage fakeStorage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('halo_apu_401_test_');
    Hive.init(tempDir.path);
    await CacheService.init();

    fakeStorage = _InMemorySecureStorage();
    SafeSecureStorage.setStorageForTesting(fakeStorage);
    SessionManager.instance.resetForTest();
    SessionManager.instance.onNavigateToLogin = () {};
  });

  tearDown(() async {
    SessionManager.instance.resetForTest();
    SafeSecureStorage.clearMemoryCacheForTesting();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('DashboardRepository does not return stale cache on HTTP 401', () async {
    await SafeSecureStorage.write('auth_token', 'tok_1');
    await SafeSecureStorage.write(
      'dashboard_cache',
      '{"stats":{"menunggu":9,"diproses":0,"selesai":0,"ditolak":0,"aktif":9},"recentTickets":[]}',
    );

    final client = ApiClient();
    client.dio.httpClientAdapter = _Status401Adapter();
    final repo = DashboardRepository(client);

    final result = await repo.getDashboardData();

    expect(result['success'], isFalse);
    expect(result['statusCode'], 401);
    expect(result['isOffline'], isFalse);
    expect((result['stats'] as Map)['menunggu'], 0);
    expect(fakeStorage.store['dashboard_cache'], isNull);
  });

  test('TicketRepository rethrows 401 instead of returning stale cache', () async {
    await SafeSecureStorage.write('auth_token', 'tok_1');
    await CacheService.put(
      CacheService.ticketListKey(page: 1),
      [
        {
          'id': '1',
          'title': 'Stale Ticket',
          'category': 'IT',
          'status': 'open',
          'created_at': '2026-11-01T00:00:00Z',
          'requester_name': 'User',
          'description': 'Desc',
        },
      ],
      ttlSeconds: 300,
    );

    final client = ApiClient();
    client.dio.httpClientAdapter = _Status401Adapter();
    final repo = TicketRepository(client);

    await expectLater(
      repo.getTickets(),
      throwsA(
        isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('CsatRepository rethrows 401 instead of swallowing it as empty list', () async {
    await SafeSecureStorage.write('auth_token', 'tok_1');
    final client = ApiClient();
    client.dio.httpClientAdapter = _Status401Adapter();
    final repo = CsatRepository(client);

    await expectLater(
      repo.getCsatHistory(),
      throwsA(
        isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401),
      ),
    );
    await expectLater(
      repo.getPendingCsat(),
      throwsA(
        isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401),
      ),
    );
  });
}
