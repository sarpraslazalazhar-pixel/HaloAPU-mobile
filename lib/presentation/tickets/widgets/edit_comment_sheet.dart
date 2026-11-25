import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/chat_bubble.dart';

/// Bottom sheet reusable untuk mengedit komentar / balasan tiket.
class EditCommentSheet extends StatefulWidget {
  final String ticketId;
  final TicketReply reply;
  final TicketService ticketService;

  const EditCommentSheet({
    super.key,
    required this.ticketId,
    required this.reply,
    required this.ticketService,
  });

  /// Menampilkan bottom sheet edit komentar dan mengembalikan [TicketReply] terbaru bila berhasil.
  static Future<TicketReply?> show(
    BuildContext context, {
    required String ticketId,
    required TicketReply reply,
    required TicketService ticketService,
  }) {
    return showModalBottomSheet<TicketReply>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditCommentSheet(
        ticketId: ticketId,
        reply: reply,
        ticketService: ticketService,
      ),
    );
  }

  @override
  State<EditCommentSheet> createState() => _EditCommentSheetState();
}

class _EditCommentSheetState extends State<EditCommentSheet> {
  late final TextEditingController _controller;
  late final String _initialText;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _initialText = isAttachmentPlaceholderNote(widget.reply.note)
        ? ''
        : widget.reply.note;
    _controller = TextEditingController(text: _initialText);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      if (_errorText != null) {
        _errorText = null;
      }
    });
  }

  bool get _canSave {
    if (_isSaving) return false;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == _initialText.trim()) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSave) return;
    final trimmed = _controller.text.trim();
    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    final result = await widget.ticketService.editTicketReply(
      widget.ticketId,
      widget.reply.id,
      trimmed,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final rawData = result['data'];
      TicketReply updated;
      if (rawData is Map) {
        final parsed = TicketReply.fromJson(Map<String, dynamic>.from(rawData));
        updated = widget.reply.copyWith(
          note: parsed.note.isNotEmpty ? parsed.note : trimmed,
          isEdited: true,
          editedAt: parsed.editedAt ?? DateTime.now(),
          adminId: parsed.adminId ?? widget.reply.adminId,
          adminName: parsed.adminName ?? widget.reply.adminName,
        );
      } else {
        updated = widget.reply.copyWith(
          note: trimmed,
          isEdited: true,
          editedAt: DateTime.now(),
        );
      }
      Navigator.of(context).pop(updated);
    } else {
      setState(() {
        _isSaving = false;
        _errorText = result['message']?.toString() ?? 'Gagal memperbarui komentar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        bottomInset + MediaQuery.of(context).padding.bottom + 20,
      ),
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
                  color: AppTheme.oceanWater.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  color: AppTheme.oceanWater,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit Komentar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Perubahan akan ditandai sebagai sudah diedit',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isSaving,
            minLines: 2,
            maxLines: 5,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: 'Tulis komentar...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(14),
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
                borderSide: const BorderSide(color: AppTheme.oceanWater, width: 1.5),
              ),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorText!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Batal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _canSave ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.oceanWater,
                    disabledBackgroundColor:
                        AppTheme.oceanWater.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Simpan',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
