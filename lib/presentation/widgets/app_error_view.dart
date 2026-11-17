import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';

/// Tampilan error terpusat.
///
/// - `fullPage: true` → halaman penuh (dipakai `GoRouter.errorBuilder`).
/// - `fullPage: false` → kartu ringkas untuk `ErrorWidget.builder`, aman
///   dirender di dalam subtree sempit tanpa overflow.
class AppErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onLogin;
  final bool fullPage;

  const AppErrorView({
    super.key,
    this.error,
    this.onRetry,
    this.onLogin,
    this.fullPage = true,
  });

  String get _message => kDebugMode
      ? '$error'
      : 'Sesi akun Anda telah berakhir atau tampilan memerlukan pembaruan. Silakan masuk kembali.';

  @override
  Widget build(BuildContext context) {
    return fullPage ? _buildPage(context) : _buildInline(context);
  }

  Widget _buildInline(BuildContext context) {
    return Material(
      color: AppTheme.lightBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Slot bisa sangat sempit (mis. pengganti satu item di dalam Row).
          final tiny = constraints.maxHeight < 72 || constraints.maxWidth < 140;
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: tiny
                    ? const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 28)
                    : SizedBox(
                        width: 200,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 32),
                            const SizedBox(height: 8),
                            const Text(
                              'Terjadi Kendala Tampilan',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            if (kDebugMode) ...[
                              const SizedBox(height: 4),
                              Text(
                                _message,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5, color: AppTheme.slateGrey, height: 1.35),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0x1F00B8D9), Color(0x1F0066FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x3300B8D9)),
                      ),
                      child: const Icon(Icons.report_gmailerrorred_rounded, size: 46, color: AppTheme.danger),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Terjadi Kendala Tampilan',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Maaf, halaman ini gagal dimuat. Coba muat ulang; jika masih berlanjut, masuk kembali ke akun Anda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.slateGrey),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        _message,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Muat Ulang'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.oceanWater,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login_rounded, size: 20),
                    label: const Text('Masuk ke Akun'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brilliantBlue,
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
