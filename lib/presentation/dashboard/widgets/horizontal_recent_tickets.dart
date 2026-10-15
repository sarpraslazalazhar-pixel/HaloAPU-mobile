import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/tickets/providers/user_ticket_provider.dart';

class HorizontalRecentTickets extends ConsumerStatefulWidget {
  final List<TicketModel>? initialTickets;

  const HorizontalRecentTickets({
    super.key,
    this.initialTickets,
  });

  @override
  ConsumerState<HorizontalRecentTickets> createState() =>
      _HorizontalRecentTicketsState();
}

class _HorizontalRecentTicketsState
    extends ConsumerState<HorizontalRecentTickets> {
  late final ScrollController _scrollController;
  bool _isLoadingMore = false;
  int _currentIndex = 0;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];


  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 60) {
      _triggerLoadMore();
    }

    final newIndex = (_scrollController.offset / 230).round();
    if (newIndex != _currentIndex) {
      setState(() => _currentIndex = newIndex);
    }
  }

  Future<void> _triggerLoadMore() async {
    final notifier = ref.read(userTicketProvider.notifier);
    if (_isLoadingMore || !notifier.hasMore) return;

    setState(() => _isLoadingMore = true);
    await notifier.loadMore();
    if (mounted) {
      setState(() => _isLoadingMore = false);
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  _CategoryConfig _getCategoryConfig(TicketModel ticket) {
    final text = '${ticket.category} ${ticket.title}'.toLowerCase();

    if (text.contains('laptop') ||
        text.contains('komputer') ||
        text.contains('pc') ||
        text.contains('proyektor') ||
        text.contains('hardware')) {
      return const _CategoryConfig(
        icon: Icons.laptop_chromebook_rounded,
        color: Color(0xFFF59E0B),
        bg: Color(0xFFFEF3C7),
      );
    }

    if (text.contains('aplikasi') ||
        text.contains('absensi') ||
        text.contains('login') ||
        text.contains('software')) {
      return const _CategoryConfig(
        icon: Icons.grid_view_rounded,
        color: Color(0xFF10B981),
        bg: Color(0xFFD1FAE5),
      );
    }

    if (text.contains('printer') || text.contains('scan')) {
      return const _CategoryConfig(
        icon: Icons.print_rounded,
        color: Color(0xFF8B5CF6),
        bg: Color(0xFFEDE9FE),
      );
    }

    return const _CategoryConfig(
      icon: Icons.confirmation_num_outlined,
      color: Color(0xFF00768C),
      bg: Color(0xFFE0F2FE),
    );
  }

  _StatusConfig _getStatusConfig(TicketStatus status) {
    switch (status) {
      case TicketStatus.solved:
        return const _StatusConfig(
          label: 'Selesai',
          bg: Color(0xFFD1FAE5),
          fg: Color(0xFF065F46),
        );
      case TicketStatus.processing:
        return const _StatusConfig(
          label: 'Diproses',
          bg: Color(0xFFFEF3C7),
          fg: Color(0xFF92400E),
        );
      case TicketStatus.open:
        return const _StatusConfig(
          label: 'Aktif',
          bg: Color(0xFFDBEAFE),
          fg: Color(0xFF1E40AF),
        );
      case TicketStatus.rejected:
        return const _StatusConfig(
          label: 'Ditolak',
          bg: Color(0xFFFFE4E6),
          fg: Color(0xFF9F1239),
        );
      case TicketStatus.pending:
        return const _StatusConfig(
          label: 'Tertunda',
          bg: Color(0xFFEDE9FE),
          fg: Color(0xFF5B21B6),
        );
      case TicketStatus.needRevision:
        return const _StatusConfig(
          label: 'Revisi',
          bg: Color(0xFFFFEDD5),
          fg: Color(0xFF9A3412),
        );
      case TicketStatus.cancelled:
        return const _StatusConfig(
          label: 'Dibatalkan',
          bg: Color(0xFFF1F5F9),
          fg: Color(0xFF475569),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(userTicketProvider);
    final List<TicketModel> tickets =
        (ticketsAsync.asData?.value.isNotEmpty == true)
            ? ticketsAsync.asData!.value
            : (widget.initialTickets ?? const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 12),
        if (tickets.isEmpty)
          _buildEmptyState(context)
        else ...[
          SizedBox(
            height: 132,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: tickets.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == tickets.length) {
                  return _buildLoadingCard();
                }
                return _buildTicketCard(context, tickets[index]);
              },
            ),
          ),
          const SizedBox(height: 8),
          _buildDotsIndicator(tickets.length),
        ],
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 18,
            color: Color(0xFF00768C),
          ),
          SizedBox(width: 8),
          Text(
            '5 Tiket Terbaru',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          Spacer(),
          Text(
            'Geser untuk melihat \u2190 \u2192',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketCard(BuildContext context, TicketModel ticket) {
    final catConfig = _getCategoryConfig(ticket);
    final statusConfig = _getStatusConfig(ticket.status);

    return Container(
      width: 218,
      height: 132,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.lightImpact();
            context.push('/tickets/user/detail', extra: ticket);
          },
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: catConfig.bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        catConfig.icon,
                        color: catConfig.color,
                        size: 17,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusConfig.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusConfig.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: statusConfig.fg,
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${ticket.id}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ticket.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 11,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(ticket.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (ticket.priority != null &&
                        ticket.priority!.trim().isNotEmpty) ...[
                      const Spacer(),
                      _buildPriorityBadge(ticket.priority!),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    final p = priority.toLowerCase();
    final isHigh = p.contains('tinggi') ||
        p.contains('urgen') ||
        p.contains('urgent') ||
        p.contains('high');
    final isLow = p.contains('rendah') || p.contains('low');

    final bg = isHigh
        ? const Color(0xFFFEE2E2)
        : isLow
            ? const Color(0xFFF1F5F9)
            : const Color(0xFFFEF3C7);
    final fg = isHigh
        ? const Color(0xFFB91C1C)
        : isLow
            ? const Color(0xFF475569)
            : const Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priority,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      width: 218,
      height: 132,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00768C)),
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Memuat tiket...',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDotsIndicator(int count) {
    final dotCount = count.clamp(1, 5);
    final activeDot = _currentIndex.clamp(0, dotCount - 1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(dotCount, (index) {
        final isActive = index == activeDot;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: isActive ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF00768C) : const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inbox_rounded,
              color: Color(0xFF94A3B8),
              size: 24,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Belum ada tiket',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ajukan tiket baru jika Anda membutuhkan bantuan IT',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              HapticFeedback.lightImpact();
              context.push('/tickets/create');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF00768C),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Buat Tiket',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryConfig {
  final IconData icon;
  final Color color;
  final Color bg;

  const _CategoryConfig({
    required this.icon,
    required this.color,
    required this.bg,
  });
}

class _StatusConfig {
  final String label;
  final Color bg;
  final Color fg;

  const _StatusConfig({
    required this.label,
    required this.bg,
    required this.fg,
  });
}
