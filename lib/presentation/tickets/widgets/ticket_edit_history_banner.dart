import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/core/utils/date_formatter.dart';
import 'package:halo_apu_mobile/domain/models/ticket_edit_history_model.dart';

/// Banner ringkas "formulir diedit admin" + bottom sheet riwayat perubahan.
class TicketEditHistoryBanner extends StatelessWidget {
  final List<TicketEditHistoryModel> histories;

  const TicketEditHistoryBanner({super.key, required this.histories});

  @override
  Widget build(BuildContext context) {
    if (histories.isEmpty) return const SizedBox.shrink();
    final latest = histories.first;
    final labels = latest.changes.map((c) => c.label).where((l) => l.isNotEmpty).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.published_with_changes_rounded, size: 18, color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Formulir diperbarui oleh ${latest.editedByName} • ${formatDateTime(latest.createdAt, pattern: 'dd MMM yyyy, HH:mm')}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                ),
                if (labels.isNotEmpty)
                  Text(
                    labels,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showTicketEditHistorySheet(context, histories),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Lihat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

Future<void> showTicketEditHistorySheet(
  BuildContext context,
  List<TicketEditHistoryModel> histories,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 18, color: AppTheme.oceanWater),
                  SizedBox(width: 8),
                  Text(
                    'Riwayat Perubahan Formulir',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: histories.length,
                separatorBuilder: (_, __) => const Divider(height: 24, color: Color(0xFFF1F5F9)),
                itemBuilder: (_, index) {
                  final entry = histories[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.editedByName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                          ),
                          Text(
                            formatDateTime(entry.createdAt, pattern: 'dd MMM yyyy, HH:mm'),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      if ((entry.editReason ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'Alasan: ${entry.editReason}',
                            style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Color(0xFF475569)),
                          ),
                        ),
                      const SizedBox(height: 8),
                      ...entry.changes.map(
                        (diff) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${diff.label}:',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                              ),
                              _ValueChip(text: diff.oldLabel, isNew: false),
                              const Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF94A3B8)),
                              _ValueChip(text: diff.newLabel, isNew: true),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ValueChip extends StatelessWidget {
  final String text;
  final bool isNew;

  const _ValueChip({required this.text, required this.isNew});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isNew ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isNew ? FontWeight.bold : FontWeight.normal,
          color: isNew ? const Color(0xFF047857) : const Color(0xFFB91C1C),
          decoration: isNew ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }
}
