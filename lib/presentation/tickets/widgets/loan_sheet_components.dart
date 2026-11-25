import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:image_picker/image_picker.dart';

const int kMaxLoanAttachments = 3;
const int kMaxLoanAttachmentBytes = 3 * 1024 * 1024;
const List<String> kAllowedLoanExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'pdf',
  'doc',
  'docx',
];

String formatLoanBytesLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

({String label, Color bg, Color fg, Color border}) resolveLoanStatusVisual(
  TicketModel ticket,
) {
  final statusPeminjaman = ticket.statusPeminjaman;
  final isSolved = ticket.status == TicketStatus.solved;

  if (ticket.isSudahDikembalikan || statusPeminjaman == 'Dikembalikan') {
    return (
      label: 'Dikembalikan',
      bg: const Color(0xFFD1FAE5),
      fg: const Color(0xFF065F46),
      border: const Color(0xFFA7F3D0),
    );
  }

  if (!isSolved || statusPeminjaman == 'Menunggu Persetujuan') {
    return (
      label: 'Menunggu Persetujuan',
      bg: const Color(0xFFF3E8FF),
      fg: const Color(0xFF6B21A8),
      border: const Color(0xFFE9D5FF),
    );
  }

  if (statusPeminjaman == 'Belum Dikembalikan') {
    return (
      label: 'Belum Dikembalikan',
      bg: const Color(0xFFFFE4E6),
      fg: const Color(0xFF9F1239),
      border: const Color(0xFFFECDD3),
    );
  }

  if (ticket.isSudahDiserahkan || statusPeminjaman == 'Sedang Dipinjam') {
    return (
      label: 'Sedang Dipinjam',
      bg: const Color(0xFFE0F2FE),
      fg: const Color(0xFF075985),
      border: const Color(0xFFBAE6FD),
    );
  }

  return (
    label: 'Menunggu Diserahkan',
    bg: const Color(0xFFFEF3C7),
    fg: const Color(0xFF92400E),
    border: const Color(0xFFFDE68A),
  );
}

({String label, Color bg, Color fg, Color border}) resolveLoanConditionVisual(
  String? raw,
) {
  final key = TicketModel.normalizeKondisiKey(raw);
  final label = TicketModel.formatKondisiLabel(key);
  if (key == 'rusak') {
    return (
      label: label,
      bg: const Color(0xFFFFE4E6),
      fg: const Color(0xFF9F1239),
      border: const Color(0xFFFECDD3),
    );
  }
  if (key == 'tidak_lengkap') {
    return (
      label: label,
      bg: const Color(0xFFFEF3C7),
      fg: const Color(0xFF92400E),
      border: const Color(0xFFFDE68A),
    );
  }
  return (
    label: label,
    bg: const Color(0xFFD1FAE5),
    fg: const Color(0xFF065F46),
    border: const Color(0xFFA7F3D0),
  );
}

class LoanConditionBadge extends StatelessWidget {
  final String? kondisi;

  const LoanConditionBadge({super.key, required this.kondisi});

  @override
  Widget build(BuildContext context) {
    final visual = resolveLoanConditionVisual(kondisi);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: visual.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: visual.border),
      ),
      child: Text(
        visual.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: visual.fg,
        ),
      ),
    );
  }
}

class TicketLoanSummaryBox extends StatelessWidget {
  final String ticketId;
  final String? borrowerName;
  final String? equipmentText;
  final String? scheduleText;

  const TicketLoanSummaryBox({
    super.key,
    required this.ticketId,
    this.borrowerName,
    this.equipmentText,
    this.scheduleText,
  });

  @override
  Widget build(BuildContext context) {
    final displayId = ticketId.startsWith('#') ? ticketId : '#TKT-$ticketId';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Tiket', value: displayId, isMonospace: true),
          if (borrowerName != null && borrowerName!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _SummaryRow(label: 'Peminjam', value: borrowerName!.trim()),
          ],
          if (equipmentText != null &&
              equipmentText!.trim().isNotEmpty &&
              equipmentText!.trim() != '-') ...[
            const SizedBox(height: 6),
            _SummaryRow(label: 'Alat', value: equipmentText!.trim()),
          ],
          if (scheduleText != null && scheduleText!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _SummaryRow(label: 'Jadwal Pakai', value: scheduleText!.trim()),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isMonospace;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isMonospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.slateGrey),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: isMonospace ? 'monospace' : null,
              color: const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }
}

class LoanConditionSelector extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const LoanConditionSelector({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  static const List<Map<String, dynamic>> _options = [
    {
      'value': 'baik',
      'label': 'Bagus (Baik)',
      'icon': Icons.check_circle_outline,
      'color': AppTheme.success,
      'desc': 'Alat berfungsi normal & lengkap',
    },
    {
      'value': 'tidak_lengkap',
      'label': 'Kurang Lengkap',
      'icon': Icons.warning_amber_rounded,
      'color': AppTheme.warning,
      'desc': 'Aksesoris / kelengkapan kurang',
    },
    {
      'value': 'rusak',
      'label': 'Rusak',
      'icon': Icons.broken_image_outlined,
      'color': AppTheme.danger,
      'desc': 'Ada kerusakan fisik / fungsi',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final normalizedValue = TicketModel.normalizeKondisiKey(value);
    final selectedOption = _options.firstWhere(
      (opt) => opt['value'] == normalizedValue,
      orElse: () => _options.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _options.map((opt) {
            final optValue = opt['value'] as String;
            final optLabel = opt['label'] as String;
            final color = opt['color'] as Color;
            final isSelected = normalizedValue == optValue;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(minHeight: 74),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.12)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.6 : 1.0,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onChanged(optValue);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 6,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              opt['icon'] as IconData,
                              size: 21,
                              color: isSelected ? color : AppTheme.slateGrey,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              optLabel,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isSelected
                                    ? color
                                    : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: selectedOption['color'] as Color,
              ),
              const SizedBox(width: 5),
              Text(
                selectedOption['desc'] as String,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LoanAttachmentUploader extends StatefulWidget {
  final List<XFile> files;
  final ValueChanged<List<XFile>> onChanged;
  final bool enabled;

  const LoanAttachmentUploader({
    super.key,
    required this.files,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<LoanAttachmentUploader> createState() => _LoanAttachmentUploaderState();
}

class _LoanAttachmentUploaderState extends State<LoanAttachmentUploader> {
  String? _warning;
  bool _isPicking = false;

  Future<void> _appendFiles(List<XFile> picked) async {
    if (picked.isEmpty) return;
    final next = List<XFile>.from(widget.files);
    String? issue;

    for (final file in picked) {
      if (next.length >= kMaxLoanAttachments) {
        issue = 'Maksimal $kMaxLoanAttachments lampiran per aksi.';
        break;
      }

      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : '';
      if (ext.isNotEmpty && !kAllowedLoanExtensions.contains(ext)) {
        issue = '${file.name}: format file tidak didukung.';
        continue;
      }

      final size = await file.length();
      if (size > kMaxLoanAttachmentBytes) {
        issue = '${file.name}: ukuran file melebihi batas 3 MB.';
        continue;
      }

      next.add(file);
    }

    if (!mounted) return;
    setState(() => _warning = issue);
    widget.onChanged(next);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPicking ||
        !widget.enabled ||
        widget.files.length >= kMaxLoanAttachments) {
      return;
    }
    setState(() => _isPicking = true);
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        await _appendFiles([image]);
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _pickDocument() async {
    if (_isPicking ||
        !widget.enabled ||
        widget.files.length >= kMaxLoanAttachments) {
      return;
    }
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kAllowedLoanExtensions,
        allowMultiple: true,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final picked = <XFile>[];
        for (final pf in result.files) {
          if (pf.bytes != null) {
            picked.add(XFile.fromData(pf.bytes!, name: pf.name));
          } else if (pf.path != null) {
            picked.add(XFile(pf.path!, name: pf.name));
          }
        }
        await _appendFiles(picked);
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFull = widget.files.length >= kMaxLoanAttachments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Lampiran Foto / Dokumen (Opsional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ),
            Text(
              '${widget.files.length}/$kMaxLoanAttachments (maks 3 MB)',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PickerButton(
                icon: Icons.camera_alt_outlined,
                label: 'Kamera',
                onTap: (!widget.enabled || _isPicking || isFull)
                    ? null
                    : () => _pickImage(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PickerButton(
                icon: Icons.photo_library_outlined,
                label: 'Galeri',
                onTap: (!widget.enabled || _isPicking || isFull)
                    ? null
                    : () => _pickImage(ImageSource.gallery),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PickerButton(
                icon: Icons.attach_file_rounded,
                label: 'File',
                onTap: (!widget.enabled || _isPicking || isFull)
                    ? null
                    : _pickDocument,
              ),
            ),
          ],
        ),
        if (_warning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: Color(0xFF92400E),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _warning!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.files.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...widget.files.asMap().entries.map((entry) {
            final idx = entry.key;
            final file = entry.value;
            return _LoanSelectedFileChip(
              file: file,
              enabled: widget.enabled,
              onRemove: () {
                final next = List<XFile>.from(widget.files)..removeAt(idx);
                setState(() => _warning = null);
                widget.onChanged(next);
              },
            );
          }),
        ],
      ],
    );
  }
}

class _LoanSelectedFileChip extends StatelessWidget {
  final XFile file;
  final bool enabled;
  final VoidCallback onRemove;

  const _LoanSelectedFileChip({
    required this.file,
    required this.enabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lower = file.name.toLowerCase();
    final isImg = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            isImg ? Icons.image_outlined : Icons.insert_drive_file_outlined,
            size: 18,
            color: AppTheme.oceanWater,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                FutureBuilder<int>(
                  future: file.length(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    return Text(
                      formatLoanBytesLabel(snapshot.data!),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade500,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hapus lampiran',
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppTheme.danger,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: enabled ? onRemove : null,
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        foregroundColor: AppTheme.oceanWater,
        backgroundColor: const Color(0xFFF8FAFC),
      ),
    );
  }
}
