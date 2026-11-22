import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/core/services/app_update_service.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/domain/models/app_release_model.dart';
import 'package:open_filex/open_filex.dart';

enum _UpdateDialogPhase {
  prompt,
  downloading,
  verifying,
  readyToInstall,
  error,
}

/// Dialog pembaruan aplikasi Halo APU (in-app download, verifikasi SHA-256, & install in-place).
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateCheckResult checkResult;
  final AppUpdateService service;

  const AppUpdateDialog({
    super.key,
    required this.checkResult,
    required this.service,
  });

  static bool _isDialogOpen = false;

  @visibleForTesting
  static void resetDialogGuardForTest() {
    _isDialogOpen = false;
  }

  /// Memeriksa pembaruan lalu menampilkan [AppUpdateDialog] bila tersedia versi lebih baru.
  /// Mengembalikan `true` jika dialog sempat ditampilkan.
  static Future<bool> checkAndShow(
    BuildContext context, {
    bool manual = false,
    AppUpdateService? service,
  }) async {
    if (_isDialogOpen) return false;
    final updateService = service ?? AppUpdateService.instance;

    AppUpdateCheckResult? result;
    try {
      result = await updateService.checkForUpdate(manual: manual);
    } on AppUpdateException catch (e) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.danger,
            content: Text(e.message),
          ),
        );
      }
      return false;
    } catch (_) {
      return false;
    }

    if (result == null || !result.hasUpdate || result.release == null) {
      if (manual && context.mounted) {
        final versionText = result?.currentVersion ?? FlavorConfig.appVersion;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.oceanWater,
            content: Text('Aplikasi sudah versi terbaru (v$versionText)'),
          ),
        );
      }
      return false;
    }

    if (!manual && !result.shouldPromptAutomatically) {
      return false;
    }

    if (!context.mounted || _isDialogOpen) return false;
    _isDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AppUpdateDialog(
          checkResult: result!,
          service: updateService,
        ),
      );
      return true;
    } finally {
      _isDialogOpen = false;
    }
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _UpdateDialogPhase _phase = _UpdateDialogPhase.prompt;
  double? _progress;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _verifiedApkPath;
  String? _errorMessage;
  String? _installHint;
  CancelToken? _cancelToken;

  AppReleaseModel get _release => widget.checkResult.release!;
  bool get _isIosTarget =>
      _release.platform.toLowerCase() == 'ios' ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('Dialog ditutup');
    }
    super.dispose();
  }

  Future<void> _startUpdate() async {
    if (_isIosTarget) {
      await _openInBrowser();
      return;
    }

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    setState(() {
      _phase = _UpdateDialogPhase.downloading;
      _progress = null;
      _receivedBytes = 0;
      _totalBytes = _release.fileSizeBytes ?? 0;
      _errorMessage = null;
      _installHint = null;
    });

    try {
      final apkPath = await widget.service.downloadAndVerifyApk(
        _release,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          final effectiveTotal = total > 0 ? total : (_release.fileSizeBytes ?? 0);
          setState(() {
            _receivedBytes = received;
            _totalBytes = effectiveTotal;
            _progress = effectiveTotal > 0
                ? (received / effectiveTotal).clamp(0.0, 1.0)
                : null;
            if (_progress != null && _progress! >= 1.0) {
              _phase = _UpdateDialogPhase.verifying;
            }
          });
        },
      );

      if (!mounted) return;
      _verifiedApkPath = apkPath;
      setState(() {
        _phase = _UpdateDialogPhase.readyToInstall;
        _installHint =
            'File pembaruan terverifikasi siap dipasang. Jika Android meminta izin "Install aplikasi tidak dikenal", aktifkan untuk Halo APU lalu kembali dan ketuk Pasang Pembaruan.';
      });

      await _triggerInstall();
    } on DioException catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e)) {
        setState(() {
          _phase = _UpdateDialogPhase.prompt;
          _progress = null;
        });
        return;
      }
      setState(() {
        _phase = _UpdateDialogPhase.error;
        _errorMessage =
            'Gagal mengunduh pembaruan (${e.message ?? 'gangguan jaringan'}).';
      });
    } on AppUpdateSecurityException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdateDialogPhase.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdateDialogPhase.error;
        _errorMessage = 'Terjadi kesalahan saat menyiapkan pembaruan: $e';
      });
    }
  }

  Future<void> _triggerInstall() async {
    final path = _verifiedApkPath;
    if (path == null || path.isEmpty) return;

    final openResult = await widget.service.installApk(path);
    if (!mounted) return;
    if (openResult.type != ResultType.done) {
      setState(() {
        _phase = _UpdateDialogPhase.readyToInstall;
        _installHint = openResult.message.isNotEmpty
            ? 'Installer belum terbuka (${openResult.message}). Pastikan izin "Install aplikasi tidak dikenal" aktif lalu ketuk Pasang Pembaruan, atau unduh via browser.'
            : 'Pastikan izin "Install aplikasi tidak dikenal" aktif lalu ketuk Pasang Pembaruan.';
      });
    }
  }

  Future<void> _openInBrowser() async {
    try {
      await widget.service.openDownloadInBrowser(_release.downloadUrl);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdateDialogPhase.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _dismissLater() async {
    await widget.service.dismissUpdate(_release.buildNumber);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _cancelDownload() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('Unduhan dibatalkan pengguna');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _phase != _UpdateDialogPhase.verifying;
    final titleText = (_release.title != null && _release.title!.trim().isNotEmpty)
        ? _release.title!.trim()
        : 'Pembaruan Aplikasi Tersedia';

    return PopScope(
      canPop: canPop,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.oceanWater.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: AppTheme.oceanWater,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Versi Baru Tersedia',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0369A1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          titleText,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.darkBg,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _InfoChip(
                    icon: Icons.tag_rounded,
                    label:
                        'v${widget.checkResult.currentVersion} → v${_release.versionName}',
                  ),
                  if (_release.buildNumber > 0)
                    _InfoChip(
                      icon: Icons.build_circle_outlined,
                      label: 'Build ${_release.buildNumber}',
                    ),
                  if (_release.formattedFileSize.isNotEmpty)
                    _InfoChip(
                      icon: Icons.download_for_offline_outlined,
                      label: _release.formattedFileSize,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _buildPhaseBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseBody() {
    switch (_phase) {
      case _UpdateDialogPhase.prompt:
        final notes = (_release.releaseNotes != null &&
                _release.releaseNotes!.trim().isNotEmpty)
            ? _release.releaseNotes!.trim()
            : 'Peningkatan performa, keamanan, dan perbaikan bug aplikasi.';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Catatan Pembaruan',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.slateGrey,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  notes,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF334155),
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _startUpdate,
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text(
                  'Update Sekarang',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.oceanWater,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _dismissLater,
              child: const Text(
                'Nanti Saja',
                style: TextStyle(
                  color: AppTheme.slateGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );

      case _UpdateDialogPhase.downloading:
        final percent = _progress != null
            ? '${(_progress! * 100).clamp(0, 100).toInt()}%'
            : 'Menghubungkan...';
        final sizeText = _totalBytes > 0
            ? '${AppReleaseModel.formatBytes(_receivedBytes)} / ${AppReleaseModel.formatBytes(_totalBytes)}'
            : (_receivedBytes > 0
                ? AppReleaseModel.formatBytes(_receivedBytes)
                : '');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Mengunduh pembaruan...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.darkBg,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.oceanWater,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  percent,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.oceanWater,
                  ),
                ),
                if (sizeText.isNotEmpty)
                  Text(
                    sizeText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slateGrey,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _cancelDownload,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.slateGrey,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Batal'),
            ),
          ],
        );

      case _UpdateDialogPhase.verifying:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppTheme.oceanWater,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Memverifikasi keamanan file (SHA-256)...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkBg,
                  ),
                ),
              ),
            ],
          ),
        );

      case _UpdateDialogPhase.readyToInstall:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Text(
                _installHint ??
                    'Jika Android meminta izin "Install aplikasi tidak dikenal", aktifkan untuk Halo APU lalu ketuk tombol di bawah.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF166534),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _triggerInstall,
                icon: const Icon(Icons.install_mobile_rounded, size: 20),
                label: const Text(
                  'Pasang Pembaruan',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.oceanWater,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser_rounded, size: 18),
              label: const Text('Unduh via Browser'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.brilliantBlue,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Tutup',
                style: TextStyle(color: AppTheme.slateGrey),
              ),
            ),
          ],
        );

      case _UpdateDialogPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _errorMessage ?? 'Gagal mengunduh pembaruan.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF991B1B),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _startUpdate,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Coba Lagi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.oceanWater,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser_rounded, size: 18),
              label: const Text('Unduh via Browser'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.brilliantBlue,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Tutup',
                style: TextStyle(color: AppTheme.slateGrey),
              ),
            ),
          ],
        );
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: AppTheme.oceanWater),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}
