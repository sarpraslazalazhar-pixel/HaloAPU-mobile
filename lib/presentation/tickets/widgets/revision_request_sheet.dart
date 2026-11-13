import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/presentation/widgets/image_doodle_screen.dart';
import 'package:image_picker/image_picker.dart';

class RevisionRequestResult {
  final String note;
  final List<XFile> attachments;

  const RevisionRequestResult({
    required this.note,
    required this.attachments,
  });
}

class RevisionRequestSheet extends StatefulWidget {
  final int revisionCount;
  final int maxRevisions;

  const RevisionRequestSheet({
    super.key,
    required this.revisionCount,
    required this.maxRevisions,
  });

  static Future<RevisionRequestResult?> show(
    BuildContext context, {
    required int revisionCount,
    required int maxRevisions,
  }) {
    return showModalBottomSheet<RevisionRequestResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RevisionRequestSheet(
        revisionCount: revisionCount,
        maxRevisions: maxRevisions,
      ),
    );
  }

  @override
  State<RevisionRequestSheet> createState() => _RevisionRequestSheetState();
}

class _RevisionRequestSheetState extends State<RevisionRequestSheet> {
  final TextEditingController _noteController = TextEditingController();
  final List<XFile> _attachments = [];
  String? _errorText;
  bool _isPicking = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool _isImageFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }

  Future<void> _addFile(XFile file) async {
    final len = await file.length();
    if (len > 3 * 1024 * 1024) {
      if (mounted) {
        setState(() => _errorText = 'Ukuran file "${file.name}" melebihi batas 3 MB.');
      }
      return;
    }
    if (mounted) {
      setState(() {
        _errorText = null;
        _attachments.add(file);
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPicking) return;
    if (_attachments.length >= 3) {
      setState(() => _errorText = 'Maksimal 3 lampiran untuk permintaan revisi.');
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
      if (image == null || !mounted) return;

      final shouldDoodle = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.draw_rounded, color: AppTheme.oceanWater),
              SizedBox(width: 8),
              Text(
                'Tandai / Coret Gambar?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: const Text(
            'Tandai bagian desain yang perlu direvisi dengan panah, kotak, atau coretan sebelum dilampirkan?',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Langsung Lampirkan', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.draw_rounded, size: 16),
              label: const Text('Coret & Tandai'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.oceanWater,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );

      if (shouldDoodle == true && mounted) {
        final annotated = await ImageDoodleScreen.annotate(context, image);
        if (annotated != null) {
          await _addFile(annotated);
          return;
        }
      }
      await _addFile(image);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _pickDocument() async {
    if (_isPicking) return;
    if (_attachments.length >= 3) {
      setState(() => _errorText = 'Maksimal 3 lampiran untuk permintaan revisi.');
      return;
    }

    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.single;
        if (platformFile.bytes != null) {
          await _addFile(XFile.fromData(platformFile.bytes!, name: platformFile.name));
        } else if (platformFile.path != null) {
          await _addFile(XFile(platformFile.path!));
        }
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _submit() {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      setState(() => _errorText = 'Catatan alasan revisi wajib diisi.');
      return;
    }
    Navigator.pop(
      context,
      RevisionRequestResult(
        note: note,
        attachments: List<XFile>.from(_attachments),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.maxRevisions - widget.revisionCount).clamp(0, widget.maxRevisions);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.brilliantBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: AppTheme.brilliantBlue, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Minta Revisi',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Revisi ke-${widget.revisionCount + 1} dari ${widget.maxRevisions} (sisa kuota: $remaining)',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Catatan Revisi *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              maxLines: 4,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              decoration: InputDecoration(
                hintText: 'Jelaskan bagian yang perlu direvisi (mis. warna, ukuran font, tata letak)...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
                  borderSide: const BorderSide(color: AppTheme.brilliantBlue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Lampiran Referensi / Coretan (Opsional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_attachments.length}/3 (maks 3MB)',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _PickerChipButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Kamera',
                    onTap: _isPicking || _attachments.length >= 3
                        ? null
                        : () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PickerChipButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Galeri',
                    onTap: _isPicking || _attachments.length >= 3
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PickerChipButton(
                    icon: Icons.attach_file_rounded,
                    label: 'Dokumen',
                    onTap: _isPicking || _attachments.length >= 3 ? null : _pickDocument,
                  ),
                ),
              ],
            ),
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              Column(
                children: _attachments.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final file = entry.value;
                  final isImg = _isImageFile(file.name);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          child: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E293B)),
                          ),
                        ),
                        if (isImg)
                          IconButton(
                            tooltip: 'Coret & Tandai Gambar',
                            icon: const Icon(Icons.draw_rounded, size: 18, color: AppTheme.oceanWater),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            onPressed: () async {
                              final annotated = await ImageDoodleScreen.annotate(context, file);
                              if (annotated != null && mounted) {
                                setState(() => _attachments[idx] = annotated);
                              }
                            },
                          ),
                        IconButton(
                          tooltip: 'Hapus lampiran',
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          onPressed: () => setState(() => _attachments.removeAt(idx)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: AppTheme.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorText!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: BorderSide(color: Colors.grey.shade300),
                      foregroundColor: const Color(0xFF475569),
                    ),
                    child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Kirim Revisi', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brilliantBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                      minimumSize: const Size(0, 48),
                    ),
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

class _PickerChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PickerChipButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        foregroundColor: AppTheme.oceanWater,
        backgroundColor: const Color(0xFFF8FAFC),
      ),
    );
  }
}
