import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';

class ReturnAssetSheet extends StatefulWidget {
  final String ticketId;
  final Future<bool> Function(String kondisi, String? catatan) onConfirm;

  const ReturnAssetSheet({
    super.key,
    required this.ticketId,
    required this.onConfirm,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String ticketId,
    required Future<bool> Function(String kondisi, String? catatan) onConfirm,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReturnAssetSheet(ticketId: ticketId, onConfirm: onConfirm),
    );
  }

  @override
  State<ReturnAssetSheet> createState() => _ReturnAssetSheetState();
}

class _ReturnAssetSheetState extends State<ReturnAssetSheet> {
  String _selectedKondisi = 'Baik';
  final TextEditingController _catatanController = TextEditingController();
  bool _isLoading = false;

  final List<Map<String, dynamic>> _kondisiOptions = [
    {
      'label': 'Baik',
      'icon': Icons.check_circle_outline,
      'color': AppTheme.success,
      'desc': 'Alat berfungsi normal & lengkap',
    },
    {
      'label': 'Rusak',
      'icon': Icons.broken_image_outlined,
      'color': AppTheme.danger,
      'desc': 'Ada kerusakan fisik / fungsi',
    },
    {
      'label': 'Tidak Lengkap',
      'icon': Icons.warning_amber_rounded,
      'color': AppTheme.warning,
      'desc': 'Aksesoris / kelengkapan kurang',
    },
  ];

  @override
  void dispose() {
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    final catatan = _catatanController.text.trim();
    final ok = await widget.onConfirm(
      _selectedKondisi,
      catatan.isEmpty ? null : catatan,
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

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
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
                    color: AppTheme.oceanWater.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_return_outlined, color: AppTheme.oceanWater, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pengembalian Alat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Konfirmasi kondisi alat yang dipinjam',
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
            const SizedBox(height: 18),
            const Text(
              'Kondisi Alat Saat Ini',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: _kondisiOptions.map((opt) {
                final isSelected = _selectedKondisi == opt['label'];
                final color = opt['color'] as Color;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedScale(
                      scale: isSelected ? 1.03 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        constraints: const BoxConstraints(minHeight: 68),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.12)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? color : const Color(0xFFE2E8F0),
                            width: isSelected ? 1.6 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedKondisi = opt['label'] as String);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      opt['icon'] as IconData,
                                      key: ValueKey('${opt['label']}_$isSelected'),
                                      size: 22,
                                      color: isSelected ? color : AppTheme.slateGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    opt['label'] as String,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isSelected ? color : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
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
            Builder(
              builder: (context) {
                final selectedOption = _kondisiOptions.firstWhere(
                  (opt) => opt['label'] == _selectedKondisi,
                  orElse: () => _kondisiOptions.first,
                );
                final desc = selectedOption['desc'] as String?;
                if (desc == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      key: ValueKey(desc),
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 13,
                          color: selectedOption['color'] as Color,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Catatan Pengembalian (Opsional)',
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
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Contoh: Kabel power lengkap, kondisi mulus...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.all(12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
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
                  borderSide: const BorderSide(color: AppTheme.oceanWater, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.oceanWater,
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          key: ValueKey('label'),
                          'Konfirmasi Pengembalian Alat',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
