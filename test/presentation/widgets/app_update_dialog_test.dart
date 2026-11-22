import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/app_update_service.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_update_dialog.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _StubAdapter(this.handler);

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

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppUpdateDialog.resetDialogGuardForTest();
    tempDir = await Directory.systemTemp.createTemp('halo_apu_dialog_test_');
  });

  tearDown(() async {
    AppUpdateDialog.resetDialogGuardForTest();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  AppUpdateService createService({
    required Map<String, dynamic>? releaseJson,
    List<int>? apkBytes,
    Future<OpenResult> Function(String path)? onInstall,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://dev.haloapu.id/api'))
      ..httpClientAdapter = _StubAdapter((options) async {
        if (options.path.contains('/app-version')) {
          return ResponseBody.fromString(
            jsonEncode({'data': releaseJson}),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        final bytes = apkBytes ?? utf8.encode('APK-BYTES');
        return ResponseBody.fromBytes(
          bytes,
          200,
          headers: {
            Headers.contentLengthHeader: [bytes.length.toString()],
          },
        );
      });

    return AppUpdateService(
      dio: dio,
      packageInfoProvider: () async => PackageInfo(
        appName: 'Halo APU',
        packageName: 'id.haloapu.mobile.staging',
        version: '1.0.1',
        buildNumber: '12',
      ),
      tempDirProvider: () async => tempDir,
      platformOverride: 'android',
      channelOverride: 'staging',
      openInstaller: onInstall ??
          (_) async => OpenResult(type: ResultType.done, message: 'done'),
      urlLauncher: (_) async => true,
    );
  }

  /// Advances real async I/O (dart:io Directory/File & sha256 stream) then pumps frames.
  Future<void> pumpRealAsync(WidgetTester tester, {Finder? untilFound}) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (untilFound != null && untilFound.evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('optional update dialog displays version, size, changelog, and allows Nanti Saja', (tester) async {
    final service = createService(releaseJson: {
      'id': 1,
      'platform': 'android',
      'channel': 'staging',
      'version_name': '1.0.2',
      'build_number': 15,
      'min_supported_build_number': 10,
      'force_update': false,
      'title': 'Versi 1.0.2 Tersedia',
      'release_notes': '- Perbaikan manajemen sesi\n- Dukungan update langsung',
      'download_url': 'https://github.com/org/repo/releases/download/v1.0.2/app.apk',
      'sha256': 'a' * 64,
      'file_size_bytes': 29779558,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppUpdateDialog.checkAndShow(
                context,
                service: service,
              ),
              child: const Text('Check'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check'));
    await pumpRealAsync(tester);

    expect(find.text('Versi Baru Tersedia'), findsOneWidget);
    expect(find.text('Versi 1.0.2 Tersedia'), findsOneWidget);
    expect(find.text('v1.0.1 → v1.0.2'), findsOneWidget);
    expect(find.text('28.4 MB'), findsOneWidget);
    expect(find.textContaining('Perbaikan manajemen sesi'), findsOneWidget);
    expect(find.text('Update Sekarang'), findsOneWidget);
    expect(find.text('Nanti Saja'), findsOneWidget);

    await tester.tap(find.text('Nanti Saja'));
    await pumpRealAsync(tester);

    expect(find.byType(AppUpdateDialog), findsNothing);
    // Subsequent auto check respects dismiss cooldown
    final recheck = await tester.runAsync(() => service.checkForUpdate(manual: false));
    expect(recheck?.shouldPromptAutomatically, isFalse);
  });

  testWidgets('update dialog remains non-blocking with Nanti Saja and PopScope enabled even if server flags force_update', (tester) async {
    final service = createService(releaseJson: {
      'id': 2,
      'platform': 'android',
      'channel': 'staging',
      'version_name': '1.1.0',
      'build_number': 20,
      'min_supported_build_number': 99,
      'force_update': true,
      'release_notes': 'Pembaruan stabilitas.',
      'download_url': 'https://github.com/org/repo/releases/download/v1.1.0/app.apk',
      'sha256': 'b' * 64,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppUpdateDialog.checkAndShow(
                context,
                service: service,
              ),
              child: const Text('Check'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check'));
    await pumpRealAsync(tester);

    expect(find.text('Versi Baru Tersedia'), findsOneWidget);
    expect(find.text('Pembaruan Wajib'), findsNothing);
    expect(find.text('Nanti Saja'), findsOneWidget);
    expect(find.text('Update Sekarang'), findsOneWidget);

    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isTrue);
  });

  testWidgets('tapping Update Sekarang downloads, verifies SHA-256, invokes installer, and stays readyToInstall', (tester) async {
    final apkBytes = utf8.encode('VALID-SIGNED-APK-CONTENT');
    final validSha = sha256.convert(apkBytes).toString();
    var installCalls = 0;

    final service = createService(
      apkBytes: apkBytes,
      releaseJson: {
        'id': 3,
        'platform': 'android',
        'channel': 'staging',
        'version_name': '1.0.2',
        'build_number': 15,
        'force_update': false,
        'download_url': 'https://github.com/org/repo/releases/download/v1.0.2/app.apk',
        'sha256': validSha,
        'file_size_bytes': apkBytes.length,
      },
      onInstall: (_) async {
        installCalls++;
        return OpenResult(type: ResultType.done, message: 'done');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppUpdateDialog.checkAndShow(
                context,
                service: service,
              ),
              child: const Text('Check'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Check'));
    await pumpRealAsync(tester, untilFound: find.text('Update Sekarang'));

    await tester.tap(find.text('Update Sekarang'));
    await pumpRealAsync(tester, untilFound: find.text('Pasang Pembaruan'));

    expect(installCalls, 1);
    expect(find.text('Pasang Pembaruan'), findsOneWidget);
    expect(find.text('Unduh via Browser'), findsOneWidget);

    // Re-tap Pasang Pembaruan (e.g. after enabling unknown apps permission)
    await tester.tap(find.text('Pasang Pembaruan'));
    await pumpRealAsync(tester);
    expect(installCalls, 2);
  });

  testWidgets('manual check shows up-to-date SnackBar when no update exists', (tester) async {
    final service = createService(releaseJson: {
      'id': 4,
      'platform': 'android',
      'channel': 'staging',
      'version_name': '1.0.1',
      'build_number': 12,
      'force_update': false,
      'download_url': 'https://github.com/org/repo/releases/download/v1.0.1/app.apk',
      'sha256': 'c' * 64,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppUpdateDialog.checkAndShow(
                context,
                manual: true,
                service: service,
              ),
              child: const Text('CheckManual'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('CheckManual'));
    await pumpRealAsync(tester);

    expect(find.byType(AppUpdateDialog), findsNothing);
    expect(find.text('Aplikasi sudah versi terbaru (v1.0.1)'), findsOneWidget);
  });
}
