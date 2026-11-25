import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/widgets/auth_attachment_image.dart';

import 'loan_sheet_components.dart';

class EquipmentLoanCard extends StatelessWidget {
  final TicketModel ticket;
  final bool canManage;
  final VoidCallback? onHandover;
  final VoidCallback? onReturn;

  const EquipmentLoanCard({
    super.key,
    required this.ticket,
    this.canManage = false,
    this.onHandover,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final isSolved = ticket.status == TicketStatus.solved;
    final hasHandedOver = ticket.isSudahDiserahkan;
    final isReturned = ticket.isSudahDikembalikan;
    final skippedHandover = !hasHandedOver && isReturned;
    final isOverdue = ticket.statusPeminjaman == 'Belum Dikembalikan';
    final statusPill = resolveLoanStatusVisual(ticket);

    final serahAttachments = ticket.lampiranSerah;
    final kembaliAttachments = ticket.lampiranKembali;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 17,
                      color: Color(0xFF0D9488),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Siklus Peminjaman Alat',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusPill.bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusPill.border),
                      ),
                      child: Text(
                        statusPill.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusPill.fg,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((ticket.alatText != null && ticket.alatText != '-') ||
                    ticket.rentangWaktu != null) ...[
                  const SizedBox(height: 8),
                  if (ticket.alatText != null && ticket.alatText != '-')
                    Text(
                      ticket.alatText!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  if (ticket.rentangWaktu != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: AppTheme.slateGrey,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Jadwal pakai: ${ticket.rentangWaktu!}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.slateGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step 1: Pengajuan Disetujui
                _StepperRow(
                  icon: isSolved
                      ? Icons.check_circle_outline_rounded
                      : Icons.schedule_rounded,
                  iconBg: isSolved
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFF1F5F9),
                  iconColor: isSolved
                      ? const Color(0xFF047857)
                      : const Color(0xFF94A3B8),
                  title: '1. Pengajuan Disetujui',
                  body: Text(
                    isSolved
                        ? 'Tiket telah disetujui dan siap masuk tahap serah-terima fisik alat.'
                        : 'Menunggu persetujuan operator sebelum alat dapat diserahkan.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slateGrey,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Step 2: Alat Diserahkan (Dikasih)
                _StepperRow(
                  icon: hasHandedOver
                      ? Icons.how_to_reg_rounded
                      : Icons.inventory_2_outlined,
                  iconBg: hasHandedOver
                      ? const Color(0xFFE0F2FE)
                      : skippedHandover
                          ? const Color(0xFFF1F5F9)
                          : isSolved
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFF1F5F9),
                  iconColor: hasHandedOver
                      ? const Color(0xFF0369A1)
                      : skippedHandover
                          ? const Color(0xFF64748B)
                          : isSolved
                              ? const Color(0xFFB45309)
                              : const Color(0xFF94A3B8),
                  title: '2. Alat Diserahkan (Dikasih)',
                  trailingBadge: skippedHandover
                      ? const _TinyBadge(
                          label: 'Langsung dikembalikan',
                          bg: Color(0xFFF1F5F9),
                          fg: Color(0xFF475569),
                        )
                      : null,
                  body: hasHandedOver
                      ? _PhaseDetailBox(
                          bgColor: const Color(0xFFF0F9FF),
                          borderColor: const Color(0xFFBAE6FD),
                          children: [
                            Text(
                              'Diserahkan pada ${ticket.diserahkanAtFormatted ?? '-'}'
                              '${ticket.diserahkanOleh != null ? ' oleh ${ticket.diserahkanOleh}' : ''}.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF334155),
                                height: 1.35,
                              ),
                            ),
                            if (ticket.kondisiSerah != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Text(
                                    'Kondisi: ',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.slateGrey,
                                    ),
                                  ),
                                  LoanConditionBadge(
                                    kondisi: ticket.kondisiSerah,
                                  ),
                                ],
                              ),
                            ],
                            if (ticket.penerimaAlat != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                'Penerima: ${ticket.penerimaAlat}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                            if (ticket.catatanSerah != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                '"${ticket.catatanSerah!}"',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                            if (serahAttachments.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Divider(
                                height: 1,
                                color: Color(0xFFBAE6FD),
                              ),
                              const SizedBox(height: 8),
                              _LoanAttachmentPreviewList(
                                title:
                                    'Lampiran Serah-Terima (${serahAttachments.length})',
                                attachments: serahAttachments,
                                accentColor: const Color(0xFF0284C7),
                              ),
                            ],
                          ],
                        )
                      : skippedHandover
                          ? const Text(
                              'Pengembalian langsung dicatat operator tanpa catatan serah-terima terpisah.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.slateGrey,
                                height: 1.35,
                              ),
                            )
                          : Text(
                              isSolved
                                  ? 'Menunggu alat diambil / diserahkan oleh operator'
                                      '${ticket.rentangWaktu != null ? ' (jadwal: ${ticket.rentangWaktu})' : ''}.'
                                  : 'Aktif setelah pengajuan disetujui.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSolved
                                    ? const Color(0xFF475569)
                                    : const Color(0xFF94A3B8),
                                height: 1.35,
                              ),
                            ),
                ),
                const SizedBox(height: 14),

                // Step 3: Alat Dikembalikan
                _StepperRow(
                  icon: isReturned
                      ? Icons.check_circle_outline_rounded
                      : (isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.schedule_rounded),
                  iconBg: isReturned
                      ? const Color(0xFFD1FAE5)
                      : (isOverdue
                          ? const Color(0xFFFFE4E6)
                          : const Color(0xFFF1F5F9)),
                  iconColor: isReturned
                      ? const Color(0xFF047857)
                      : (isOverdue
                          ? const Color(0xFFBE123C)
                          : const Color(0xFF94A3B8)),
                  title: '3. Alat Dikembalikan',
                  body: isReturned
                      ? _PhaseDetailBox(
                          bgColor: const Color(0xFFECFDF5),
                          borderColor: const Color(0xFFA7F3D0),
                          children: [
                            Text(
                              'Dikembalikan pada ${ticket.dikembalikanAtFormatted ?? '-'}'
                              '${ticket.diterimaKembaliOleh != null ? ' (diterima oleh ${ticket.diterimaKembaliOleh})' : ''}.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF334155),
                                height: 1.35,
                              ),
                            ),
                            if (ticket.kondisiKembali != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Text(
                                    'Kondisi: ',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.slateGrey,
                                    ),
                                  ),
                                  LoanConditionBadge(
                                    kondisi: ticket.kondisiKembali,
                                  ),
                                ],
                              ),
                            ],
                            if (ticket.catatanKembali != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                '"${ticket.catatanKembali!}"',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                            if (kembaliAttachments.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Divider(
                                height: 1,
                                color: Color(0xFFA7F3D0),
                              ),
                              const SizedBox(height: 8),
                              _LoanAttachmentPreviewList(
                                title:
                                    'Lampiran Pengembalian (${kembaliAttachments.length})',
                                attachments: kembaliAttachments,
                                accentColor: const Color(0xFF059669),
                              ),
                            ],
                          ],
                        )
                      : Text(
                          isOverdue
                              ? 'Batas jadwal peminjaman telah lewat dan alat belum ditandai kembali.'
                              : 'Menunggu konfirmasi pengembalian oleh operator/admin.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isOverdue ? FontWeight.w600 : FontWeight.normal,
                            color: isOverdue
                                ? const Color(0xFFBE123C)
                                : AppTheme.slateGrey,
                            height: 1.35,
                          ),
                        ),
                ),

                // Admin actions (ONLY when canManage == true)
                if (canManage &&
                    isSolved &&
                    !isReturned &&
                    (ticket.canSerahkan || ticket.canKembalikan)) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),
                  if (ticket.canSerahkan) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: onHandover,
                        icon: const Icon(Icons.inventory_2_outlined, size: 16),
                        label: const Text(
                          'Tandai Sudah Dikasih',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    if (ticket.canKembalikan) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: OutlinedButton.icon(
                          onPressed: onReturn,
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                          ),
                          label: const Text(
                            'Langsung Tandai Dikembalikan',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF047857),
                            side: const BorderSide(color: Color(0xFF6EE7B7)),
                            minimumSize: const Size(0, 40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ] else if (ticket.canKembalikan) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: onReturn,
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          'Tandai Sudah Dikembalikan',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final Widget? trailingBadge;
  final Widget body;

  const _StepperRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.trailingBadge,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (trailingBadge != null) trailingBadge!,
                ],
              ),
              const SizedBox(height: 4),
              body,
            ],
          ),
        ),
      ],
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _TinyBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _PhaseDetailBox extends StatelessWidget {
  final Color bgColor;
  final Color borderColor;
  final List<Widget> children;

  const _PhaseDetailBox({
    required this.bgColor,
    required this.borderColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _LoanAttachmentPreviewList extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> attachments;
  final Color accentColor;

  const _LoanAttachmentPreviewList({
    required this.title,
    required this.attachments,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.attach_file_rounded, size: 13, color: accentColor),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...attachments.map((att) {
          String fileName =
              (att['fileName'] ?? att['file_name'] ?? att['original_name'] ?? 'Lampiran')
                  .toString();
          final mimeType =
              att['mimeType']?.toString() ?? att['mime_type']?.toString();
          final isImg = AttachmentService.isImage(fileName, mimeType);
          final url = AttachmentService.resolveAttachmentUrl(att);

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: url.isEmpty
                  ? null
                  : () {
                      if (isImg) {
                        showAuthImagePreview(
                          context,
                          url: url,
                          title: fileName,
                        );
                      } else {
                        AttachmentService.downloadAndOpenFile(
                          context,
                          url: url,
                          fileName: fileName,
                        );
                      }
                    },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    if (isImg && url.isNotEmpty)
                      AuthAttachmentImage(
                        imageUrl: url,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(6),
                      )
                    else
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isImg
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 18,
                          color: accentColor,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          if (att['fileSize'] != null || att['file_size'] != null)
                            Text(
                              formatLoanBytesLabel(
                                int.tryParse(
                                      (att['fileSize'] ?? att['file_size'])
                                          .toString(),
                                    ) ??
                                    0,
                              ),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.slateGrey,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      isImg ? Icons.visibility_outlined : Icons.download_rounded,
                      size: 17,
                      color: AppTheme.slateGrey,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
