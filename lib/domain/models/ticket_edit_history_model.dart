class TicketFieldDiff {
  final String label;
  final dynamic oldValue;
  final dynamic newValue;

  const TicketFieldDiff({required this.label, this.oldValue, this.newValue});

  factory TicketFieldDiff.fromJson(String key, Map<String, dynamic> json) {
    return TicketFieldDiff(
      label: (json['label'] ?? key).toString(),
      oldValue: json['old'],
      newValue: json['new'],
    );
  }

  String get oldLabel => _describe(oldValue);
  String get newLabel => _describe(newValue);

  static String _describe(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '(kosong)';
    if (value is List) {
      return value.isEmpty ? '(kosong)' : value.join(', ');
    }
    if (value is bool) return value ? 'Ya' : 'Tidak';
    return value.toString();
  }
}

class TicketEditHistoryModel {
  final int id;
  final String editedByName;
  final String? editReason;
  final List<TicketFieldDiff> changes;
  final DateTime createdAt;

  const TicketEditHistoryModel({
    required this.id,
    required this.editedByName,
    required this.changes,
    required this.createdAt,
    this.editReason,
  });

  factory TicketEditHistoryModel.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    final changes = <TicketFieldDiff>[];
    if (rawChanges is Map) {
      rawChanges.forEach((key, value) {
        if (value is Map) {
          changes.add(TicketFieldDiff.fromJson(key.toString(), Map<String, dynamic>.from(value)));
        }
      });
    }

    return TicketEditHistoryModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      editedByName: (json['edited_by_name'] ?? 'Admin').toString(),
      editReason: json['edit_reason']?.toString(),
      changes: changes,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now(),
    );
  }

  static List<TicketEditHistoryModel> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => TicketEditHistoryModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
