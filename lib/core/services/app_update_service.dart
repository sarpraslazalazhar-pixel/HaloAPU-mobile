import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:halo_apu_mobile/core/config/api_config.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/domain/models/app_release_model.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateSecurityException implements Exception {
  final String message;
  AppUpdateSecurityException(this.message);

  @override
  String toString() => message;
}

class AppUpdateException implements Exception {
  final String message;
  AppUpdateException(this.message);

  @override
  String toString() => message;
}

class AppUpdateCheckResult {
  final bool hasUpdate;
  final bool isForceUpdate;
  final String currentVersion;
  final int currentBuildNumber;
  final AppReleaseModel? release;
  final bool shouldPromptAutomatically;

  const AppUpdateCheckResult({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.currentVersion,
    required this.currentBuildNumber,
    this.release,
    required this.shouldPromptAutomatically,
  });
}

/// Layanan pengecekan, pengunduhan, verifikasi SHA-256, dan instalasi in-place
/// pembaruan aplikasi Halo APU Mobile.
class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService();

  static const String _dismissedBuildKey = 'dismissed_update_build';
  static const String _dismissedAtKey = 'dismissed_update_at';
  static const Duration _dismissCooldown = Duration(hours: 24);
  static const Duration _checkTimeout = Duration(seconds: 6);

  /// Trigger reaktif saat pengguna mengetuk notifikasi FCM `type: 'app_update'`.
  static final ValueNotifier<int> notificationUpdateTrigger = ValueNotifier<int>(0);

  final Dio? _customDio;
  final Future<PackageInfo> Function()? _packageInfoProvider;
  final Future<Directory> Function()? _tempDirProvider;
  final String? _platformOverride;
  final String? _channelOverride;
  final Future<OpenResult> Function(String filePath)? _openInstaller;
  final Future<bool> Function(Uri uri)? _urlLauncher;
  final DateTime Function()? _nowProvider;

  AppUpdateService({
    Dio? dio,
    Future<PackageInfo> Function()? packageInfoProvider,
    Future<Directory> Function()? tempDirProvider,
    String? platformOverride,
    String? channelOverride,
    Future<OpenResult> Function(String filePath)? openInstaller,
    Future<bool> Function(Uri uri)? urlLauncher,
    DateTime Function()? nowProvider,
  })  : _customDio = dio,
        _packageInfoProvider = packageInfoProvider,
        _tempDirProvider = tempDirProvider,
        _platformOverride = platformOverride,
        _channelOverride = channelOverride,
        _openInstaller = openInstaller,
        _urlLauncher = urlLauncher,
        _nowProvider = nowProvider;

  Dio get _dio =>
      _customDio ??
      Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: _checkTimeout,
        receiveTimeout: _checkTimeout,
        headers: const {'Accept': 'application/json'},
      ));

  DateTime _now() => (_nowProvider ?? DateTime.now)();

  void triggerFromNotification() {
    notificationUpdateTrigger.value++;
  }

  /// Mengambil versi dan build number aktual aplikasi yang terpasang.
  Future<({String version, int buildNumber})> getCurrentVersionInfo() async {
    String version = FlavorConfig.appVersion;
    int buildNumber = FlavorConfig.appBuildNumber;

    try {
      final info = await (_packageInfoProvider ?? PackageInfo.fromPlatform)();
      if (info.version.trim().isNotEmpty) {
        version = info.version.trim();
      }
      final parsedBuild = int.tryParse(info.buildNumber.trim());
      if (parsedBuild != null && parsedBuild > 0) {
        buildNumber = parsedBuild;
      }
    } catch (_) {
      // Gunakan fallback FlavorConfig jika PackageInfo tidak tersedia (mis. unit test).
    }

    return (version: version, buildNumber: buildNumber);
  }

  Future<String> getFormattedCurrentVersion() async {
    final info = await getCurrentVersionInfo();
    if (info.buildNumber > 0) {
      return 'v${info.version} (Build ${info.buildNumber})';
    }
    return 'v${info.version}';
  }

  /// Memastikan URL unduhan memakai HTTPS, bebas kredensial, dan berasal dari
  /// host tepercaya (GitHub Releases / host web Halo APU).
  static bool isAllowedDownloadUrl(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return false;

    const exactAllowedHosts = <String>{
      'github.com',
      'objects.githubusercontent.com',
      'release-assets.githubusercontent.com',
      'releases.githubusercontent.com',
    };
    if (exactAllowedHosts.contains(host)) return true;

    if (host.endsWith('.githubusercontent.com') &&
        host.length > '.githubusercontent.com'.length) {
      return true;
    }

    final appWebHost = Uri.tryParse(FlavorConfig.webUrl)?.host.trim().toLowerCase();
    if (appWebHost != null && appWebHost.isNotEmpty && host == appWebHost) {
      return true;
    }

    return false;
  }

  /// Mengecek apakah tersedia rilis terbaru untuk platform & channel aktif.
  Future<AppUpdateCheckResult?> checkForUpdate({bool manual = false}) async {
    final current = await getCurrentVersionInfo();
    await cleanupOldApks(currentBuildNumber: current.buildNumber);

    final platform = _platformOverride ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android');
    final channel = _channelOverride ?? FlavorConfig.releaseChannel;

    try {
      final response = await _dio.get(
        '/app-version',
        queryParameters: {
          'platform': platform,
          'channel': channel,
        },
        options: Options(
          sendTimeout: _checkTimeout,
          receiveTimeout: _checkTimeout,
        ),
      );

      if (response.statusCode != 200 || response.data is! Map) {
        if (manual) {
          throw AppUpdateException('Gagal memeriksa pembaruan dari server.');
        }
        return null;
      }

      final payload = response.data as Map;
      final rawRelease = payload['data'];
      if (rawRelease == null) {
        return AppUpdateCheckResult(
          hasUpdate: false,
          isForceUpdate: false,
          currentVersion: current.version,
          currentBuildNumber: current.buildNumber,
          release: null,
          shouldPromptAutomatically: false,
        );
      }

      if (rawRelease is! Map) {
        if (manual) {
          throw AppUpdateException('Format data pembaruan tidak valid.');
        }
        return null;
      }

      final release = AppReleaseModel.fromJson(
        Map<String, dynamic>.from(rawRelease),
      );

      // Pastikan channel & platform tidak tertukar (mencegah salah flavor/packageId)
      if (release.channel.isNotEmpty && release.channel != channel) {
        return AppUpdateCheckResult(
          hasUpdate: false,
          isForceUpdate: false,
          currentVersion: current.version,
          currentBuildNumber: current.buildNumber,
          release: null,
          shouldPromptAutomatically: false,
        );
      }

      final hasUpdate = release.buildNumber > current.buildNumber;
      // Pembaruan aplikasi selalu bersifat opsional (tidak pernah memblokir user).
      const isForceUpdate = false;

      var shouldPrompt = false;
      if (hasUpdate) {
        if (manual) {
          shouldPrompt = true;
        } else {
          final dismissedRecently = await _wasDismissedRecently(release.buildNumber);
          shouldPrompt = !dismissedRecently;
        }
      }

      return AppUpdateCheckResult(
        hasUpdate: hasUpdate,
        isForceUpdate: isForceUpdate,
        currentVersion: current.version,
        currentBuildNumber: current.buildNumber,
        release: release,
        shouldPromptAutomatically: shouldPrompt,
      );
    } on AppUpdateException {
      rethrow;
    } on DioException {
      if (manual) {
        throw AppUpdateException(
          'Gagal memeriksa pembaruan. Periksa koneksi internet Anda.',
        );
      }
      return null;
    } catch (_) {
      if (manual) {
        throw AppUpdateException('Terjadi kesalahan saat memeriksa pembaruan.');
      }
      return null;
    }
  }

  Future<bool> _wasDismissedRecently(int buildNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedBuild = prefs.getInt(_dismissedBuildKey);
      final dismissedAt = prefs.getInt(_dismissedAtKey);
      if (dismissedBuild != buildNumber || dismissedAt == null) return false;
      final elapsedMs = _now().millisecondsSinceEpoch - dismissedAt;
      return elapsedMs >= 0 && elapsedMs < _dismissCooldown.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Menyimpan penundaan dialog ("Nanti Saja") selama 24 jam untuk [buildNumber].
  Future<void> dismissUpdate(int buildNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dismissedBuildKey, buildNumber);
      await prefs.setInt(_dismissedAtKey, _now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Menghapus APK lama (`<= currentBuildNumber`) dan file `.part` sisa,
  /// namun mempertahankan APK terverifikasi untuk versi lebih baru agar user
  /// tidak perlu mengunduh ulang setelah mengaktifkan izin "Install unknown apps".
  Future<void> cleanupOldApks({required int currentBuildNumber}) async {
    try {
      final updatesDir = await _getUpdatesDirectory(createIfMissing: false);
      if (!await updatesDir.exists()) return;

      final apkPattern = RegExp(r'^haloapu-(\d+)\.apk$');
      await for (final entity in updatesDir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path.split(RegExp(r'[/\\]')).last;

        if (name.endsWith('.part')) {
          await _safeDelete(entity);
          continue;
        }

        final match = apkPattern.firstMatch(name);
        if (match != null) {
          final build = int.tryParse(match.group(1) ?? '');
          if (build != null && build <= currentBuildNumber) {
            await _safeDelete(entity);
          }
        }
      }
    } catch (_) {}
  }

  /// Mengunduh APK ke direktori cache aplikasi lalu memverifikasi SHA-256 secara streaming.
  Future<String> downloadAndVerifyApk(
    AppReleaseModel release, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final initialUri = Uri.tryParse(release.downloadUrl.trim());
    if (initialUri == null || !isAllowedDownloadUrl(initialUri)) {
      throw AppUpdateSecurityException(
        'URL unduhan pembaruan tidak valid atau tidak berasal dari sumber tepercaya.',
      );
    }

    final expectedSha = (release.sha256 ?? '').trim().toLowerCase();
    if (release.platform.toLowerCase() == 'android' &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha)) {
      throw AppUpdateSecurityException(
        'Checksum keamanan (SHA-256) rilis tidak valid. Pembaruan dibatalkan.',
      );
    }

    final updatesDir = await _getUpdatesDirectory(createIfMissing: true);
    final finalApkFile = File('${updatesDir.path}/haloapu-${release.buildNumber}.apk');

    // Pakai ulang APK terverifikasi bila sudah pernah diunduh (mis. kembali dari Settings izin)
    if (await finalApkFile.exists()) {
      final existingHash = await computeFileSha256(finalApkFile);
      if (expectedSha.isEmpty || existingHash == expectedSha) {
        return finalApkFile.path;
      }
      await _safeDelete(finalApkFile);
    }

    final partFile = File('${updatesDir.path}/haloapu-${release.buildNumber}.apk.part');
    await _safeDelete(partFile);

    final response = await _dio.download(
      release.downloadUrl.trim(),
      partFile.path,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    if (!isAllowedDownloadUrl(response.realUri)) {
      await _safeDelete(partFile);
      throw AppUpdateSecurityException(
        'Redirect unduhan mengarah ke host yang tidak diizinkan (${response.realUri.host}).',
      );
    }

    final actualSha = await computeFileSha256(partFile);
    if (expectedSha.isNotEmpty && actualSha != expectedSha) {
      await _safeDelete(partFile);
      throw AppUpdateSecurityException(
        'Verifikasi keamanan file (SHA-256) gagal. File pembaruan dibatalkan.',
      );
    }

    await _safeDelete(finalApkFile);
    await partFile.rename(finalApkFile.path);
    return finalApkFile.path;
  }

  /// Menghitung SHA-256 file secara streaming agar hemat RAM untuk APK besar.
  static Future<String> computeFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  /// Memicu installer sistem Android untuk update in-place tanpa uninstall.
  Future<OpenResult> installApk(String filePath) {
    if (_openInstaller != null) {
      return _openInstaller(filePath);
    }
    return OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
  }

  /// Fallback membuka tautan rilis di browser eksternal setelah validasi host allowlist.
  Future<bool> openDownloadInBrowser(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !isAllowedDownloadUrl(uri)) {
      throw AppUpdateSecurityException(
        'Tautan unduhan tidak valid atau tidak berasal dari sumber tepercaya.',
      );
    }
    if (_urlLauncher != null) {
      return _urlLauncher(uri);
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<Directory> _getUpdatesDirectory({required bool createIfMissing}) async {
    final tempDir = await (_tempDirProvider ?? getTemporaryDirectory)();
    final updatesDir = Directory('${tempDir.path}/updates');
    if (createIfMissing && !await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    return updatesDir;
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
