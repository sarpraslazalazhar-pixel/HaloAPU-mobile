import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';
import 'package:halo_apu_mobile/presentation/widgets/auth_attachment_image.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/core/utils/date_formatter.dart';

const Set<String> _attachmentPlaceholderNotes = {
  '[Lampiran]',
  '[Lampiran Tiket]',
  '[Lampiran Chat]',
};

/// Mengembalikan `true` jika [note] adalah placeholder internal untuk pesan lampiran tanpa teks.
bool isAttachmentPlaceholderNote(String note) =>
    _attachmentPlaceholderNotes.contains(note.trim());

class ChatBubble extends StatelessWidget {
  final TicketReply reply;
  final bool isCurrentUserAdmin;
  final String requesterName;
  final int? currentAdminId;
  final String? currentAdminName;
  final bool isTicketClosed;
  final void Function(TicketReply reply)? onEdit;

  const ChatBubble({
    super.key,
    required this.reply,
    required this.isCurrentUserAdmin,
    required this.requesterName,
    this.currentAdminId,
    this.currentAdminName,
    this.isTicketClosed = false,
    this.onEdit,
  });

  bool get _isSystemAction {
    final action = reply.action.toLowerCase().trim();
    final note = reply.note.toLowerCase().trim();

    // Regular user/admin chat message actions
    if (action == 'balasan' || action == 'pesan' || action == 'chat' || action == 'reply' || action == 'diskusi' || action == 'catatan') {
      return false;
    }

    // System event actions
    if (action == 'dibuat' ||
        action == 'alat_diserahkan' ||
        action == 'alat_dikembalikan' ||
        action.contains('assign') ||
        action.contains('status') ||
        action.contains('priority') ||
        action.contains('revisi') ||
        action == 'solve' ||
        action == 'reject' ||
        action == 'cancel' ||
        action.startsWith('work_hours')) {
      return true;
    }

    // Fallback: Check note keywords for auto-generated logs
    if (note.startsWith('tiket dibuat') ||
        note.startsWith('tiket ditugaskan') ||
        note.startsWith('penugasan operator') ||
        note.startsWith('status diubah') ||
        note.startsWith('prioritas diubah') ||
        note.startsWith('revisi diajukan') ||
        note.startsWith('solusi diajukan')) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isSystemAction) {
      return _buildSystemEventPill(context);
    }

    bool isMe = false;
    if (isCurrentUserAdmin) {
      if (reply.isFromAdmin) {
        if (currentAdminId != null && reply.adminId != null) {
          isMe = reply.adminId == currentAdminId;
        } else if (currentAdminName != null && currentAdminName!.isNotEmpty) {
          final myName = currentAdminName!.toLowerCase().trim();
          final senderName = (reply.adminName ?? '').toLowerCase().trim();
          isMe = senderName.isNotEmpty && senderName == myName;
        } else {
          isMe = false;
        }
      } else {
        isMe = false;
      }
    } else {
      isMe = !reply.isFromAdmin;
    }

    final bool canEdit =
        isMe && onEdit != null && !isTicketClosed && !_isSystemAction && reply.id > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: isMe ? _buildMyBubble(context, canEdit: canEdit) : _buildOtherBubble(context),
    );
  }

  Widget _buildSystemEventPill(BuildContext context) {
    IconData icon = Icons.info_outline_rounded;
    Color iconColor = const Color(0xFF64748B);
    Color bgColor = const Color(0xFFF1F5F9);
    Color borderColor = const Color(0xFFE2E8F0);

    final noteLower = reply.note.toLowerCase();
    final actionLower = reply.action.toLowerCase();
    String? actionBadgeLabel;

    if (actionLower == 'alat_diserahkan') {
      icon = Icons.inventory_2_outlined;
      iconColor = const Color(0xFF0284C7);
      bgColor = const Color(0xFFE0F2FE);
      borderColor = const Color(0xFFBAE6FD);
      actionBadgeLabel = 'Alat Diserahkan';
    } else if (actionLower == 'alat_dikembalikan') {
      icon = Icons.assignment_turned_in_rounded;
      iconColor = const Color(0xFF059669);
      bgColor = const Color(0xFFD1FAE5);
      borderColor = const Color(0xFFA7F3D0);
      actionBadgeLabel = 'Alat Dikembalikan';
    } else if (actionLower.contains('assign') || noteLower.contains('ditugaskan') || noteLower.contains('penugasan')) {
      icon = Icons.assignment_ind_rounded;
      iconColor = const Color(0xFF4F46E5);
      bgColor = const Color(0xFFEEF2FF);
      borderColor = const Color(0xFFC7D2FE);
    } else if (actionLower.contains('dibuat') || noteLower.contains('dibuat')) {
      icon = Icons.add_task_rounded;
      iconColor = const Color(0xFF0284C7);
      bgColor = const Color(0xFFE0F2FE);
      borderColor = const Color(0xFFBAE6FD);
    } else if (noteLower.contains('selesai') || noteLower.contains('solve') || noteLower.contains('diterima')) {
      icon = Icons.check_circle_rounded;
      iconColor = const Color(0xFF16A34A);
      bgColor = const Color(0xFFDCFCE7);
      borderColor = const Color(0xFFBBF7D0);
    } else if (noteLower.contains('tolak') || noteLower.contains('batal') || noteLower.contains('reject')) {
      icon = Icons.cancel_rounded;
      iconColor = const Color(0xFFDC2626);
      bgColor = const Color(0xFFFEE2E2);
      borderColor = const Color(0xFFFECACA);
    } else if (actionLower.startsWith('work_hours')) {
      icon = Icons.schedule_rounded;
      iconColor = const Color(0xFF475569);
      bgColor = const Color(0xFFF1F5F9);
      borderColor = const Color(0xFFCBD5E1);
    } else if (noteLower.contains('proses') || noteLower.contains('status')) {
      icon = Icons.sync_alt_rounded;
      iconColor = const Color(0xFFD97706);
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFFDE68A);
    } else if (noteLower.contains('revisi')) {
      icon = Icons.edit_note_rounded;
      iconColor = const Color(0xFF9333EA);
      bgColor = const Color(0xFFF3E8FF);
      borderColor = const Color(0xFFE9D5FF);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actionBadgeLabel != null) ...[
                    Text(
                      actionBadgeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: iconColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    reply.note,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              formatDateTime(reply.createdAt, pattern: 'HH:mm'),
              style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: reply.note));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pesan disalin ke papan klip'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showBubbleActions(BuildContext context, {required bool canEdit}) {
    if (!canEdit) {
      _copyToClipboard(context);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(sheetContext).padding.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Color(0xFF00768C)),
              title: const Text(
                'Edit Komentar',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onEdit?.call(reply);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Color(0xFF475569)),
              title: const Text(
                'Salin Teks',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _copyToClipboard(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowNoteText() {
    final trimmed = reply.note.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == '[Lampiran]') return false;
    final hasAttachments = reply.attachments != null && reply.attachments!.isNotEmpty;
    if (hasAttachments && isAttachmentPlaceholderNote(trimmed)) return false;
    return true;
  }

  Widget _buildEditedBadge({required Color color}) {
    if (!reply.isEdited) return const SizedBox.shrink();
    final label = Text(
      '(diedit)',
      style: TextStyle(
        fontSize: 10,
        fontStyle: FontStyle.italic,
        color: color,
      ),
    );
    if (reply.editedAt == null) return label;
    return Tooltip(
      message: 'Diedit ${formatDateTime(reply.editedAt, pattern: 'dd MMM yyyy, HH:mm')}',
      child: label,
    );
  }

  Widget _buildAttachments(BuildContext context, List<Map<String, dynamic>> attachments, bool isMe) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: attachments.map((att) {
        final fileName = (att['fileName'] ?? att['original_name'] ?? 'Lampiran').toString();
        final mimeType = att['mimeType']?.toString() ?? att['mime_type']?.toString();
        final isImg = AttachmentService.isImage(fileName, mimeType);
        final url = AttachmentService.resolveAttachmentUrl(att);

        if (url.isEmpty) return const SizedBox.shrink();

        if (isImg) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Stack(
              children: [
                AuthAttachmentImage(
                  imageUrl: url,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showAuthImagePreview(
                    context,
                    url: url,
                    title: fileName,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_in_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              AttachmentService.downloadAndOpenFile(
                context,
                url: url,
                fileName: fileName,
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isMe ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file_rounded,
                    size: 18,
                    color: isMe ? Colors.white : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      fileName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isMe ? Colors.white : const Color(0xFF1E293B),
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: isMe ? Colors.white70 : const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
          );
        }
      }).toList(),
    );
  }

  Widget _buildOtherBubble(BuildContext context) {
    final bool isAdminSender = reply.isFromAdmin;
    final String senderName = isAdminSender
        ? (reply.adminName != null && reply.adminName!.isNotEmpty
            ? reply.adminName!
            : 'Operator')
        : (requesterName.isNotEmpty ? requesterName : 'Pemohon');

    final String roleTag = isAdminSender ? 'Operator' : 'Pemohon';
    final Color roleTagBg = isAdminSender ? const Color(0xFFEEF2FF) : const Color(0xFFECFDF5);
    final Color roleTagColor = isAdminSender ? const Color(0xFF4F46E5) : const Color(0xFF059669);
    final Color avatarBg = isAdminSender ? const Color(0xFFEEF2FF) : const Color(0xFFF0FDF4);
    final Color avatarColor = isAdminSender ? const Color(0xFF4F46E5) : const Color(0xFF10B981);

    final String initial = senderName.isNotEmpty ? senderName[0].toUpperCase() : (isAdminSender ? 'O' : 'U');

    return GestureDetector(
      onLongPress: () => _copyToClipboard(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 17,
            backgroundColor: avatarBg,
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: avatarColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Bubble Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Sender Name + Role Badge
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          senderName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: roleTagBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          roleTag,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: roleTagColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (reply.attachments != null && reply.attachments!.isNotEmpty)
                        _buildAttachments(context, reply.attachments!, false),
                      if (_shouldShowNoteText())
                        Text(
                          reply.note,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF1E293B),
                            height: 1.35,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (reply.isEdited) ...[
                              _buildEditedBadge(color: const Color(0xFF64748B)),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              formatDateTime(reply.createdAt, pattern: 'HH:mm'),
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40), // Right spacing
        ],
      ),
    );
  }

  Widget _buildMyBubble(BuildContext context, {required bool canEdit}) {
    final bubbleCard = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00768C), Color(0xFF008EA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00768C).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (reply.attachments != null && reply.attachments!.isNotEmpty)
            _buildAttachments(context, reply.attachments!, true),
          if (_shouldShowNoteText())
            Text(
              reply.note,
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.white,
                height: 1.35,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reply.isEdited) ...[
                _buildEditedBadge(color: Colors.white.withValues(alpha: 0.85)),
                const SizedBox(width: 5),
              ],
              Text(
                formatDateTime(reply.createdAt, pattern: 'HH:mm'),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.done_all_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ],
          ),
        ],
      ),
    );

    return GestureDetector(
      onLongPress: () => _showBubbleActions(context, canEdit: canEdit),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(width: canEdit ? 8 : 44), // Left spacing
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 2, bottom: 4),
                  child: Text(
                    'Anda',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (canEdit) ...[
                      IconButton(
                        onPressed: () => onEdit?.call(reply),
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        color: const Color(0xFF64748B),
                        tooltip: 'Edit komentar',
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(child: bubbleCard),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
