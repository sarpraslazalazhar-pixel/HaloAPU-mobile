import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';

import 'loan_sheet_components.dart';

class ReturnAssetSheet extends StatefulWidget {
  final String ticketId;
  final bool hasHandedOver;
  final String? borrowerName;
  final String? equipmentText;
  final String? scheduleText;
  final Future<bool> Function(
    String kondisi,
    String? catatan,
    List<XFile> attachments,
  ) onConfirm;

  const ReturnAssetSheet({
    super.key,
    required this.ticketId,
    this.hasHandedOver = true,
    this.borrowerName,
    this.equipmentText,
    this.scheduleText,
    required this.onConfirm,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String ticketId,
    bool hasHandedOver = true,
    String? borrowerName,
    String? equipmentText,
    String? scheduleText,
    required Future<bool> Function(
      String kondisi,
      String? catatan,
      List<XFile> attachments,
    ) onConfirm,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReturnAssetSheet(
        ticketId: ticketId,
        hasHandedOver: hasHandedOver,
        borrowerName: borrowerName,
        equipmentText: equipmentText,
        scheduleText: scheduleText,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<ReturnAssetSheet> createState() => _ReturnAssetSheetState();
}

class _ReturnAssetSheetState extends State<ReturnAssetSheet> {
  String _selectedKondisi = 'baik';
  final TextEditingController _catatanController = TextEditingController();
  List<XFile> _attachments = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final catatan = _catatanController.text.trim();
    final ok = await widget.onConfirm(
      _selectedKondisi,
      catatan.isEmpty ? null : catatan,
      List<XFile>.from(_attachments),
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

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
                    color: const Color(0xFF059669).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.assignment_return_outlined,
                    color: Color(0xFF059669),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pemeriksaan Pengembalian Alat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Konfirmasi kondisi fisik & kelengkapan alat',
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
            if (!widget.hasHandedOver) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Color(0xFF0284C7),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Serah-terima belum ditandai; Anda tetap bisa langsung menyimpan pengembalian alat.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF075985),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            LoanConditionSelector(
              label: 'Kondisi Fisik & Kelengkapan',
              value: _selectedKondisi,
              onChanged: (next) => setState(() => _selectedKondisi = next),
            ),
            const SizedBox(height: 16),
            const Text(
              'Catatan Pemeriksaan / Pengembalian (Opsional)',
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
                hintText:
                    'Contoh: Kabel lengkap dan tas bersih, atau ada goresan halus...',
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
                    color: Color(0xFF059669),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LoanAttachmentUploader(
              files: _attachments,
              enabled: !_isLoading,
              onChanged: (next) => setState(() => _attachments = next),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          key: ValueKey('label'),
                          'Simpan Pengembalian',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
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
