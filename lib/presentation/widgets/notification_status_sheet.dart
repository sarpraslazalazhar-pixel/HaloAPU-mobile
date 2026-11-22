import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/services/permission_service.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';

/// Bottom sheet diagnostik & pengaturan notifikasi agar tetap aktif saat aplikasi ditutup.
class NotificationStatusSheet extends StatefulWidget {
  const NotificationStatusSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationStatusSheet(),
    );
  }

  @override
  State<NotificationStatusSheet> createState() =>
      _NotificationStatusSheetState();
}

class _NotificationStatusSheetState extends State<NotificationStatusSheet> {
  NotificationDiagnosticStatus? _status;
  bool _isLoading = true;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final permissionGranted =
        await PermissionService.isNotificationPermissionGranted();
    final diag = await PushNotificationService.getDiagnosticStatus();
    if (!mounted) return;
    setState(() {
      _status = NotificationDiagnosticStatus(
        permissionGranted: permissionGranted || diag.permissionGranted,
        fcmReady: diag.fcmReady,
        isPlaceholderConfig: diag.isPlaceholderConfig,
        backgroundWorkerActive: diag.backgroundWorkerActive,
        realtimePollerActive: diag.realtimePollerActive,
      );
      _isLoading = false;
    });
  }

  Future<void> _requestPermission() async {
    if (_isRequestingPermission) return;
    setState(() => _isRequestingPermission = true);
    try {
      final granted = await PermissionService.requestNotificationPermission();
      await PushNotificationService.syncFcmTokenWithBackend();
      await _loadStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: granted ? AppTheme.success : AppTheme.warning,
          content: Text(
            granted
                ? 'Izin notifikasi berhasil diaktifkan.'
                : 'Izin notifikasi belum diberikan. Aktifkan lewat Pengaturan Aplikasi HP.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRequestingPermission = false);
    }
  }

  Future<void> _sendTestNotification() async {
    await PushNotificationService.showNotificationAlert(
      title: 'Tes Notifikasi Halo APU',
      body: 'Notifikasi pop-up dan suara di perangkat Anda berfungsi dengan baik.',
      data: const {'type': 'test'},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Notifikasi uji dikirim ke status bar perangkat.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.oceanWater.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppTheme.oceanWater,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status & Pengaturan Notifikasi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pastikan notifikasi tetap masuk saat aplikasi ditutup',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading || status == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _StatusRow(
                icon: status.permissionGranted
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: status.permissionGranted
                    ? AppTheme.success
                    : AppTheme.danger,
                title: 'Izin Notifikasi Perangkat',
                subtitle: status.permissionGranted
                    ? 'Aktif • Notifikasi diizinkan tampil'
                    : 'Nonaktif • Ketuk aktifkan agar notif bisa muncul',
                trailing: status.permissionGranted
                    ? null
                    : TextButton(
                        onPressed:
                            _isRequestingPermission ? null : _requestPermission,
                        child: const Text('Aktifkan'),
                      ),
              ),
              const SizedBox(height: 10),
              _StatusRow(
                icon: Icons.sync_rounded,
                color: (status.fcmReady || status.backgroundWorkerActive)
                    ? AppTheme.oceanWater
                    : AppTheme.warning,
                title: 'Layanan Latar Belakang',
                subtitle: status.fcmReady
                    ? 'Push Real-Time + Sinkronisasi Latar Belakang Aktif'
                    : status.backgroundWorkerActive
                        ? 'Sinkronisasi Latar Belakang Aktif (Mode Fallback)'
                        : 'Mode Polling Aktif Saat Aplikasi Dibuka',
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () async {
                  await PushNotificationService.openBatteryOptimizationSettings();
                },
                icon: const Icon(Icons.battery_saver_rounded),
                label: const Text(
                  'Izinkan Berjalan di Latar Belakang (Hemat Baterai)',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _sendTestNotification,
                icon: const Icon(Icons.notifications_none_rounded),
                label: const Text('Uji Notifikasi Lokal'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.oceanWater,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _StatusRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
