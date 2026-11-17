import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';

const List<String> kTicketPriorities = ['Rendah', 'Sedang', 'Tinggi', 'Urgen'];
const Set<String> _nonEditableTypes = {'upload_gambar', 'upload_file', 'info_peraturan'};

/// Bottom sheet edit formulir tiket (khusus Admin/Superadmin).
/// Mengembalikan `true` jika penyimpanan berhasil.
class TicketEditFormSheet extends StatefulWidget {
  final String ticketId;
  final Map<String, dynamic> initialFormData;
  final List<Map<String, dynamic>> formFields;
  final String? initialPriority;

  const TicketEditFormSheet({
    super.key,
    required this.ticketId,
    required this.initialFormData,
    required this.formFields,
    this.initialPriority,
  });

  @override
  State<TicketEditFormSheet> createState() => _TicketEditFormSheetState();
}

class _TicketEditFormSheetState extends State<TicketEditFormSheet> {
  final TicketService _service = TicketService();
  final TextEditingController _reasonController = TextEditingController();
  late final Map<String, dynamic> _formData;
  late String? _priority;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _formData = Map<String, dynamic>.from(widget.initialFormData);
    _priority = widget.initialPriority;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Alasan perubahan wajib diisi (minimal 5 karakter).');
      return;
    }

    for (final field in _editableFields) {
      if (field['required'] != true) continue;
      final value = _formData[field['id'].toString()];
      final empty = value == null ||
          value.toString().trim().isEmpty ||
          (value is List && value.isEmpty);
      if (empty) {
        setState(() => _error = 'Field "${field['label']}" wajib diisi.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await _service.updateTicketForm(
      widget.ticketId,
      formData: _formData,
      priority: _priority,
      reason: reason,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _saving = false;
      _error = result['message']?.toString() ?? 'Gagal menyimpan perubahan.';
    });
  }

  List<Map<String, dynamic>> get _editableFields =>
      widget.formFields.where((f) {
        if (_nonEditableTypes.contains(f['type']?.toString())) return false;

        final parentId = (f['parentFieldId'] ?? f['parent_field_id'])?.toString();
        if (parentId == null || parentId.isEmpty) return true;

        final parentValue = _formData[parentId];
        final trigger = (f['triggerValue'] ?? f['trigger_value'])?.toString().trim().toLowerCase().replaceAll(RegExp(r'[:\s]+$'), '');
        if (trigger == null) return false;

        if (parentValue is List) {
          return parentValue.any((v) => v.toString().trim().toLowerCase().replaceAll(RegExp(r'[:\s]+$'), '') == trigger);
        }
        return (parentValue ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'[:\s]+$'), '') == trigger;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: AppTheme.oceanWater, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Edit Formulir Tiket',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
                children: [
                  if (_editableFields.isNotEmpty)
                    _SectionCard(
                      icon: Icons.assignment_outlined,
                      title: 'Data Formulir',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _editableFields.map(_buildField).toList(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    icon: Icons.flag_outlined,
                    title: 'Prioritas & Alasan',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _priority,
                          decoration: _decoration('Prioritas'),
                          items: kTicketPriorities
                              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                              .toList(),
                          onChanged: (val) => setState(() => _priority = val),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _reasonController,
                          maxLines: 3,
                          maxLength: 500,
                          decoration: _decoration('Alasan Perubahan *').copyWith(
                            hintText: 'Contoh: Melengkapi lokasi karena informasi awal kurang spesifik.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.oceanWater),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Simpan Perubahan'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _buildField(Map<String, dynamic> field) {
    final key = field['id'].toString();
    final label = field['label']?.toString() ?? 'Field';
    final required = field['required'] == true;
    final type = field['type']?.toString() ?? 'teks_pendek';
    final options = (field['options'] is List)
        ? (field['options'] as List).map((e) => e.toString()).toList()
        : <String>[];

    Widget input;
    switch (type) {
      case 'dropdown':
      case 'radio':
        input = DropdownButtonFormField<String>(
          initialValue: options.contains(_formData[key]) ? _formData[key] as String : null,
          decoration: _decoration(label),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (val) => setState(() => _formData[key] = val),
        );
        break;
      case 'checkbox':
        input = SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: const TextStyle(fontSize: 13)),
          value: _formData[key] == true,
          onChanged: (val) => setState(() => _formData[key] = val),
        );
        break;
      case 'multi_pilih':
        final selected = (_formData[key] is List)
            ? (_formData[key] as List).map((e) => e.toString()).toList()
            : <String>[];
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 6,
              children: options.map((opt) {
                final isOn = selected.contains(opt);
                return FilterChip(
                  label: Text(opt, style: const TextStyle(fontSize: 11.5)),
                  selected: isOn,
                  onSelected: (val) => setState(() {
                    final next = List<String>.from(selected);
                    val ? next.add(opt) : next.remove(opt);
                    _formData[key] = next;
                  }),
                );
              }).toList(),
            ),
          ],
        );
        break;
      case 'angka':
      case 'nominal_rp':
        input = TextFormField(
          initialValue: _formData[key]?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: _decoration(label),
          onChanged: (val) => _formData[key] = val,
        );
        break;
      case 'tanggal':
      case 'datetime':
        final current = _formData[key]?.toString() ?? '';
        input = InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(current) ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked == null) return;
            final dateStr =
                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
            if (type == 'datetime') {
              if (!mounted) return;
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (time == null) return;
              _formData[key] =
                  '$dateStr ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            } else {
              _formData[key] = dateStr;
            }
            setState(() {});
          },
          child: InputDecorator(
            decoration: _decoration(label).copyWith(suffixIcon: const Icon(Icons.event_rounded, size: 18)),
            child: Text(current.isEmpty ? 'Pilih tanggal...' : current),
          ),
        );
        break;
      case 'waktu':
        final current = _formData[key]?.toString() ?? '';
        input = InkWell(
          onTap: () async {
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
            if (time == null) return;
            setState(() {
              _formData[key] =
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            });
          },
          child: InputDecorator(
            decoration: _decoration(label).copyWith(suffixIcon: const Icon(Icons.access_time_rounded, size: 18)),
            child: Text(current.isEmpty ? 'Pilih waktu...' : current),
          ),
        );
        break;
      case 'teks_panjang':
        input = TextFormField(
          initialValue: _formData[key]?.toString() ?? '',
          maxLines: 4,
          maxLength: 2000,
          decoration: _decoration(label),
          onChanged: (val) => _formData[key] = val,
        );
        break;
      default:
        input = TextFormField(
          initialValue: _formData[key]?.toString() ?? '',
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(255)],
          decoration: _decoration(label),
          onChanged: (val) => _formData[key] = val,
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: type == 'checkbox' || type == 'multi_pilih'
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                input,
                if (required)
                  const Text('* wajib diisi', style: TextStyle(fontSize: 10.5, color: AppTheme.danger)),
              ],
            )
          : input,
    );
  }
}

/// Kartu bersekat untuk mengelompokkan isian di dalam sheet.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
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
              Icon(icon, size: 15, color: AppTheme.oceanWater),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
