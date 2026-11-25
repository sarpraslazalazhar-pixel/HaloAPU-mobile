import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';

import 'loan_sheet_components.dart';

typedef LoadRecipientsFn = Future<Map<String, dynamic>> Function({
  int? ticketId,
  String? search,
});

class HandoverAssetSheet extends StatefulWidget {
  final String ticketId;
  final String? borrowerName;
  final String? equipmentText;
  final String? scheduleText;
  final Future<bool> Function(
    int? penerimaUserId,
    String kondisi,
    String? catatan,
    List<XFile> attachments,
  ) onConfirm;
  final LoadRecipientsFn? loadRecipients;

  const HandoverAssetSheet({
    super.key,
    required this.ticketId,
    this.borrowerName,
    this.equipmentText,
    this.scheduleText,
    required this.onConfirm,
    this.loadRecipients,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String ticketId,
    String? borrowerName,
    String? equipmentText,
    String? scheduleText,
    required Future<bool> Function(
      int? penerimaUserId,
      String kondisi,
      String? catatan,
      List<XFile> attachments,
    ) onConfirm,
    LoadRecipientsFn? loadRecipients,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HandoverAssetSheet(
        ticketId: ticketId,
        borrowerName: borrowerName,
        equipmentText: equipmentText,
        scheduleText: scheduleText,
        onConfirm: onConfirm,
        loadRecipients: loadRecipients,
      ),
    );
  }

  @override
  State<HandoverAssetSheet> createState() => _HandoverAssetSheetState();
}

class _HandoverAssetSheetState extends State<HandoverAssetSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _catatanController = TextEditingController();
  Timer? _searchDebounce;

  int? _selectedUserId;
  String _kondisiSerah = 'baik';
  List<XFile> _attachments = [];
  bool _isSubmitting = false;

  bool _loadingRecipients = true;
  String? _recipientError;
  Map<String, dynamic>? _defaultRecipient;
  List<Map<String, dynamic>> _recipientOptions = [];

  @override
  void initState() {
    super.initState();
    _fetchRecipients('');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _fetchRecipients(String search) async {
    if (mounted) {
      setState(() {
        _loadingRecipients = true;
        _recipientError = null;
      });
    }

    final loader =
        widget.loadRecipients ?? TicketService().getLoanRecipients;
    final cleanNumericId = int.tryParse(widget.ticketId.replaceAll('-', ''));
    final res = await loader(
      ticketId: cleanNumericId,
      search: search.trim().isEmpty ? null : search.trim(),
    );

    if (!mounted) return;

    if (res['success'] == true && res['data'] is Map) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final defRaw = data['default_recipient'];
      final optsRaw = data['options'];
      setState(() {
        _defaultRecipient =
            defRaw is Map ? Map<String, dynamic>.from(defRaw) : null;
        _recipientOptions = optsRaw is List
            ? optsRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [];
        _loadingRecipients = false;
      });
    } else {
      setState(() {
        _recipientOptions = [];
        _recipientError =
            res['message']?.toString() ?? 'Gagal memuat daftar penerima alat';
        _loadingRecipients = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _fetchRecipients(value);
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final catatan = _catatanController.text.trim();
    final ok = await widget.onConfirm(
      _selectedUserId,
      _kondisiSerah,
      catatan.isEmpty ? null : catatan,
      List<XFile>.from(_attachments),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final defaultName =
        _defaultRecipient?['name']?.toString().trim().isNotEmpty == true
            ? _defaultRecipient!['name'].toString()
            : 'Admin yang sedang login';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + (bottomInset > 0 ? bottomInset : bottomPadding),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFF0284C7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Konfirmasi Serah-Terima Alat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Catat penerima fisik, kondisi awal, dan lampiran serah-terima',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.slateGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TicketLoanSummaryBox(
              ticketId: widget.ticketId,
              borrowerName: widget.borrowerName,
              equipmentText: widget.equipmentText,
              scheduleText: widget.scheduleText,
            ),
            const SizedBox(height: 16),
            const Text(
              'Pengambil / Penerima Alat',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _isSubmitting
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedUserId = null);
                    },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedUserId == null
                      ? const Color(0xFFE0F2FE)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedUserId == null
                        ? const Color(0xFF0284C7)
                        : const Color(0xFFE2E8F0),
                    width: _selectedUserId == null ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Otomatis: $defaultName (Anda)',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Nama otomatis diisi dari akun Anda yang mengklik tombol ini',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.slateGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedUserId == null)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Color(0xFF0284C7),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                color: Colors.white,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(11),
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppTheme.slateGrey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: const InputDecoration(
                              hintText: 'Atau cari & pilih user terdaftar...',
                              hintStyle: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF94A3B8),
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                        if (_loadingRecipients)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 165),
                    child: _recipientOptions.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 12,
                            ),
                            child: Text(
                              _loadingRecipients
                                  ? 'Memuat daftar user...'
                                  : (_recipientError ??
                                      'Tidak ada user terdaftar yang cocok.'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.slateGrey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _recipientOptions.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFF1F5F9),
                            ),
                            itemBuilder: (context, index) {
                              final opt = _recipientOptions[index];
                              final optId = opt['id'] is int
                                  ? opt['id'] as int
                                  : int.tryParse(opt['id']?.toString() ?? '');
                              final isSelected =
                                  optId != null && _selectedUserId == optId;
                              final isRequester = opt['is_requester'] == true;
                              final name = opt['name']?.toString() ?? '-';
                              final username =
                                  opt['username']?.toString() ?? '';
                              final divisi = opt['divisi']?.toString();

                              return InkWell(
                                onTap: _isSubmitting || optId == null
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        setState(() => _selectedUserId = optId);
                                      },
                                child: Container(
                                  color: isSelected
                                      ? const Color(0xFFF0F9FF)
                                      : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.w600,
                                                      color: const Color(
                                                        0xFF1E293B,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (isRequester) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFCCFBF1,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'Pemohon',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF115E59,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '@$username${(divisi != null && divisi.isNotEmpty) ? ' • $divisi' : ''}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.slateGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: Color(0xFF0284C7),
                                        ),
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
            const SizedBox(height: 16),
            LoanConditionSelector(
              label: 'Kondisi Barang Saat Diserahkan',
              value: _kondisiSerah,
              onChanged: (next) => setState(() => _kondisiSerah = next),
            ),
            const SizedBox(height: 16),
            const Text(
              'Keterangan / Catatan Serah-Terima (Opsional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _catatanController,
              maxLines: 3,
              maxLength: 1000,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Lengkap dengan tas, charger, dan kabel HDMI',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.all(12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF0284C7),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LoanAttachmentUploader(
              files: _attachments,
              enabled: !_isSubmitting,
              onChanged: (next) => setState(() => _attachments = next),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Tandai Sudah Dikasih',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
