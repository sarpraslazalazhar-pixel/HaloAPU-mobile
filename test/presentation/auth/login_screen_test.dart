import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:halo_apu_mobile/presentation/auth/login_screen.dart';
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SafeSecureStorage.setStorageForTesting(_InMemorySecureStorage());
    SessionManager.instance.resetForTest();
  });

  tearDown(() {
    SessionManager.instance.resetForTest();
    SafeSecureStorage.clearMemoryCacheForTesting();
  });

  testWidgets('LoginScreen displays and dismisses pending session message banner', (tester) async {
    await SessionManager.instance.handleSessionExpired(
      reason: 'Sesi Anda telah berakhir. Silakan login kembali.',
      navigate: false,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Sesi Anda telah berakhir. Silakan login kembali.'),
      findsOneWidget,
    );
    expect(SessionManager.instance.pendingSessionMessage, isNull);

    await tester.tap(find.byTooltip('Tutup'));
    await tester.pump();

    expect(
      find.text('Sesi Anda telah berakhir. Silakan login kembali.'),
      findsNothing,
    );
  });

  testWidgets('LoginScreen shows inline validation error for empty fields', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Login sebagai User'));
    await tester.tap(find.text('Login sebagai User'));
    await tester.pump();

    expect(
      find.text('Email/Username dan Password tidak boleh kosong'),
      findsOneWidget,
    );
  });
}
