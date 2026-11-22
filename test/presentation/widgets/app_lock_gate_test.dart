import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_lock_gate.dart';

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
    SafeSecureStorage.setStorageForTesting(_InMemorySecureStorage());
    SessionManager.instance.resetForTest();
  });

  tearDown(() {
    SessionManager.instance.resetForTest();
    SafeSecureStorage.clearMemoryCacheForTesting();
  });
  Widget buildTestApp({
    required Future<bool> Function() isBiometricEnabled,
    required Future<bool> Function() canAuthenticate,
    required Future<bool> Function() hasActiveSession,
    required Future<bool> Function() authenticate,
    Future<void> Function()? onLogout,
    bool Function()? isAuthenticatingNow,
  }) {
    return MaterialApp(
      home: AppLockGate(
        isBiometricEnabled: isBiometricEnabled,
        canAuthenticate: canAuthenticate,
        hasActiveSession: hasActiveSession,
        authenticate: authenticate,
        onLogout: onLogout,
        isAuthenticatingNow: isAuthenticatingNow,
        child: const Scaffold(
          body: Center(child: Text('Dashboard Content')),
        ),
      ),
    );
  }

  testWidgets('locks on cold start when enabled with active session and unlocks on success', (tester) async {
    final authCompleter = Completer<bool>();
    var authCalls = 0;

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => true,
        canAuthenticate: () async => true,
        hasActiveSession: () async => true,
        authenticate: () {
          authCalls++;
          return authCompleter.future;
        },
        isAuthenticatingNow: () => false,
      ),
    );

    await tester.pump();
    expect(authCalls, 1);
    expect(find.text('Halo APU Terkunci'), findsOneWidget);

    authCompleter.complete(true);
    await tester.pumpAndSettle();

    expect(find.text('Halo APU Terkunci'), findsNothing);
    expect(find.text('Dashboard Content'), findsOneWidget);
  });

  testWidgets('does not lock when biometric is disabled or session is inactive', (tester) async {
    var authCalls = 0;

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => false,
        canAuthenticate: () async => true,
        hasActiveSession: () async => true,
        authenticate: () async {
          authCalls++;
          return true;
        },
        isAuthenticatingNow: () => false,
      ),
    );

    await tester.pumpAndSettle();
    expect(authCalls, 0);
    expect(find.text('Halo APU Terkunci'), findsNothing);

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => true,
        canAuthenticate: () async => true,
        hasActiveSession: () async => false,
        authenticate: () async {
          authCalls++;
          return true;
        },
        isAuthenticatingNow: () => false,
      ),
    );

    await tester.pumpAndSettle();
    expect(authCalls, 0);
    expect(find.text('Halo APU Terkunci'), findsNothing);
  });

  testWidgets('locks on pause -> resume and skips re-lock when external auth is active', (tester) async {
    var enabled = false;
    var externalAuthActive = false;
    var authResult = true;
    var authCalls = 0;

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => enabled,
        canAuthenticate: () async => true,
        hasActiveSession: () async => true,
        authenticate: () async {
          authCalls++;
          return authResult;
        },
        isAuthenticatingNow: () => externalAuthActive,
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Halo APU Terkunci'), findsNothing);

    // Enable biometric while app is open, then simulate OS biometric prompt lifecycle
    enabled = true;
    externalAuthActive = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(authCalls, 0);
    expect(find.text('Halo APU Terkunci'), findsNothing);

    // Now simulate normal backgrounding and resuming
    externalAuthActive = false;
    authResult = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(authCalls, 1);
    expect(find.text('Halo APU Terkunci'), findsOneWidget);

    // Retry via Buka Kunci button
    authResult = true;
    await tester.tap(find.text('Buka Kunci'));
    await tester.pumpAndSettle();

    expect(authCalls, 2);
    expect(find.text('Halo APU Terkunci'), findsNothing);
  });

  testWidgets('logout escape hatch unlocks and invokes onLogout when auth fails', (tester) async {
    var loggedOut = false;

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => true,
        canAuthenticate: () async => true,
        hasActiveSession: () async => true,
        authenticate: () async => false,
        onLogout: () async {
          loggedOut = true;
        },
        isAuthenticatingNow: () => false,
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Halo APU Terkunci'), findsOneWidget);

    await tester.tap(find.text('Keluar ke Login'));
    await tester.pumpAndSettle();

    expect(loggedOut, isTrue);
    expect(find.text('Halo APU Terkunci'), findsNothing);
  });

  testWidgets('SessionManager expiry resets AppLockGate overlay immediately after navigation', (tester) async {
    var hasSession = true;
    var navigatedToLogin = false;

    SessionManager.instance.onNavigateToLogin = () {
      navigatedToLogin = true;
    };

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => true,
        canAuthenticate: () async => true,
        hasActiveSession: () async => hasSession,
        authenticate: () async => false,
        isAuthenticatingNow: () => false,
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Halo APU Terkunci'), findsOneWidget);

    hasSession = false;
    await SessionManager.instance.handleSessionExpired();

    // Navigation runs immediately, while AppLockGate remains covered until frame commits
    expect(navigatedToLogin, isTrue);
    expect(find.text('Halo APU Terkunci'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Halo APU Terkunci'), findsNothing);
    expect(find.text('Dashboard Content'), findsOneWidget);
  });

  testWidgets('does not re-lock on resume when session has become inactive', (tester) async {
    var hasSession = true;
    var authCalls = 0;

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => true,
        canAuthenticate: () async => true,
        hasActiveSession: () async => hasSession,
        authenticate: () async {
          authCalls++;
          return true;
        },
        isAuthenticatingNow: () => false,
      ),
    );

    await tester.pumpAndSettle();
    expect(authCalls, 1);
    expect(find.text('Halo APU Terkunci'), findsNothing);

    // Session cleared while app goes to background
    hasSession = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(authCalls, 1);
    expect(find.text('Halo APU Terkunci'), findsNothing);
  });

  testWidgets('logout button prevents duplicate calls while logout is in flight', (tester) async {
    final logoutCompleter = Completer<void>();
    var logoutCalls = 0;

    await tester.pumpWidget(
      buildTestApp(
        isBiometricEnabled: () async => true,
        canAuthenticate: () async => true,
        hasActiveSession: () async => true,
        authenticate: () async => false,
        onLogout: () {
          logoutCalls++;
          return logoutCompleter.future;
        },
        isAuthenticatingNow: () => false,
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Keluar ke Login'), findsOneWidget);

    await tester.tap(find.text('Keluar ke Login'));
    await tester.pump();
    expect(find.text('Keluar...'), findsOneWidget);

    // Tap again while in progress - should be ignored
    await tester.tap(find.text('Keluar...'));
    await tester.pump();
    expect(logoutCalls, 1);

    logoutCompleter.complete();
    await tester.pumpAndSettle();
    expect(find.text('Halo APU Terkunci'), findsNothing);
  });
}
