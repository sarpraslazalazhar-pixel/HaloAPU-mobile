import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/csat_provider.dart';
import 'package:halo_apu_mobile/presentation/tickets/providers/user_ticket_provider.dart';

class _PendingRatingItem {
  final String id;
  final String ticketId;
  final String title;
  final String category;
  final String? date;
  final bool isMock;

  const _PendingRatingItem({
    required this.id,
    required this.ticketId,
    required this.title,
    required this.category,
    this.date,
    this.isMock = false,
  });
}

class PendingRatingSection extends ConsumerStatefulWidget {
  const PendingRatingSection({super.key});

  @override
  ConsumerState<PendingRatingSection> createState() => _PendingRatingSectionState();
}

class _PendingRatingSectionState extends ConsumerState<PendingRatingSection> {
  final Set<String> _dismissedIds = {};

  List<_PendingRatingItem> _getItems() {
    final csatState = ref.watch(csatProvider);
    final userTickets = ref.watch(userTicketProvider).valueOrNull ?? [];

    final List<_PendingRatingItem> items = [];

    // 1. Data dari CsatProvider (pending CSAT dari backend)
    final pendingCsats = csatState.pendingCsats.valueOrNull ?? [];
    for (final p in pendingCsats) {
      if (!_dismissedIds.contains(p.id) && !_dismissedIds.contains(p.ticketId)) {
        items.add(_PendingRatingItem(
          id: p.id,
          ticketId: p.ticketId,
          title: p.ticketTitle,
          category: p.category.isNotEmpty ? p.category : 'Layanan IT',
          date: _formatDate(p.completedAt),
          isMock: false,
        ));
      }
    }

    // 2. Fallback dari tiket user dengan status solved yang belum dirating
    if (items.isEmpty) {
      final solvedWithoutCsat = userTickets.where((t) =>
        t.status == TicketStatus.solved &&
        t.csat == null &&
        !_dismissedIds.contains(t.id)
      );

      for (final t in solvedWithoutCsat) {
        items.add(_PendingRatingItem(
          id: t.id,
          ticketId: t.id,
          title: t.title,
          category: t.category.isNotEmpty ? t.category : 'Layanan IT',
          date: 'Selesai',
          isMock: false,
        ));
      }
    }

    // 3. Fallback mock 2 item contoh agar langsung tampil 2 kotak seperti gambar user
    if (items.isEmpty) {
      const mock1 = _PendingRatingItem(
        id: 'mock-wifi',
        ticketId: 'TCK-8821',
        title: 'Pemasangan Router WiFi Ruang Rapat',
        category: 'Jaringan & Internet',
        date: 'Hari ini',
        isMock: true,
      );
      const mock2 = _PendingRatingItem(
        id: 'mock-laptop',
        ticketId: 'TCK-8819',
        title: 'Perbaikan Laptop HRD',
        category: 'Perangkat Keras',
        date: 'Kemarin',
        isMock: true,
      );

      if (!_dismissedIds.contains(mock1.id)) items.add(mock1);
      if (!_dismissedIds.contains(mock2.id)) items.add(mock2);
    }

    return items;
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'Selesai';
    try {
      final dt = DateTime.parse(raw);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Hari ini';
      }
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Selesai';
    }
  }

  void _showRatingModal(BuildContext context, _PendingRatingItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RatingModalSheet(
        item: item,
        onRatingSuccess: () {
          setState(() {
            _dismissedIds.add(item.id);
            _dismissedIds.add(item.ticketId);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _getItems();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              const Icon(
                Icons.star_rounded,
                size: 20,
                color: Color(0xFFF59E0B),
              ),
              const SizedBox(width: 8),
              const Text(
                'Menunggu Penilaian',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length} Tiket',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => context.push('/ratings/history'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Lihat Semua',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00768C),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Beri ulasan kepuasan layanan Halo APU',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Cards Horizontal List
        SizedBox(
          height: 125,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildCard(context, item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, _PendingRatingItem item) {
    return Container(
      width: 230,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFDE68A),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showRatingModal(context, item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top: Star badge + Title
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Middle: Ticket ID & Category / Date
                Row(
                  children: [
                    Text(
                      item.ticketId,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      '•',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        item.category,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.date != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        item.date!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),

                // Bottom: 5-star pill + "Beri Nilai" chip button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (_) => const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 0.5),
                          child: Icon(
                            Icons.star_rounded,
                            size: 12.5,
                            color: Color(0xFFF59E0B),
                          ),
                        )),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Beri Nilai',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingModalSheet extends ConsumerStatefulWidget {
  final _PendingRatingItem item;
  final VoidCallback onRatingSuccess;

  const _RatingModalSheet({
    required this.item,
    required this.onRatingSuccess,
  });

  @override
  ConsumerState<_RatingModalSheet> createState() => _RatingModalSheetState();
}

class _RatingModalSheetState extends ConsumerState<_RatingModalSheet> {
  final TextEditingController _commentController = TextEditingController();
  final TicketService _ticketService = TicketService();
  int _selectedRating = 5;
  bool _isSubmitting = false;

  static const Map<int, String> _satisfactionLabels = {
    1: 'Sangat Buruk',
    2: 'Buruk',
    3: 'Cukup',
    4: 'Puas',
    5: 'Sangat Puas',
  };

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _isSubmitting = true);
    final comment = _commentController.text.trim();

    try {
      if (!widget.item.isMock) {
        await _ticketService.rateTicket(
          widget.item.ticketId,
          _selectedRating,
          comment: comment.isNotEmpty ? comment : null,
        );
        ref.read(csatProvider.notifier).fetchPendingCsat();
        ref.read(userTicketProvider.notifier).refresh();
      } else {
        await Future.delayed(const Duration(milliseconds: 350));
      }

      widget.onRatingSuccess();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Terima kasih! Penilaian Anda berhasil dikirim.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Gagal mengirim penilaian. Silakan coba lagi.'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final labelText = _satisfactionLabels[_selectedRating] ?? 'Puas';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: bottomInset + 24,
        top: 16,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header Title
          const Text(
            'Penilaian Layanan',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Bagaimana pengalaman Anda terhadap penanganan tiket ini?',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Ticket Info Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.confirmation_number_outlined,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.item.ticketId} • ${widget.item.category}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 5-Star Interactive Rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starNum = index + 1;
              final isFilled = starNum <= _selectedRating;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedRating = starNum);
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: AnimatedScale(
                    scale: isFilled ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFilled ? const Color(0xFFF59E0B) : Colors.grey.shade300,
                      size: 42,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),

          // Satisfaction Level Label Chip
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                labelText,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Comment TextField
          TextField(
            controller: _commentController,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Tulis komentar atau saran Anda (opsional)...',
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 20),

          // Submit Button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRating,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                disabledBackgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.6),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Kirim Penilaian',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
