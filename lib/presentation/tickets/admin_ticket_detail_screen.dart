import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';
import 'package:halo_apu_mobile/presentation/widgets/auth_attachment_image.dart';
import 'package:halo_apu_mobile/core/utils/date_formatter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import '../widgets/image_doodle_screen.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';
import 'package:halo_apu_mobile/core/services/cache_service.dart';
import 'providers/admin_ticket_provider.dart';
import 'widgets/ticket_status_timeline.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/ticket_sla_card.dart';
import 'widgets/return_asset_sheet.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/monitor_provider.dart';

class AdminTicketDetailScreen extends ConsumerStatefulWidget {
  final TicketModel ticket;

  const AdminTicketDetailScreen({super.key, required this.ticket});

  @override
  ConsumerState<AdminTicketDetailScreen> createState() =>
      _AdminTicketDetailScreenState();
}

class _AdminTicketDetailScreenState
    extends ConsumerState<AdminTicketDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TicketModel _ticket;
  bool _isLoadingDetail = true;
  bool _isSuperAdmin = false;
  bool _canAssignOperator = false;
  bool _isTimelineCollapsed = true;
  bool _showQuickRepliesBar = true;
  String _currentAdminName = '';
  Timer? _pollingTimer;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();
  final TextEditingController _messageController = TextEditingController();
  final List<XFile> _replyAttachments = [];
  List<Map<String, dynamic>> _attachments = [];
  Map<String, dynamic> _formData = {};
  List<Map<String, dynamic>> _formFields = [];
  Map<String, dynamic>? _csatData;

  static const List<String> _quickReplies = [
    'Baik, akan segera kami proses. Terima kasih atas informasinya.',
    'Mohon maaf atas kendalanya, sedang dalam penanganan tim terkait.',
    'Kendala sudah diselesaikan, silakan dicek kembali. Mohon konfirmasi.',
    'Mohon tambahkan foto/dokumen pendukung agar dapat kami tindaklanjuti.',
  ];

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _tabController = TabController(length: 3, vsync: this);

    _chatFocusNode.addListener(() {
      if (_chatFocusNode.hasFocus) {
        _scrollToBottom();
      }
    });

    _loadTicketDetail();
    _loadUserRole();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _tabController.index == 0 && !_isLoadingDetail && !_isSending) {
        _silentRefreshTicketDetail();
      }
    });
  }

  Future<void> _silentRefreshTicketDetail() async {
    final result = await _ticketService.getTicketDetail(_ticket.id);
    if (mounted && result['success'] == true && result['data'] is Map) {
      final data = Map<String, dynamic>.from(result['data'] as Map);
      final cacheKey = CacheService.ticketDetailKey(_ticket.id);
      await CacheService.put(cacheKey, data, ttlSeconds: 600);
      _applyDetailData(data);
    }
  }

  Future<void> _loadUserRole() async {
    String? userDataStr = await _storage.read(key: 'user_data');
    if (userDataStr == null || userDataStr.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      userDataStr = prefs.getString('user_data');
    }
    if (userDataStr != null && userDataStr.isNotEmpty) {
      try {
        final userData = jsonDecode(userDataStr);
        final position = userData['position']?.toString().toLowerCase() ?? '';
        final role = userData['role']?.toString().toLowerCase() ?? '';
        final division = userData['division']?.toString().toLowerCase() ?? '';
        final isSuper = userData['isSuperAdmin'] == true ||
            position.contains('super') ||
            role.contains('super') ||
            division.contains('super');
        final canAssign = userData['canAssignOperator'] == true || isSuper;

        if (mounted) {
          setState(() {
            _isSuperAdmin = isSuper;
            _canAssignOperator = canAssign;
            _currentAdminName = userData['name']?.toString() ?? userData['username']?.toString() ?? '';
          });
        }
      } catch (_) {}
    }
  }

  void _applyDetailData(Map<String, dynamic> data) {
    void apply() {
      _ticket = TicketModel.safeFromJson(data);
      if (data['attachments'] is List) {
        _attachments = List<Map<String, dynamic>>.from(
          (data['attachments'] as List).map((a) => Map<String, dynamic>.from(a as Map)),
        );
      }
      if (data['formData'] is Map) {
        _formData = Map<String, dynamic>.from(data['formData'] as Map);
      }
      if (data['formFields'] is List) {
        _formFields = List<Map<String, dynamic>>.from(
          (data['formFields'] as List).map((f) => Map<String, dynamic>.from(f as Map)),
        );
      }
      if (data['csat'] is Map) {
        _csatData = Map<String, dynamic>.from(data['csat'] as Map);
      }
    }

    if (mounted) {
      setState(apply);
      ref.read(adminTicketProvider.notifier).updateTicket(_ticket);
    } else {
      apply();
    }
  }

  Future<void> _loadTicketDetail() async {
    final cacheKey = CacheService.ticketDetailKey(_ticket.id);
    final cached = CacheService.get(cacheKey) ?? CacheService.getStale(cacheKey);
    if (cached != null && cached is Map) {
      _applyDetailData(Map<String, dynamic>.from(cached));
      if (mounted) {
        setState(() => _isLoadingDetail = false);
      } else {
        _isLoadingDetail = false;
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingDetail = true);
      }
    }

    final result = await _ticketService.getTicketDetail(_ticket.id);
    if (result['success'] == true && result['data'] is Map) {
      final data = Map<String, dynamic>.from(result['data'] as Map);
      await CacheService.put(cacheKey, data, ttlSeconds: 600);
      if (mounted) {
        _applyDetailData(data);
        setState(() => _isLoadingDetail = false);
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingDetail = false);
        if (cached == null && result['message'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'].toString())));
        }
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tabController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _applyTicket(TicketModel updated) {
    final merged = updated.copyWith(
      operators: updated.operators ?? _ticket.operators,
      logs: updated.logs ?? _ticket.logs,
    );
    setState(() => _ticket = merged);
    ref.read(adminTicketProvider.notifier).updateTicket(merged);
  }

  bool _isSending = false;
  final TicketService _ticketService = TicketService();

  Future<void> _sendMessage(String text) async {
    final message = text.trim().isEmpty && _replyAttachments.isNotEmpty ? '[Lampiran]' : text.trim();
    if (message.isEmpty && _replyAttachments.isEmpty) return;
    if (_isSending) return;

    setState(() => _isSending = true);
    final result = await _ticketService.replyTicket(
      _ticket.id, 
      message,
      attachments: _replyAttachments.isNotEmpty ? _replyAttachments : null,
    );
    if (result['success']) {
      final reply = TicketReply.fromJson(result['data']);
      _applyTicket(
        _ticket.copyWith(
          logs: [...?_ticket.logs, reply],
        ),
      );
      _messageController.clear();
      _replyAttachments.clear();
      _chatFocusNode.unfocus();
      _scrollToBottom();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  String _statusToString(TicketStatus status) {
    switch (status) {
      case TicketStatus.open: return 'open';
      case TicketStatus.processing: return 'on_proses';
      case TicketStatus.solved: return 'solve';
      case TicketStatus.rejected: return 'reject';
      case TicketStatus.cancelled: return 'dibatalkan';
      case TicketStatus.pending: return 'pending';
      case TicketStatus.needRevision: return 'need_revision';
    }
  }

  static const Map<TicketStatus, List<TicketStatus>> _validTransitions = {
    TicketStatus.open: [TicketStatus.processing, TicketStatus.rejected, TicketStatus.pending],
    TicketStatus.processing: [TicketStatus.solved, TicketStatus.pending, TicketStatus.rejected],
    TicketStatus.pending: [TicketStatus.processing],
    TicketStatus.needRevision: [TicketStatus.solved, TicketStatus.pending, TicketStatus.rejected],
  };

  String _statusLabel(TicketStatus status) {
    switch (status) {
      case TicketStatus.open: return 'Terbuka';
      case TicketStatus.processing: return 'Diproses';
      case TicketStatus.solved: return 'Selesai';
      case TicketStatus.rejected: return 'Ditolak';
      case TicketStatus.cancelled: return 'Dibatalkan';
      case TicketStatus.pending: return 'Tertunda';
      case TicketStatus.needRevision: return 'Butuh Revisi';
    }
  }

  IconData _getStatusIcon(TicketStatus status) {
    switch (status) {
      case TicketStatus.open: return Icons.inbox_rounded;
      case TicketStatus.processing: return Icons.handyman_outlined;
      case TicketStatus.solved: return Icons.check_circle_outline;
      case TicketStatus.rejected: return Icons.cancel_outlined;
      case TicketStatus.pending: return Icons.pause_circle_outline;
      case TicketStatus.cancelled: return Icons.block;
      case TicketStatus.needRevision: return Icons.warning_amber_rounded;
    }
  }

  Color _getStatusColor(TicketStatus status) {
    switch (status) {
      case TicketStatus.open: return AppTheme.danger;
      case TicketStatus.processing: return AppTheme.warning;
      case TicketStatus.solved: return AppTheme.success;
      case TicketStatus.rejected: return AppTheme.brilliantBlue;
      case TicketStatus.pending: return Colors.orange;
      case TicketStatus.cancelled: return Colors.grey;
      case TicketStatus.needRevision: return Colors.purple;
    }
  }

  void _showStatusSheet() {
    final availableStatuses = _validTransitions[_ticket.status] ?? [];
    
    if (availableStatuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada aksi status yang tersedia untuk tiket ini.')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Perbarui Status Tiket',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Status',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableStatuses.map((status) {
                  return SizedBox(
                    width: (MediaQuery.of(context).size.width - 48) / 2, // 2 columns minus paddings
                    child: _buildStatusOption(
                      sheetContext, 
                      status, 
                      _statusLabel(status), 
                      _getStatusIcon(status), 
                      _getStatusColor(status),
                    ),
                  );
                }).toList(),
              ),
              if ((_canAssignOperator || _isSuperAdmin) && _ticket.operators != null && _ticket.operators!.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Ditugaskan ke',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildAssignOption(sheetContext, 'Belum', null),
                    ..._ticket.operators!.map((op) => _buildAssignOption(sheetContext, op['name'], op['id'])),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOption(
    BuildContext sheetContext,
    TicketStatus status,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _ticket.status == status;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(sheetContext).pop(); // close bottom sheet first
        _showStatusConfirmDialog(status, label, color);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : AppTheme.lightBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey.shade500, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? color : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusConfirmDialog(TicketStatus status, String label, Color color) {
    final TextEditingController noteController = TextEditingController();
    bool isSubmitting = false;
    List<XFile> attachments = [];
    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Ubah Status ke "$label"'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tambahkan catatan opsional untuk riwayat tiket (bisa dilihat user):',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Cth: Penanganan selesai, menunggu validasi user.',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Lampiran Tambahan (Opsional):',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const Text(
                      'Maks. 3 lampiran',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    if (attachments.isNotEmpty)
                      Column(
                        children: attachments.asMap().entries.map((entry) {
                          int idx = entry.key;
                          XFile file = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                const Icon(Icons.image, size: 20, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    file.name,
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                                  onPressed: () {
                                    setStateDialog(() {
                                      attachments.removeAt(idx);
                                    });
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                )
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    if (attachments.length < 3)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            final fileSize = await image.length();
                            if (fileSize > 3 * 1024 * 1024) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ukuran file melebihi 3MB')),
                              );
                              return;
                            }
                            setStateDialog(() {
                              attachments.add(image);
                            });
                          }
                        },
                        icon: const Icon(Icons.add_photo_alternate, size: 18),
                        label: const Text('Pilih Gambar', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(36),
                          foregroundColor: AppTheme.oceanWater,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                if (!isSubmitting)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Batal', style: TextStyle(color: Colors.grey)),
                  ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setStateDialog(() => isSubmitting = true);
                          try {
                            final result = await _ticketService.changeStatus(
                              _ticket.id, 
                              _statusToString(status),
                              catatan: noteController.text.trim(),
                              attachments: attachments,
                            );
                            
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext); // close dialog

                            if (result['success']) {
                              await CacheService.remove(CacheService.ticketDetailKey(_ticket.id));
                              await CacheService.removeByPrefix('ticket_list_');
                              ref.read(adminTicketProvider.notifier).refresh();
                              ref.read(monitorProvider.notifier).refresh();
                              await _loadTicketDetail(); // reload to get new logs & detail
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(behavior: SnackBarBehavior.floating, content: Text('Status berhasil diubah menjadi "$label"')),
                              );
                            } else {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(result['message'])),
                              );
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.red.shade600,
                                content: Text('Gagal mengubah status: $e'),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Simpan Status', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAssignOption(
    BuildContext sheetContext,
    String assignee,
    int? adminId,
  ) {
    final isSelected = (_ticket.assignedTo ?? 'Belum') == assignee || (_ticket.assignedTo == null && adminId == null);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        Navigator.of(sheetContext).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(adminId == null ? 'Melepas penugasan operator...' : 'Menugaskan operator...'),
          ),
        );

        final result = await _ticketService.assignOperator(_ticket.id, adminId);
        if (result['success']) {
          _applyTicket(TicketModel.safeFromJson(result['data']));
          _loadTicketDetail();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: const Color(0xFF10B981),
                content: Text(adminId == null ? 'Penugasan operator berhasil dilepas' : 'Operator berhasil ditugaskan'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red.shade600,
                content: Text(result['message'] ?? 'Gagal memperbarui penugasan operator'),
              ),
            );
          }
        }
      },
      child: Container(
        width: (MediaQuery.of(context).size.width - 56) / 2, // 2 columns in Wrap
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.oceanWater.withValues(alpha: 0.12)
              : AppTheme.lightBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.oceanWater : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.person_outline_rounded,
              size: 18,
              color: isSelected
                  ? AppTheme.oceanWater
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                assignee,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? AppTheme.oceanWater : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignOperatorSheet() {
    final operators = _ticket.operators ?? [];
    final hasCurrentAssignee = _ticket.assignedTo != null && _ticket.assignedTo!.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.assignment_ind_rounded, color: Color(0xFF4F46E5), size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilih & Tugaskan Operator',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tugaskan tiket ini ke operator / teknisi terkait',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Opsi Unassign jika sudah ada penugasan saat ini
            if (hasCurrentAssignee) ...[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text('Melepas penugasan operator...'),
                    ),
                  );

                  final result = await _ticketService.assignOperator(_ticket.id, null);
                  if (result['success']) {
                    _applyTicket(TicketModel.safeFromJson(result['data']));
                    _loadTicketDetail();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Color(0xFF10B981),
                          content: Text('Penugasan operator berhasil dilepas'),
                        ),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: Colors.red.shade600,
                          content: Text(result['message'] ?? 'Gagal melepas operator'),
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFCA5A5),
                      width: 1.0,
                    ),
                  ),
                  child: const Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFFFEE2E2),
                        child: Icon(Icons.person_off_rounded, color: Color(0xFFDC2626), size: 18),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kosongkan / Lepas Penugasan',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Hapus operator yang ditugaskan saat ini',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFDC2626), size: 20),
                    ],
                  ),
                ),
              ),
            ],

            if (operators.isEmpty && !hasCurrentAssignee)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                alignment: Alignment.center,
                child: const Text('Tidak ada operator yang terdaftar untuk unit tiket ini', style: TextStyle(color: Colors.grey)),
              )
            else if (operators.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: operators.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final op = operators[idx];
                    final int opId = op['id'];
                    final String opName = op['name'] ?? 'Operator';
                    final bool isAssigned = (_ticket.assignedTo ?? '').toLowerCase() == opName.toLowerCase();

                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text('Menugaskan tiket ke $opName...'),
                          ),
                        );

                        final result = await _ticketService.assignOperator(_ticket.id, opId);
                        if (result['success']) {
                          _applyTicket(TicketModel.safeFromJson(result['data']));
                          _loadTicketDetail();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: const Color(0xFF10B981),
                                content: Text('Tiket berhasil ditugaskan ke $opName'),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.red.shade600,
                                content: Text(result['message'] ?? 'Gagal menugaskan operator'),
                              ),
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isAssigned ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isAssigned ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                            width: isAssigned ? 1.8 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isAssigned ? const Color(0xFF4F46E5) : Colors.grey.shade200,
                              child: Text(
                                opName.isNotEmpty ? opName[0].toUpperCase() : 'O',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isAssigned ? Colors.white : Colors.grey.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    opName,
                                    style: TextStyle(
                                      fontWeight: isAssigned ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 14,
                                      color: isAssigned ? const Color(0xFF312E81) : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isAssigned ? 'Operator Saat Ini' : 'Petugas Operator',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isAssigned ? const Color(0xFF4F46E5) : Colors.grey.shade500,
                                      fontWeight: isAssigned ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isAssigned)
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 22)
                            else
                              Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade400, size: 14),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showQuickReplySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Balasan Cepat',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            for (final reply in _quickReplies)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _sendMessage(reply);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.lightBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 18,
                          color: AppTheme.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            reply,
                            style: const TextStyle(fontSize: 13, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReplyAttachment(String type) async {
    Navigator.pop(context); // Close bottom sheet
    if (_replyAttachments.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maksimal 3 lampiran!')));
      return;
    }

    Future<void> process(XFile f) async {
      final len = await f.length();
      if (len > 3 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ukuran file maksimal 3MB!')));
        }
        return;
      }
      setState(() => _replyAttachments.add(f));
    }

    if (type == 'kamera' || type == 'galeri') {
      final picker = ImagePicker();
      final source = type == 'kamera' ? ImageSource.camera : ImageSource.gallery;
      final image = await picker.pickImage(source: source, maxWidth: 1920, imageQuality: 85);
      if (image != null) {
        if (mounted) {
          final shouldDoodle = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Row(
                children: [
                  Icon(Icons.draw_rounded, color: AppTheme.oceanWater),
                  SizedBox(width: 8),
                  Text('Tandai / Coret Foto?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: const Text(
                'Apakah Anda ingin mencoret atau menandai foto sebelum dikirim ke balasan tiket?',
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
              await process(annotated);
              return;
            }
          }
        }
        await process(image);
      }
    } else {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );
      if (result != null) {
        final platformFile = result.files.single;
        if (platformFile.bytes != null) {
          await process(XFile.fromData(platformFile.bytes!, name: platformFile.name));
        } else if (platformFile.path != null) {
          await process(XFile(platformFile.path!));
        }
      }
    }
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.camera_alt, color: Color(0xFF0284C7)),
                  ),
                  title: const Text('Kamera', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Ambil foto langsung', style: TextStyle(fontSize: 12)),
                  onTap: () => _pickReplyAttachment('kamera'),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE7F3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.photo_library, color: Color(0xFFDB2777)),
                  ),
                  title: const Text('Galeri Foto', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Pilih foto dari perangkat', style: TextStyle(fontSize: 12)),
                  onTap: () => _pickReplyAttachment('galeri'),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.insert_drive_file, color: Color(0xFFD97706)),
                  ),
                  title: const Text('Dokumen', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Kirim file PDF atau dokumen', style: TextStyle(fontSize: 12)),
                  onTap: () => _pickReplyAttachment('dokumen'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B), size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tiket #${_ticket.id}',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '${_ticket.category} • ${_ticket.requesterName}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_canAssignOperator || _isSuperAdmin)
            IconButton(
              tooltip: 'Tugaskan Operator',
              icon: const Icon(Icons.assignment_ind_outlined, color: Color(0xFF4F46E5), size: 22),
              onPressed: _showAssignOperatorSheet,
            ),
          IconButton(
            tooltip: 'Ubah Status',
            icon: const Icon(Icons.sync_alt_rounded, color: Color(0xFF00768C), size: 22),
            onPressed: _showStatusSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoadingDetail
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    TicketStatusTimeline(
                      ticket: _ticket,
                      isCollapsed: _isTimelineCollapsed,
                      onToggleExpand: () => setState(() => _isTimelineCollapsed = !_isTimelineCollapsed),
                      onAssignTap: (_canAssignOperator || _isSuperAdmin) ? _showAssignOperatorSheet : null,
                    ),
                    const SizedBox(height: 10),
                    TicketSlaCard(ticket: _ticket),
                    _buildAssetReturnCard(),
                    _buildPrioritySelector(),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: AppTheme.oceanWater,
                  indicatorWeight: 2.5,
                  labelColor: AppTheme.oceanWater,
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
                  tabs: [
                    const Tab(text: 'Chat & Riwayat'),
                    Tab(text: 'Lampiran (${_attachments.length})'),
                    const Tab(text: 'Detail Tiket'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildChatTab(),
            _buildAttachmentTab(),
            _buildDetailTab(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActionArea(context, isKeyboardOpen),
    );
  }

  Widget _buildAttachmentTab() {
    if (_attachments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Belum ada lampiran pada tiket ini', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _attachments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final att = _attachments[index];
        String fileName = (att['fileName'] ?? att['original_name'] ?? 'Lampiran').toString();
        final mimeType = att['mimeType']?.toString() ?? att['mime_type']?.toString();
        if (!fileName.contains('.')) {
          final ext = mimeType != null && mimeType.contains('png')
              ? 'png'
              : (mimeType != null && mimeType.contains('pdf') ? 'pdf' : 'jpg');
          fileName = '$fileName.$ext';
        }
        final isImage = AttachmentService.isImage(fileName, mimeType);
        final url = AttachmentService.resolveAttachmentUrl(att);

        return InkWell(
          onTap: () {
            if (url.isNotEmpty) {
              if (isImage) {
                showAuthImagePreview(context, url: url, title: fileName);
              } else {
                AttachmentService.downloadAndOpenFile(context, url: url, fileName: fileName);
              }
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                if (isImage && url.isNotEmpty)
                  AuthAttachmentImage(
                    imageUrl: url,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isImage ? Colors.blue.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                      color: isImage ? Colors.blue : Colors.amber.shade800,
                      size: 24,
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        att['fileSize'] != null
                            ? '${(int.tryParse(att['fileSize'].toString()) ?? 0) ~/ 1024} KB'
                            : (mimeType != null && mimeType.isNotEmpty ? mimeType : 'Dokumen'),
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isImage ? Icons.visibility_rounded : Icons.download_rounded,
                    size: 20,
                    color: const Color(0xFF64748B),
                  ),
                  onPressed: () {
                    if (url.isNotEmpty) {
                      if (isImage) {
                        showAuthImagePreview(context, url: url, title: fileName);
                      } else {
                        AttachmentService.downloadAndOpenFile(context, url: url, fileName: fileName);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailTab() {
    // Filter form fields: skip fields whose value is identical to title to avoid redundant repetition
    final activeFormFields = _formFields.where((field) {
      final val = _formData[field['id'].toString()];
      if (val == null || val.toString().trim().isEmpty) return false;
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Card 1: Informasi Utama
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF00768C)),
                      SizedBox(width: 6),
                      Text(
                        'INFORMASI UTAMA',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${_ticket.id}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _ticket.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 14),
              _buildDetailRow(Icons.category_outlined, 'Kategori Layanan', _ticket.category),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.person_outline_rounded, 'Nama Pemohon', _ticket.requesterName.isNotEmpty ? _ticket.requesterName : '-'),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.engineering_outlined, 'Ditugaskan Ke', _ticket.assignedTo ?? 'Belum ada teknisi'),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.calendar_today_outlined, 'Waktu Diajukan', formatDateTime(_ticket.createdAt, pattern: 'dd MMMM yyyy, HH:mm')),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.flag_outlined, 'Prioritas', _ticket.priority ?? 'Sedang'),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Card 2: Rincian Formulir
        if (activeFormFields.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF00768C)),
                    SizedBox(width: 6),
                    Text(
                      'RINCIAN FORMULIR',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...activeFormFields.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final field = entry.value;
                  final val = _formData[field['id'].toString()]?.toString() ?? '-';
                  final label = field['label']?.toString() ?? 'Field';
                  final isLast = idx == activeFormFields.length - 1;

                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            val,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          )
        else if (_ticket.summaryItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF00768C)),
                    SizedBox(width: 6),
                    Text(
                      'RINCIAN FORMULIR',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ..._ticket.summaryItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.key.isNotEmpty)
                            Text(
                              item.key,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            item.value,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

        // Card 3: Penilaian CSAT
        if (_csatData != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.star_rounded, size: 18, color: Color(0xFFD97706)),
                    SizedBox(width: 6),
                    Text(
                      'PENILAIAN KEPUASAN (CSAT)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ...List.generate(5, (index) {
                      final ratingVal = (_csatData!['rating'] is int ? _csatData!['rating'] : int.tryParse(_csatData!['rating'].toString())) ?? 0;
                      return Icon(
                        index < ratingVal ? Icons.star_rounded : Icons.star_border_rounded,
                        color: const Color(0xFFF59E0B),
                        size: 24,
                      );
                    }),
                    const SizedBox(width: 8),
                    Text(
                      '${_csatData!['rating']}/5',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                if (_csatData!['comment'] != null && _csatData!['comment'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '"${_csatData!['comment']}"',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12.5,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final localDate = date.toLocal();
    final checkDate = DateTime(localDate.year, localDate.month, localDate.day);

    if (checkDate == today) {
      return 'Hari Ini';
    } else if (checkDate == yesterday) {
      return 'Kemarin';
    } else {
      return formatDateTime(localDate, pattern: 'dd MMM yyyy');
    }
  }

  Widget _buildChatTab() {
    final logs = _ticket.logs ?? [];
    if (logs.isEmpty) {
      return Container(
        color: const Color(0xFFF8FAFC),
        padding: const EdgeInsets.all(32.0),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum ada percakapan',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tulis balasan atau gunakan balasan cepat di bawah untuk memulai percakapan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    final reversedLogs = logs.reversed.toList();
    final List<Widget> items = [];
    DateTime? lastDate;

    for (int i = 0; i < reversedLogs.length; i++) {
      final reply = reversedLogs[i];
      final localDate = reply.createdAt.toLocal();
      final replyDate = DateTime(localDate.year, localDate.month, localDate.day);

      if (lastDate == null || replyDate != lastDate) {
        lastDate = replyDate;
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _formatDateHeader(replyDate),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      items.add(
        ChatBubble(
          reply: reply,
          isCurrentUserAdmin: true,
          requesterName: _ticket.requesterName,
          currentAdminName: _currentAdminName,
        ),
      );
    }

    return Container(
      color: const Color(0xFFF8FAFC),
      child: RefreshIndicator(
        onRefresh: _silentRefreshTicketDetail,
        child: ListView(
          controller: _chatScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: items,
        ),
      ),
    );
  }

  Widget _buildBottomActionArea(BuildContext context, bool isKeyboardOpen) {
    return Container(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Replies Horizontal Bar
            if (_showQuickRepliesBar && _quickReplies.isNotEmpty) ...[
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _quickReplies.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final replyText = _quickReplies[idx];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        setState(() {
                          _messageController.text = replyText;
                          _messageController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _messageController.text.length),
                          );
                        });
                        _chatFocusNode.requestFocus();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded, size: 13, color: Color(0xFF0284C7)),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                replyText,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF334155),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Attachment Previews
            if (_replyAttachments.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                height: 52,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _replyAttachments.length,
                  itemBuilder: (ctx, i) {
                    final file = _replyAttachments[i];
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_rounded, size: 18, color: AppTheme.oceanWater),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              file.name,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (file.name.toLowerCase().endsWith('.jpg') ||
                              file.name.toLowerCase().endsWith('.jpeg') ||
                              file.name.toLowerCase().endsWith('.png')) ...[
                            IconButton(
                              icon: const Icon(Icons.draw_rounded, size: 16, color: AppTheme.oceanWater),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              tooltip: 'Coret & Tandai Foto',
                              onPressed: () async {
                                final annotated = await ImageDoodleScreen.annotate(context, file);
                                if (annotated != null && mounted) {
                                  setState(() {
                                    _replyAttachments[i] = annotated;
                                  });
                                }
                              },
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            onPressed: () => setState(() => _replyAttachments.removeAt(i)),
                          )
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Chat Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.attach_file_rounded,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                    onPressed: () => _showAttachmentOptions(context),
                  ),
                  GestureDetector(
                    onLongPress: _showQuickReplySheet,
                    child: IconButton(
                      icon: Icon(
                        Icons.bolt_rounded,
                        color: _showQuickRepliesBar ? const Color(0xFF0284C7) : Colors.grey.shade400,
                        size: 20,
                      ),
                      tooltip: 'Bilah Balasan Cepat (Tahan untuk opsi lainnya)',
                      onPressed: () => setState(() => _showQuickRepliesBar = !_showQuickRepliesBar),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _chatFocusNode,
                      onTap: _scrollToBottom,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A)),
                      decoration: const InputDecoration(
                        hintText: 'Ketik pesan balasan...',
                        hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 2),
                    decoration: const BoxDecoration(
                      color: AppTheme.oceanWater,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      onPressed: _isSending
                          ? null
                          : () {
                              if (_messageController.text.isNotEmpty || _replyAttachments.isNotEmpty) {
                                _sendMessage(_messageController.text);
                              } else {
                                _chatFocusNode.unfocus();
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons Row (Hidden when keyboard is open)
            if (!isKeyboardOpen) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showStatusSheet,
                      icon: const Icon(Icons.sync_alt_rounded, size: 16),
                      label: const Text(
                        'Ubah Status',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: AppTheme.danger, width: 1.2),
                        foregroundColor: AppTheme.danger,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  if (_canAssignOperator || _isSuperAdmin) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showAssignOperatorSheet,
                        icon: const Icon(Icons.assignment_ind_rounded, size: 16),
                        label: Text(
                          _ticket.assignedTo != null && _ticket.assignedTo!.isNotEmpty
                              ? 'Ganti Operator'
                              : 'Tugaskan Operator',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
  Widget _buildAssetReturnCard() {
    if (!_ticket.isPengembalianAlat) return const SizedBox.shrink();

    final isSolved = _ticket.status == TicketStatus.solved;
    if (!isSolved) return const SizedBox.shrink();

    final isReturned = _ticket.isSudahDikembalikan;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReturned
              ? AppTheme.success.withValues(alpha: 0.35)
              : AppTheme.warning.withValues(alpha: 0.4),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (isReturned ? AppTheme.success : AppTheme.warning)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    isReturned ? Icons.task_alt_rounded : Icons.assignment_return_outlined,
                    size: 17,
                    color: isReturned ? AppTheme.success : AppTheme.warning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status Pengembalian Alat',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isReturned
                            ? 'Alat telah diterima kembali'
                            : 'Tiket selesai, alat belum dikembalikan',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slateGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isReturned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.success.withValues(alpha: 0.25),
                        width: 1.0,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 12, color: AppTheme.success),
                        SizedBox(width: 3),
                        Text(
                          'Sudah Dikembalikan',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (isReturned) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_ticket.kondisiKembali != null)
                      Row(
                        children: [
                          const Icon(Icons.verified_outlined, size: 14, color: AppTheme.slateGrey),
                          const SizedBox(width: 6),
                          const Text('Kondisi: ',
                              style: TextStyle(fontSize: 11.5, color: AppTheme.slateGrey)),
                          Text(
                            _ticket.kondisiKembali!,
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                    if (_ticket.catatanKembali != null &&
                        _ticket.catatanKembali!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppTheme.slateGrey),
                          const SizedBox(width: 6),
                          const Text('Catatan: ',
                              style: TextStyle(fontSize: 11.5, color: AppTheme.slateGrey)),
                          Expanded(
                            child: Text(
                              _ticket.catatanKembali!,
                              style: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFF334155)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_ticket.dikembalikanAtFormatted != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: AppTheme.slateGrey),
                          const SizedBox(width: 6),
                          Text(
                            'Waktu: ${_ticket.dikembalikanAtFormatted}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.slateGrey),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Material(
                color: AppTheme.oceanWater,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _handleKembalikanAlat,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_return_outlined, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Tandai Alat Dikembalikan',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleKembalikanAlat() async {
    await ReturnAssetSheet.show(
      context,
      ticketId: _ticket.id,
      onConfirm: (kondisi, catatan) async {
        final res = await _ticketService.kembalikanAlat(
          _ticket.id,
          kondisi: kondisi,
          catatan: catatan,
        );
        if (!mounted) return false;
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              backgroundColor: AppTheme.success,
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      res['message'] ?? 'Alat berhasil dikembalikan',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          );
          ref.read(adminTicketProvider.notifier).refresh();
          ref.read(monitorProvider.notifier).refresh();
          await _loadTicketDetail();
          return true;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
              backgroundColor: AppTheme.danger,
              content: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      res['message'] ?? 'Gagal menandai pengembalian alat',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          );
          return false;
        }
      },
    );
  }

  Widget _buildPrioritySelector() {
    final currentPriority = _ticket.priority ?? 'Sedang';
    final priorities = [
      {'label': 'Rendah', 'color': AppTheme.slateGrey},
      {'label': 'Sedang', 'color': AppTheme.oceanWater},
      {'label': 'Tinggi', 'color': AppTheme.warning},
      {'label': 'Urgen', 'color': AppTheme.danger},
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.brilliantBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.flag_outlined, size: 15, color: AppTheme.brilliantBlue),
              ),
              const SizedBox(width: 8),
              const Text(
                'Prioritas Tiket',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Text(
                'Saat ini: $currentPriority',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slateGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: priorities.map((p) {
              final label = p['label'] as String;
              final color = p['color'] as Color;
              final isSelected = currentPriority.toLowerCase() == label.toLowerCase();
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: isSelected ? color : color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? color : color.withValues(alpha: 0.25),
                        width: isSelected ? 1.4 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.28),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (!isSelected) {
                            _showChangePriorityDialog(label);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 36),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? Colors.white : color,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePriorityDialog(String newPriority) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.oceanWater.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.flag_rounded, size: 18, color: AppTheme.oceanWater),
            ),
            const SizedBox(width: 10),
            const Text(
              'Ubah Prioritas Tiket',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: 'Apakah Anda yakin ingin mengubah prioritas tiket menjadi ',
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                children: [
                  TextSpan(
                    text: '"$newPriority"',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const TextSpan(text: '? Perubahan ini akan mempengaruhi target penanganan tiket.'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.slateGrey,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanWater,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: const Size(80, 38),
            ),
            child: const Text('Ubah', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await _ticketService.updatePriority(_ticket.id, newPriority);
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            backgroundColor: AppTheme.success,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    res['message'] ?? 'Prioritas berhasil diubah',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
        ref.read(adminTicketProvider.notifier).refresh();
        ref.read(monitorProvider.notifier).refresh();
        await _loadTicketDetail();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            backgroundColor: AppTheme.danger,
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    res['message'] ?? 'Gagal mengubah prioritas',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppTheme.lightBg.withValues(alpha: 0.95),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
