import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';
import 'package:halo_apu_mobile/core/services/pending_ticket_service.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemorySecureStorage fakeStorage;

  setUp(() {
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

  test('isAuthEndpoint identifies public auth endpoints accurately', () {
    expect(SessionManager.isAuthEndpoint('/login'), isTrue);
    expect(SessionManager.isAuthEndpoint('login'), isTrue);
    expect(SessionManager.isAuthEndpoint('/api/login'), isTrue);
    expect(
      SessionManager.isAuthEndpoint('https://dev.haloapu.id/api/login?foo=1'),
      isTrue,
    );
    expect(SessionManager.isAuthEndpoint('/forgot-password'), isTrue);
    expect(SessionManager.isAuthEndpoint('/api/contact-admin'), isTrue);

    expect(SessionManager.isAuthEndpoint('/tickets'), isFalse);
    expect(SessionManager.isAuthEndpoint('/user'), isFalse);
    expect(SessionManager.isAuthEndpoint('/dashboard'), isFalse);
    expect(SessionManager.isAuthEndpoint('/login-history'), isFalse);
    expect(SessionManager.isAuthEndpoint(''), isFalse);
  });

  test('handleSessionExpired enforces security ordering, clears session incl. dashboard_cache, and deduplicates parallel calls', () async {
    await SafeSecureStorage.write('auth_token', 'tok_abc');
    await SafeSecureStorage.write('user_data', '{"name":"Siti"}');
    await SafeSecureStorage.write('user_role', 'user');
    await SafeSecureStorage.write('dashboard_cache', '{"stats":{}}');
    await SafeSecureStorage.write('app_device_hardware_id', 'DEV-99');
    AttachmentService.setCachedToken('tok_abc');

    final events = <String>[];
    var listenerNotifications = 0;

    SessionManager.instance.notifyLoginSuccess();
    expect(SessionManager.instance.isAuthenticated, isTrue);

    SessionManager.instance.addListener(() {
      listenerNotifications++;
      events.add('notifyListeners');
    });
    SessionManager.instance.onInvalidateProviders = () {
      events.add('invalidateProviders');
    };
    SessionManager.instance.onNavigateToLogin = () {
      events.add('navigateToLogin');
    };
    SessionManager.instance.onResetAppLock = () {
      events.add('resetAppLock');
    };

    // Trigger multiple concurrent 401 expiry calls
    await Future.wait([
      SessionManager.instance.handleSessionExpired(reason: '  Akun dinonaktifkan  '),
      SessionManager.instance.handleSessionExpired(reason: 'Pesan kedua'),
      SessionManager.instance.handleSessionExpired(),
    ]);

    expect(SessionManager.instance.isAuthenticated, isFalse);
    expect(SessionManager.instance.isHandlingExpiry, isFalse);
    expect(listenerNotifications, 1);

    // Wajib: onResetAppLock dipanggil SETELAH invalidateProviders, notifyListeners, dan navigateToLogin
    expect(
      events,
      equals([
        'invalidateProviders',
        'notifyListeners',
        'navigateToLogin',
        'resetAppLock',
      ]),
    );

    // Session & dashboard_cache cleared, device ID preserved
    expect(fakeStorage.store['auth_token'], isNull);
    expect(fakeStorage.store['user_data'], isNull);
    expect(fakeStorage.store['user_role'], isNull);
    expect(fakeStorage.store['dashboard_cache'], isNull);
    expect(fakeStorage.store['app_device_hardware_id'], equals('DEV-99'));
    expect(AttachmentService.cachedToken, isNull);

    // Pending message consumed once
    expect(
      SessionManager.instance.consumeSessionMessage(),
      equals('Akun dinonaktifkan'),
    );
    expect(SessionManager.instance.consumeSessionMessage(), isNull);
  });

  test('handleSessionExpired with navigate: false skips navigation and uses default message when reason is empty', () async {
    var navigated = false;
    var lockReset = false;
    SessionManager.instance.onNavigateToLogin = () => navigated = true;
    SessionManager.instance.onResetAppLock = () => lockReset = true;

    await SessionManager.instance.handleSessionExpired(reason: '   ', navigate: false);

    expect(navigated, isFalse);
    expect(lockReset, isTrue);
    expect(
      SessionManager.instance.consumeSessionMessage(),
      equals(SessionManager.defaultExpiredMessage),
    );
  });

  test('forceReLogin clears local session, optionally sets reason, navigates, and resets lock', () async {
    await SafeSecureStorage.write('auth_token', 'tok_xyz');
    await SafeSecureStorage.write('dashboard_cache', '{"stats":{}}');
    AttachmentService.setCachedToken('tok_xyz');

    final events = <String>[];
    SessionManager.instance.onInvalidateProviders = () => events.add('invalidate');
    SessionManager.instance.onNavigateToLogin = () => events.add('navigate');
    SessionManager.instance.onResetAppLock = () => events.add('resetLock');

    await SessionManager.instance.forceReLogin(reason: 'Silakan masuk ulang');

    expect(SessionManager.instance.isAuthenticated, isFalse);
    expect(fakeStorage.store['auth_token'], isNull);
    expect(fakeStorage.store['dashboard_cache'], isNull);
    expect(AttachmentService.cachedToken, isNull);
    expect(events, equals(['invalidate', 'navigate', 'resetLock']));
    expect(SessionManager.instance.consumeSessionMessage(), equals('Silakan masuk ulang'));
  });

  test('markLoggedOut clears session and pending message without navigating', () async {
    await SafeSecureStorage.write('auth_token', 'tok_log');
    await SafeSecureStorage.write('dashboard_cache', '{"stats":{}}');
    AttachmentService.setCachedToken('tok_log');

    var navigated = false;
    var invalidated = false;
    var lockReset = false;

    SessionManager.instance.onNavigateToLogin = () => navigated = true;
    SessionManager.instance.onInvalidateProviders = () => invalidated = true;
    SessionManager.instance.onResetAppLock = () => lockReset = true;

    await SessionManager.instance.handleSessionExpired(reason: 'Expired', navigate: false);
    SessionManager.instance.notifyLoginSuccess();
    expect(SessionManager.instance.pendingSessionMessage, isNull);

    await SessionManager.instance.markLoggedOut();

    expect(SessionManager.instance.isAuthenticated, isFalse);
    expect(SessionManager.instance.pendingSessionMessage, isNull);
    expect(fakeStorage.store['auth_token'], isNull);
    expect(fakeStorage.store['dashboard_cache'], isNull);
    expect(AttachmentService.cachedToken, isNull);
    expect(navigated, isFalse);
    expect(invalidated, isTrue);
    expect(lockReset, isTrue);
  });

  test('handleSessionExpired and markLoggedOut clear ticket_drafts and pending_tickets Hive boxes', () async {
    final tempDir = await Directory.systemTemp.createTemp('halo_apu_sm_hive_');
    addTearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Hive.init(tempDir.path);
    final draftsBox = await Hive.openBox('ticket_drafts');
    final pendingBox = await Hive.openBox(PendingTicketService.boxName);
    await draftsBox.put('draft_1', {'title': 'Rahasia User A'});
    await pendingBox.put('pending_1', {'sub_unit_id': 1, 'form_data': {'desc': 'Secret'}});

    await SessionManager.instance.handleSessionExpired(navigate: false);

    expect(draftsBox.isEmpty, isTrue);
    expect(pendingBox.isEmpty, isTrue);

    await draftsBox.put('draft_2', {'title': 'Draft 2'});
    await pendingBox.put('pending_2', {'sub_unit_id': 2});

    await SessionManager.instance.markLoggedOut();

    expect(draftsBox.isEmpty, isTrue);
    expect(pendingBox.isEmpty, isTrue);
  });

  test('forceReLogin awaits active handleSessionExpired without double-clear or double-navigate', () async {
    final deleteStarted = Completer<void>();
    final allowDeleteFinish = Completer<void>();
    final slowStorage = _SlowDeleteSecureStorage(
      onFirstDelete: () {
        if (!deleteStarted.isCompleted) deleteStarted.complete();
        return allowDeleteFinish.future;
      },
    );
    SafeSecureStorage.setStorageForTesting(slowStorage);

    var navigateCount = 0;
    var invalidateCount = 0;
    var lockResetCount = 0;
    SessionManager.instance.onNavigateToLogin = () => navigateCount++;
    SessionManager.instance.onInvalidateProviders = () => invalidateCount++;
    SessionManager.instance.onResetAppLock = () => lockResetCount++;

    final expiryFuture = SessionManager.instance.handleSessionExpired(reason: '401');
    await deleteStarted.future;

    // Concurrent forceReLogin while expiry transition is mid-flight
    final forceFuture = SessionManager.instance.forceReLogin(reason: 'Manual');

    allowDeleteFinish.complete();
    await Future.wait([expiryFuture, forceFuture]);

    expect(navigateCount, 1);
    expect(invalidateCount, 1);
    expect(lockResetCount, 1);
  });
}

class _SlowDeleteSecureStorage extends _InMemorySecureStorage {
  final Future<void> Function() onFirstDelete;
  bool _called = false;

  _SlowDeleteSecureStorage({required this.onFirstDelete});

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
    if (!_called) {
      _called = true;
      await onFirstDelete();
    }
    await super.delete(key: key);
  }
}
