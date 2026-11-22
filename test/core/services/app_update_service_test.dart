import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/core/services/app_update_service.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:halo_apu_mobile/domain/models/app_release_model.dart';
import 'package:halo_apu_mobile/domain/models/notification_model.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QueueAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _QueueAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

PackageInfo _mockPackageInfo({String version = '1.0.1', int buildNumber = 12}) {
  return PackageInfo(
    appName: 'Halo APU',
    packageName: 'id.haloapu.mobile.staging',
    version: version,
    buildNumber: buildNumber.toString(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('halo_apu_update_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('isAllowedDownloadUrl enforces HTTPS, no userinfo, and strict host allowlist', () {
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('https://github.com/org/repo/releases/download/v1.0.2/app.apk'),
      ),
      isTrue,
    );
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('https://objects.githubusercontent.com/github-production-release-asset/app.apk'),
      ),
      isTrue,
    );
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('https://release-assets.githubusercontent.com/file.apk'),
      ),
      isTrue,
    );
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('${FlavorConfig.webUrl}/downloads/haloapu.apk'),
      ),
      isTrue,
    );

    // Rejected URLs
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('http://github.com/org/repo/app.apk'),
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('https://user:pass@github.com/org/repo/app.apk'),
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('https://evil.com/app.apk'),
      ),
      isFalse,
    );
    expect(
      AppUpdateService.isAllowedDownloadUrl(
        Uri.parse('https://github.com.evil.com/app.apk'),
      ),
      isFalse,
    );
  });

  test('checkForUpdate compares buildNumber and always keeps updates optional (non-blocking)', () async {
    Future<AppUpdateCheckResult?> runCheck(Map<String, dynamic> releaseJson, {int currentBuild = 12}) async {
      final dio = Dio(BaseOptions(baseUrl: 'https://dev.haloapu.id/api'))
        ..httpClientAdapter = _QueueAdapter((_) async {
          return ResponseBody.fromString(
            jsonEncode({'data': releaseJson}),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        });
      final service = AppUpdateService(
        dio: dio,
        packageInfoProvider: () async => _mockPackageInfo(buildNumber: currentBuild),
        tempDirProvider: () async => tempDir,
        platformOverride: 'android',
        channelOverride: 'staging',
      );
      return service.checkForUpdate();
    }

    // Up-to-date (same build)
    final same = await runCheck({
      'id': 1,
      'platform': 'android',
      'channel': 'staging',
      'version_name': '1.0.1',
      'build_number': 12,
      'min_supported_build_number': 10,
      'force_update': false,
      'download_url': 'https://github.com/org/repo/app.apk',
    });
    expect(same?.hasUpdate, isFalse);
    expect(same?.isForceUpdate, isFalse);

    // Optional update
    final optional = await runCheck({
      'id': 2,
      'platform': 'android',
      'channel': 'staging',
      'version_name': '1.0.2',
      'build_number': 15,
      'min_supported_build_number': 10,
      'force_update': false,
      'download_url': 'https://github.com/org/repo/app.apk',
      'file_size_bytes': 29779558,
    });
    expect(optional?.hasUpdate, isTrue);
    expect(optional?.isForceUpdate, isFalse);
    expect(optional?.shouldPromptAutomatically, isTrue);
    expect(optional?.release?.formattedFileSize, equals('28.4 MB'));

    // Even if server sends legacy force_update: true or higher min_supported_build_number,
    // mobile never blocks the user (always optional).
    final legacyForceFlag = await runCheck({
      'id': 3,
      'platform': 'android',
      'channel': 'staging',
      'version_name': '1.0.2',
      'build_number': 15,
      'min_supported_build_number': 99,
      'force_update': true,
      'download_url': 'https://github.com/org/repo/app.apk',
    });
    expect(legacyForceFlag?.hasUpdate, isTrue);
    expect(legacyForceFlag?.isForceUpdate, isFalse);
  });

  test('dismissUpdate respects 24h cooldown for same build and resets for newer build or manual check', () async {
    var now = DateTime(2026, 11, 22, 8, 0);
    var remoteBuild = 15;

    final dio = Dio(BaseOptions(baseUrl: 'https://dev.haloapu.id/api'))
      ..httpClientAdapter = _QueueAdapter((_) async {
        return ResponseBody.fromString(
          jsonEncode({
            'data': {
              'id': 1,
              'platform': 'android',
              'channel': 'staging',
              'version_name': '1.0.2',
              'build_number': remoteBuild,
              'min_supported_build_number': 0,
              'force_update': false,
              'download_url': 'https://github.com/org/repo/app.apk',
            },
          }),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      });

    final service = AppUpdateService(
      dio: dio,
      packageInfoProvider: () async => _mockPackageInfo(buildNumber: 12),
      tempDirProvider: () async => tempDir,
      platformOverride: 'android',
      channelOverride: 'staging',
      nowProvider: () => now,
    );

    await service.dismissUpdate(15);

    // Same build within 24h -> hidden for auto check
    final within24h = await service.checkForUpdate(manual: false);
    expect(within24h?.shouldPromptAutomatically, isFalse);

    // Manual check ignores cooldown
    final manualCheck = await service.checkForUpdate(manual: true);
    expect(manualCheck?.shouldPromptAutomatically, isTrue);

    // Newer build (16) ignores dismiss for build 15
    remoteBuild = 16;
    final newerBuild = await service.checkForUpdate(manual: false);
    expect(newerBuild?.shouldPromptAutomatically, isTrue);
    remoteBuild = 15;

    // After 24h + 1 minute -> prompt again for build 15
    now = now.add(const Duration(hours: 24, minutes: 1));
    final after24h = await service.checkForUpdate(manual: false);
    expect(after24h?.shouldPromptAutomatically, isTrue);
  });

  test('checkForUpdate fails silently when auto and throws AppUpdateException when manual', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://dev.haloapu.id/api'))
      ..httpClientAdapter = _QueueAdapter((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

    final service = AppUpdateService(
      dio: dio,
      packageInfoProvider: () async => _mockPackageInfo(buildNumber: 12),
      tempDirProvider: () async => tempDir,
      platformOverride: 'android',
      channelOverride: 'staging',
    );

    expect(await service.checkForUpdate(manual: false), isNull);
    await expectLater(
      service.checkForUpdate(manual: true),
      throwsA(isA<AppUpdateException>()),
    );
  });

  test('downloadAndVerifyApk validates SHA-256 streaming, renames atomically, and rejects tampered files', () async {
    final validBytes = utf8.encode('FAKE-APK-BINARY-PAYLOAD-v1.0.2');
    final validSha = sha256.convert(validBytes).toString();
    var downloadCalls = 0;

    final dio = Dio()
      ..httpClientAdapter = _QueueAdapter((_) async {
        downloadCalls++;
        return ResponseBody.fromBytes(
          validBytes,
          200,
          headers: {
            Headers.contentLengthHeader: [validBytes.length.toString()],
          },
        );
      });

    final service = AppUpdateService(
      dio: dio,
      packageInfoProvider: () async => _mockPackageInfo(buildNumber: 12),
      tempDirProvider: () async => tempDir,
      platformOverride: 'android',
      channelOverride: 'staging',
    );

    final validRelease = AppReleaseModel(
      id: 1,
      platform: 'android',
      channel: 'staging',
      versionName: '1.0.2',
      buildNumber: 15,
      downloadUrl: 'https://github.com/org/repo/releases/download/v1.0.2/app.apk',
      sha256: validSha,
      fileSizeBytes: validBytes.length,
    );

    final apkPath = await service.downloadAndVerifyApk(validRelease);
    expect(apkPath, endsWith('haloapu-15.apk'));
    expect(await File(apkPath).exists(), isTrue);
    expect(await File('$apkPath.part').exists(), isFalse);
    expect(downloadCalls, 1);

    // Second call reuses verified cached APK without re-downloading
    final cachedPath = await service.downloadAndVerifyApk(validRelease);
    expect(cachedPath, equals(apkPath));
    expect(downloadCalls, 1);

    // Tampered file (wrong SHA-256) deletes .part and throws AppUpdateSecurityException
    final tamperedRelease = AppReleaseModel(
      id: 2,
      platform: 'android',
      channel: 'staging',
      versionName: '1.0.3',
      buildNumber: 16,
      downloadUrl: 'https://objects.githubusercontent.com/tampered.apk',
      sha256: '0' * 64,
    );

    await expectLater(
      service.downloadAndVerifyApk(tamperedRelease),
      throwsA(isA<AppUpdateSecurityException>()),
    );
    expect(
      await File('${tempDir.path}/updates/haloapu-16.apk').exists(),
      isFalse,
    );
    expect(
      await File('${tempDir.path}/updates/haloapu-16.apk.part').exists(),
      isFalse,
    );
  });

  test('downloadAndVerifyApk rejects disallowed redirect host and deletes partial file', () async {
    final payloadBytes = utf8.encode('APK-FROM-EVIL-REDIRECT');
    final payloadSha = sha256.convert(payloadBytes).toString();

    final dio = Dio()
      ..httpClientAdapter = _QueueAdapter((options) async {
        // Simulate Dio redirect tracking by pointing realUri to disallowed host
        return ResponseBody.fromBytes(payloadBytes, 200)
          ..redirects = [
            RedirectRecord(302, 'GET', Uri.parse('https://evil.com/malware.apk')),
          ];
      });

    final service = AppUpdateService(
      dio: dio,
      packageInfoProvider: () async => _mockPackageInfo(buildNumber: 12),
      tempDirProvider: () async => tempDir,
      platformOverride: 'android',
      channelOverride: 'staging',
    );

    final release = AppReleaseModel(
      id: 5,
      platform: 'android',
      channel: 'staging',
      versionName: '1.0.4',
      buildNumber: 18,
      downloadUrl: 'https://github.com/org/repo/releases/download/v1.0.4/app.apk',
      sha256: payloadSha,
    );

    await expectLater(
      service.downloadAndVerifyApk(release),
      throwsA(isA<AppUpdateSecurityException>()),
    );
    expect(
      await File('${tempDir.path}/updates/haloapu-18.apk').exists(),
      isFalse,
    );
    expect(
      await File('${tempDir.path}/updates/haloapu-18.apk.part').exists(),
      isFalse,
    );
  });

  test('cleanupOldApks removes old/partial files while keeping verified newer APK', () async {
    final updatesDir = Directory('${tempDir.path}/updates');
    await updatesDir.create(recursive: true);

    final oldApk = File('${updatesDir.path}/haloapu-10.apk')..writeAsStringSync('old');
    final currentApk = File('${updatesDir.path}/haloapu-12.apk')..writeAsStringSync('cur');
    final newerApk = File('${updatesDir.path}/haloapu-15.apk')..writeAsStringSync('new');
    final leftoverPart = File('${updatesDir.path}/haloapu-15.apk.part')..writeAsStringSync('part');

    final service = AppUpdateService(
      tempDirProvider: () async => tempDir,
    );

    await service.cleanupOldApks(currentBuildNumber: 12);

    expect(await oldApk.exists(), isFalse);
    expect(await currentApk.exists(), isFalse);
    expect(await leftoverPart.exists(), isFalse);
    expect(await newerApk.exists(), isTrue);
  });

  test('PushNotificationService.shouldIgnoreAppUpdatePayload isolates staging vs production channels', () {
    expect(
      PushNotificationService.shouldIgnoreAppUpdatePayload(
        {'type': 'app_update', 'channel': 'staging'},
        currentChannel: 'production',
      ),
      isTrue,
    );
    expect(
      PushNotificationService.shouldIgnoreAppUpdatePayload(
        {'type': 'app_update', 'channel': 'production'},
        currentChannel: 'staging',
      ),
      isTrue,
    );
    expect(
      PushNotificationService.shouldIgnoreAppUpdatePayload(
        {'type': 'app_update', 'channel': 'production'},
        currentChannel: 'production',
      ),
      isFalse,
    );
    expect(
      PushNotificationService.shouldIgnoreAppUpdatePayload(
        {'type': 'app_update'},
        currentChannel: 'production',
      ),
      isFalse,
    );
    expect(
      PushNotificationService.shouldIgnoreAppUpdatePayload(
        {'type': 'ticket', 'channel': 'staging'},
        currentChannel: 'production',
      ),
      isFalse,
    );
  });

  test('PushNotificationService.buildAlertFromNotificationJson extracts app_update payload and filters channel', () {
    // Flat app_update notification matching current channel
    final flatMatch = PushNotificationService.buildAlertFromNotificationJson(
      {
        'id': 'notif-1',
        'type': 'app_update',
        'title': 'Pembaruan Tersedia',
        'body': 'Halo APU v1.0.3 sudah rilis',
        'channel': 'staging',
        'version_name': '1.0.3',
        'build_number': 15,
      },
      currentChannel: 'staging',
    );
    expect(flatMatch, isNotNull);
    expect(flatMatch!.title, equals('Pembaruan Tersedia'));
    expect(flatMatch.body, equals('Halo APU v1.0.3 sudah rilis'));
    expect(flatMatch.data, equals({
      'type': 'app_update',
      'channel': 'staging',
      'version_name': '1.0.3',
      'build_number': '15',
      'id': 'notif-1',
    }));

    // Nested data['type'] == 'app_update' matching channel
    final nestedMatch = PushNotificationService.buildAlertFromNotificationJson(
      {
        'id': 'notif-2',
        'title': 'Update Produksi',
        'message': 'Segera perbarui ke v1.1.0',
        'data': {
          'type': 'app_update',
          'channel': 'production',
          'version_name': '1.1.0',
          'build_number': '20',
        },
      },
      currentChannel: 'production',
    );
    expect(nestedMatch, isNotNull);
    expect(nestedMatch!.data['type'], equals('app_update'));
    expect(nestedMatch.data['channel'], equals('production'));
    expect(nestedMatch.data['version_name'], equals('1.1.0'));
    expect(nestedMatch.data['build_number'], equals('20'));

    // Mismatched channel (production notif while running staging) -> ignored (null)
    final mismatched = PushNotificationService.buildAlertFromNotificationJson(
      {
        'id': 'notif-3',
        'type': 'app_update',
        'title': 'Update Produksi',
        'body': 'Rilis produksi',
        'channel': 'production',
        'version_name': '1.1.0',
        'build_number': 20,
      },
      currentChannel: 'staging',
    );
    expect(mismatched, isNull);

    // Regular ticket notification preserves ticket_id routing
    final ticketAlert = PushNotificationService.buildAlertFromNotificationJson(
      {
        'id': 'notif-4',
        'type': 'reply',
        'title': 'Balasan Baru',
        'body': 'Operator membalas tiket Anda',
        'ticketId': '123456789',
      },
      currentChannel: 'staging',
    );
    expect(ticketAlert, isNotNull);
    expect(ticketAlert!.data['type'], equals('reply'));
    expect(ticketAlert.data['ticket_id'], equals('123456789'));
    expect(ticketAlert.data['id'], equals('notif-4'));
  });

  test('PushNotificationService routes app_update tap payload to AppUpdateService trigger without ticket navigation', () async {
    final initialCount = AppUpdateService.notificationUpdateTrigger.value;

    // Matching channel (uses FlavorConfig.releaseChannel) increments trigger
    await PushNotificationService.handleNotificationDataForTest({
      'type': 'app_update',
      'channel': FlavorConfig.releaseChannel,
      'version_name': '1.0.5',
      'build_number': '25',
      'id': 'notif-update-1',
    });
    expect(
      AppUpdateService.notificationUpdateTrigger.value,
      equals(initialCount + 1),
    );

    // Different channel does NOT increment trigger
    final otherChannel =
        FlavorConfig.releaseChannel == 'production' ? 'staging' : 'production';
    await PushNotificationService.handleNotificationDataForTest({
      'type': 'app_update',
      'channel': otherChannel,
      'version_name': '1.0.5',
      'build_number': '25',
      'id': 'notif-update-2',
    });
    expect(
      AppUpdateService.notificationUpdateTrigger.value,
      equals(initialCount + 1),
    );
  });

  test('NotificationModel.safeFromJson parses app_update metadata and unknown types safely', () {
    final model = NotificationModel.safeFromJson({
      'id': 'n-100',
      'title': 'Update Aplikasi v1.0.4',
      'body': 'Perbaikan stabilitas dan notifikasi.',
      'type': 'app_update',
      'createdAt': '2026-11-22T11:00:00Z',
      'isRead': false,
      'data': {
        'channel': 'staging',
        'version_name': '1.0.4',
        'build_number': '18',
      },
    });

    expect(model.type, equals(NotificationType.appUpdate));
    expect(model.channel, equals('staging'));
    expect(model.versionName, equals('1.0.4'));
    expect(model.buildNumber, equals(18));
    expect(model.isRead, isFalse);

    final unknownTypeModel = NotificationModel.safeFromJson({
      'id': 'n-101',
      'title': 'Lainnya',
      'body': 'Info baru',
      'type': 'future_unknown_type',
      'created_at': '2026-11-22T11:00:00Z',
      'is_read': true,
    });
    expect(unknownTypeModel.type, equals(NotificationType.ticket));
    expect(unknownTypeModel.isRead, isTrue);
  });
}
