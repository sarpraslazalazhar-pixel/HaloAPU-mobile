import 'package:flutter/material.dart';

/// Ringkasan jeda jam kerja dari API (`data.work_hours`).
class TicketWorkHoursInfo {
  final String reason; // 'paused' | 'queued'
  final String? resumeStatus;
  final bool isOpen;
  final String? nextOpenLabel;
  final String? operatorName;
  final bool canResume;

  const TicketWorkHoursInfo({
    required this.reason,
    this.resumeStatus,
    required this.isOpen,
    this.nextOpenLabel,
    this.operatorName,
    required this.canResume,
  });

  bool get isPaused => reason == 'paused';

  static TicketWorkHoursInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final reason = map['reason']?.toString();
    if (reason != 'paused' && reason != 'queued') return null;

    return TicketWorkHoursInfo(
      reason: reason!,
      resumeStatus: map['resume_status']?.toString(),
      isOpen: map['is_open'] == true,
      nextOpenLabel: map['next_open_label']?.toString(),
      operatorName: map['operator_name']?.toString(),
      canResume: map['can_resume'] == true,
    );
  }
}

class TicketWorkHoursNotice extends StatelessWidget {
  final TicketWorkHoursInfo info;
  final bool isAdmin;
  final VoidCallback onContact;
  final VoidCallback? onResume;
  final bool resuming;

  const TicketWorkHoursNotice({
    super.key,
    required this.info,
    required this.isAdmin,
    required this.onContact,
    this.onResume,
    this.resuming = false,
  });

  @override
  Widget build(BuildContext context) {
    final heading = info.isOpen
        ? (info.isPaused
            ? 'Menunggu petugas melanjutkan tiket'
            : 'Tiket menunggu giliran petugas')
        : 'Jam kerja sudah berakhir';
    final body = info.isPaused
        ? 'Pengerjaan tiket ditunda.'
        : 'Posisi tiket dalam antrean tidak berubah.';
    final guidance = isAdmin
        ? 'Jika harus ditangani hari ini, koordinasikan lewat chat tiket dan ajukan lembur sesuai prosedur kantor.'
        : (info.operatorName != null
            ? 'Perlu ditangani hari ini? Hubungi petugas lewat chat tiket untuk meminta lembur.'
            : 'Petugas belum ditugaskan. Sampaikan kebutuhan hari ini di chat tiket.');

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 20, color: Color(0xFFB45309)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(body,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF92400E))),
                      if (!info.isOpen && info.nextOpenLabel != null) ...[
                        const SizedBox(height: 2),
                        Text('Buka kembali: ${info.nextOpenLabel}',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF92400E))),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        info.operatorName != null
                            ? 'Petugas: ${info.operatorName}'
                            : 'Belum ada petugas yang ditugaskan',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF92400E)),
                      ),
                      const SizedBox(height: 2),
                      Text(guidance,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF92400E))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (info.canResume && onResume != null)
                  ElevatedButton.icon(
                    onPressed: resuming ? null : onResume,
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                    label: Text(resuming ? 'Memproses...' : 'Lanjutkan Tiket'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: onContact,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(info.operatorName != null
                      ? 'Hubungi Petugas'
                      : 'Buka Chat Tiket'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: const Color(0xFF92400E),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
