import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/core/services/app_update_service.dart';
import 'package:halo_apu_mobile/core/services/permission_service.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:halo_apu_mobile/core/storage/secure_storage_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const workerChannel = MethodChannel('id.haloapu.mobile/background_worker');
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late Map<String, String> memorySecureStorage;
  late List<MethodCall> recordedWorkerCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    memorySecureStorage = <String, String>{};
    recordedWorkerCalls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = Map<String, dynamic>.from(
        (call.arguments as Map?) ?? const {},
      );
      final key = args['key']?.toString();
      switch (call.method) {
        case 'read':
          return key == null ? null : memorySecureStorage[key];
        case 'write':
          if (key != null) {
            memorySecureStorage[key] = args['value']?.toString() ?? '';
          }
          return null;
        case 'delete':
          if (key != null) memorySecureStorage.remove(key);
          return null;
        case 'deleteAll':
          memorySecureStorage.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(memorySecureStorage);
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(workerChannel, (call) async {
      recordedWorkerCalls.add(call);
      switch (call.method) {
        case 'configureWorker':
        case 'scheduleQuickCheck':
        case 'markNotificationSeen':
        case 'clearWorker':
        case 'openBatteryOptimizationSettings':
          return true;
        case 'getSeenNotificationIds':
          return <String>[];
        case 'consumeLaunchPayload':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    PushNotificationService.requestLocalPermissionOverride = null;
    PushNotificationService.areLocalNotificationsEnabledOverride = null;
    PermissionService.fcmRequestPermissionOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(workerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('deduplication ring-buffer retains strictly latest 50 notification IDs', () async {
    final prefs = await SharedPreferences.getInstance();

    for (var i = 1; i <= 55; i++) {
      await PushNotificationService.recordSeenNotificationId(
        'uuid-$i',
        prefs: prefs,
        syncNative: false,
      );
    }

    final stored =
        prefs.getStringList(PushNotificationService.notifiedIdsPrefsKey) ?? [];
    expect(stored.length, equals(50));
    expect(await PushNotificationService.hasSeenNotificationId('uuid-1', prefs: prefs), isFalse);
    expect(await PushNotificationService.hasSeenNotificationId('uuid-5', prefs: prefs), isFalse);
    expect(await PushNotificationService.hasSeenNotificationId('uuid-6', prefs: prefs), isTrue);
    expect(await PushNotificationService.hasSeenNotificationId('uuid-55', prefs: prefs), isTrue);

    // Recording an existing ID moves it to the end without increasing length
    await PushNotificationService.recordSeenNotificationId(
      'uuid-10',
      prefs: prefs,
      syncNative: false,
    );
    final updated =
        prefs.getStringList(PushNotificationService.notifiedIdsPrefsKey) ?? [];
    expect(updated.length, equals(50));
    expect(updated.last, equals('uuid-10'));
  });

  test('detects placeholder Firebase credentials vs valid production credentials', () {
    expect(
      PushNotificationService.isPlaceholderOptions(
        projectId: 'haloapu-dev',
        apiKey: 'fake_api_key_for_dev',
        appId: '1:123456789012:android:abcdef1234567890',
      ),
      isTrue,
    );
    expect(
      PushNotificationService.isPlaceholderOptions(
        projectId: 'halo-apu-prod',
        apiKey: 'AIzaSyRealValidKeyExample123456',
        appId: '1:987654321098:android:9988776655443322',
      ),
      isFalse,
    );
    expect(PushNotificationService.isPlaceholderFirebaseConfig, isTrue);
  });

  test('PermissionService falls back to Android 13+ local notification permission when FCM throws', () async {
    PushNotificationService.requestLocalPermissionOverride = () async => true;
    PermissionService.fcmRequestPermissionOverride =
        () async => throw Exception('FIS_AUTH_ERROR: fake google-services');

    final granted = await PermissionService.requestNotificationPermission();
    expect(granted, isTrue);

    PushNotificationService.areLocalNotificationsEnabledOverride = () async => true;
    expect(await PermissionService.isNotificationPermissionGranted(), isTrue);

    PushNotificationService.areLocalNotificationsEnabledOverride = () async => false;
    expect(await PermissionService.isNotificationPermissionGranted(), isFalse);
  });

  test('MethodChannel bridge invokes configureWorker, markNotificationSeen, scheduleQuickCheck, clearWorker, and handles onNotificationTapped', () async {
    await SafeSecureStorage.write('auth_token', 'bearer-test-token');

    await PushNotificationService.recordSeenNotificationId('notif-seen-1');
    expect(
      recordedWorkerCalls.any(
        (c) =>
            c.method == 'markNotificationSeen' &&
            (c.arguments as Map)['id'] == 'notif-seen-1',
      ),
      isTrue,
    );

    final configured =
        await PushNotificationService.configureBackgroundWorker(baselineSet: true);
    expect(configured, isTrue);
    final configCall =
        recordedWorkerCalls.firstWhere((c) => c.method == 'configureWorker');
    final configArgs = Map<String, dynamic>.from(configCall.arguments as Map);
    expect(configArgs['authToken'], equals('bearer-test-token'));
    expect(configArgs['releaseChannel'], equals(FlavorConfig.releaseChannel));
    expect(configArgs['baselineSet'], isTrue);
    expect(configArgs['seenIds'], contains('notif-seen-1'));

    await PushNotificationService.onAppPaused();
    expect(
      recordedWorkerCalls.any((c) => c.method == 'scheduleQuickCheck'),
      isTrue,
    );

    // Simulate user tapping a WorkManager-created notification while app is running
    PushNotificationService.ensureWorkerHandlerForTest();
    final initialTrigger = AppUpdateService.notificationUpdateTrigger.value;
    final tapPayload = jsonEncode({
      'id': 'notif-tap-1',
      'type': 'app_update',
      'channel': FlavorConfig.releaseChannel,
      'version_name': '1.0.9',
      'build_number': '99',
    });
    final encodedCall = const StandardMethodCodec().encodeMethodCall(
      MethodCall('onNotificationTapped', tapPayload),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      workerChannel.name,
      encodedCall,
      (_) {},
    );
    expect(
      AppUpdateService.notificationUpdateTrigger.value,
      equals(initialTrigger + 1),
    );

    // Logout / stopRealtimePoller clears worker and seen IDs
    PushNotificationService.stopRealtimePoller();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      recordedWorkerCalls.any((c) => c.method == 'clearWorker'),
      isTrue,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList(PushNotificationService.notifiedIdsPrefsKey),
      isNull,
    );
  });
}
