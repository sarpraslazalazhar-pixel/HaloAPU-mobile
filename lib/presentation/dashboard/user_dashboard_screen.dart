import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:halo_apu_mobile/presentation/widgets/custom_bottom_nav.dart';
import 'package:halo_apu_mobile/presentation/widgets/entrance_animation.dart';
import 'package:halo_apu_mobile/presentation/widgets/shimmer.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_avatar.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_permission_dialog.dart';
import 'package:halo_apu_mobile/core/services/push_notification_service.dart';
import 'package:halo_apu_mobile/domain/models/user_profile_model.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/notifications/providers/notification_provider.dart';
import 'package:halo_apu_mobile/presentation/profile/providers/user_profile_provider.dart';
import 'package:halo_apu_mobile/data/repositories/dashboard_repository.dart';
import 'widgets/horizontal_recent_tickets.dart';
import 'widgets/pending_rating_section.dart';
import 'providers/csat_provider.dart';
import '../tickets/providers/user_ticket_provider.dart';

class UserDashboardScreen extends ConsumerStatefulWidget {
  const UserDashboardScreen({super.key});

  @override
  ConsumerState<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends ConsumerState<UserDashboardScreen> {
  DashboardRepository get _dashboardRepo => ref.read(dashboardRepositoryProvider);
  Map<String, dynamic>? _dashboardData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    PushNotificationService.startRealtimePoller();
    PushNotificationService.onNotificationReceived = () {
      if (mounted) {
        ref.read(notificationProvider.notifier).refresh();
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionDialog.showIfRequired(context);
      PushNotificationService.syncFcmTokenWithBackend();
    });
  }

  Future<void> _fetchDashboardData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    ref.read(userProfileProvider.notifier).refresh();
    ref.read(notificationProvider.notifier).refresh();
    ref.read(csatProvider.notifier).fetchPendingCsat();
    ref.read(userTicketProvider.notifier).refresh();
    final result = await _dashboardRepo.getDashboardData();

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['success'] == true) {
          _dashboardData = result;
        }
      });

      if (result['statusCode'] == 401) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = ref
            .watch(notificationProvider)
            .value
            ?.where((n) => !n.isRead)
            .length ??
        0;
    final profile = ref.watch(userProfileProvider);
    final isOffline = _dashboardData?['isOffline'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      body: Stack(
        children: [
          // Background Gradient at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFE0F4FE).withValues(alpha: 0.7),
                    const Color(0xFFF7FAFC).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _fetchDashboardData,
              color: const Color(0xFF00768C),
              displacement: 40,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EntranceAnimation(
                      child: _DashboardHeader(
                        profile: profile,
                        unreadCount: unreadCount,
                      ),
                    ),

                    if (isOffline)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _dashboardData?['message'] ?? 'Mode Offline: Menampilkan data tersimpan',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFB45309),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Statistics Row
                    EntranceAnimation(
                      delay: const Duration(milliseconds: 90),
                      child: _isLoading && _dashboardData == null
                          ? const StatRowSkeleton()
                          : _StatisticsRow(stats: _dashboardData?['stats']),
                    ),
                    // Hero Action (Ketersediaan Aset)
                    EntranceAnimation(
                      delay: const Duration(milliseconds: 180),
                      child: _buildHeroAction(context),
                    ),
                    const SizedBox(height: 12),

                    // Recent Tickets
                    EntranceAnimation(
                      delay: const Duration(milliseconds: 270),
                      child: HorizontalRecentTickets(
                        initialTickets: _dashboardData?['recentTickets'] ?? <TicketModel>[],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Pending Ratings
                    const EntranceAnimation(
                      delay: Duration(milliseconds: 340),
                      child: PendingRatingSection(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: const UserBottomNav(currentIndex: 0),
      floatingActionButton: CustomFloatingActionButton(
        icon: Icons.add,
        onPressed: () {
          context.push('/tickets/create');
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildHeroAction(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            context.push('/monitor');
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0072FF).withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.devices_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Jadwal Reservasi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cek status dan jadwal reservasi ruangan & kendaraan',
                        style: TextStyle(
                          color: Color(0xE6FFFFFF),
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final UserProfile profile;
  final int unreadCount;

  const _DashboardHeader({required this.profile, required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    final displayName = profile.name.isNotEmpty && profile.name != 'Loading...'
        ? profile.name
        : (profile.username.isNotEmpty ? profile.username : 'Pengguna');
    final firstName = displayName.split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
      child: Row(
        children: [
          AppAvatar(
            name: displayName,
            imageUrl: profile.avatarUrl,
            radius: 24,
            onTap: () => context.push('/profile'),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assalamu\'alaikum, $firstName',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00768C),
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Selamat pagi, ada yang bisa dibantu?',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Colors.black87, size: 22),
                  onPressed: () => context.push('/notifications'),
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          )
        ],
      ),
    );
  }
}

int _parseInt(dynamic val) {
  if (val == null) return 0;
  if (val is int) return val;
  if (val is num) return val.toInt();
  if (val is String) return int.tryParse(val) ?? 0;
  return 0;
}

class _StatisticsRow extends StatelessWidget {
  final Map<String, dynamic>? stats;

  const _StatisticsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final aktif = _parseInt(stats?['aktif']);
    final selesai = _parseInt(stats?['selesai']);
    final diproses = _parseInt(stats?['diproses']);
    final ditolak = _parseInt(stats?['ditolak']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 2.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildStatCard(
                  title: 'Aktif',
                  count: aktif,
                  color: const Color(0xFF0066FF),
                  icon: Icons.data_usage_rounded,
                  onTap: () => context.push('/tickets/user', extra: 'Aktif'),
                ),
                const SizedBox(height: 8),
                _buildStatCard(
                  title: 'Selesai',
                  count: selesai,
                  color: const Color(0xFF10B981),
                  icon: Icons.check_circle_outline_rounded,
                  onTap: () => context.push('/tickets/user', extra: 'Selesai'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                _buildStatCard(
                  title: 'Diproses',
                  count: diproses,
                  color: const Color(0xFFF59E0B),
                  icon: Icons.hourglass_empty_rounded,
                  onTap: () => context.push('/tickets/user', extra: 'Diproses'),
                ),
                const SizedBox(height: 8),
                _buildStatCard(
                  title: 'Ditolak',
                  count: ditolak,
                  color: const Color(0xFFEF4444),
                  icon: Icons.cancel_outlined,
                  onTap: () => context.push('/tickets/user', extra: 'Ditolak'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 16),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: count.toDouble()),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Text(
                      value.round().toString(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
