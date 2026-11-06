import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:halo_apu_mobile/core/utils/date_formatter.dart';

part 'ticket_model.freezed.dart';
part 'ticket_model.g.dart';

enum TicketStatus {
  @JsonValue('open') open,
  @JsonValue('on_proses') processing,
  @JsonValue('solve') solved,
  @JsonValue('reject') rejected,
  @JsonValue('dibatalkan') cancelled,
  @JsonValue('pending') pending,
  @JsonValue('need_revision') needRevision,
}

@freezed
sealed class TicketModel with _$TicketModel {
  const factory TicketModel({
    required String id,
    required String title,
    required String description,
    required String category,
    required TicketStatus status,
    required DateTime createdAt,
    required String requesterName,
    String? assignedTo,
    String? attachmentUrl,
    List<TicketReply>? logs,
    List<Map<String, dynamic>>? operators,
    Map<String, dynamic>? csat,
  }) = _TicketModel;

  factory TicketModel.fromJson(Map<String, dynamic> json) => _$TicketModelFromJson(json);

  static TicketModel safeFromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['description'] ??= '';
    map['requesterName'] ??= 'Pengguna';
    map['category'] ??= 'Umum';
    final rawCreatedAt = map['createdAt'] ?? map['created_at'];
    map['createdAt'] = parseToLocal(rawCreatedAt).toIso8601String();
    const extraKeys = [
      'priority',
      'dikembalikan_at',
      'kondisi_kembali',
      'catatan_kembali',
      'wajib_kembali',
      'sla_response_time',
      'sla_resolution_time',
      'sla_response_deadline',
      'sla_resolution_deadline',
      'is_sla_breached',
      'is_breached',
      'is_sla_paused',
      'is_booking_past',
      'booking_end_time',
    ];

    final hasExtraKeys = extraKeys.any((k) => map.containsKey(k) && map[k] != null);
    if (hasExtraKeys || map['description'] is Map) {
      Map<String, dynamic> descMap = {};
      if (map['description'] is Map) {
        descMap = Map<String, dynamic>.from(map['description'] as Map);
      } else if (map['description'] is String && (map['description'] as String).trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(map['description'] as String);
          if (decoded is Map) {
            descMap = Map<String, dynamic>.from(decoded);
          } else {
            descMap['deskripsi'] = map['description'];
          }
        } catch (_) {
          descMap['deskripsi'] = map['description'];
        }
      }
      for (final k in extraKeys) {
        if (map.containsKey(k) && map[k] != null) {
          descMap[k] = map[k];
        }
      }
      map['description'] = jsonEncode(descMap);
    }
    final rawStatus = map['status']?.toString().toLowerCase() ?? 'open';
    switch (rawStatus) {
      case 'on_proses':
      case 'processing':
      case 'assigned':
        map['status'] = 'on_proses';
        break;
      case 'solve':
      case 'solved':
      case 'selesai':
        map['status'] = 'solve';
        break;
      case 'reject':
      case 'rejected':
        map['status'] = 'reject';
        break;
      case 'dibatalkan':
      case 'cancelled':
        map['status'] = 'dibatalkan';
        break;
      case 'need_revision':
        map['status'] = 'need_revision';
        break;
      case 'pending':
        map['status'] = 'pending';
        break;
      default:
        map['status'] = 'open';
    }
    if (map['operators'] is List) {
      map['operators'] = (map['operators'] as List)
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    if (map['logs'] is List) {
      map['logs'] = (map['logs'] as List)
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .map((e) {
            if (e['attachments'] is List) {
              e['attachments'] = (e['attachments'] as List)
                  .map((a) => a is Map ? Map<String, dynamic>.from(a) : null)
                  .whereType<Map<String, dynamic>>()
                  .toList();
            }
            return e;
          })
          .toList();
    }
    return TicketModel.fromJson(map);
  }
}

@freezed
sealed class TicketReply with _$TicketReply {
  const factory TicketReply({
    required int id,
    required String action,
    required String note,
    required DateTime createdAt,
    String? adminName,
    required bool isFromAdmin,
    List<Map<String, dynamic>>? attachments,
  }) = _TicketReply;

  factory TicketReply.fromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    map['id'] = map['id'] is int ? map['id'] : (int.tryParse(map['id']?.toString() ?? '0') ?? 0);
    map['action'] = (map['action'] ?? map['aksi'] ?? '').toString();
    map['note'] = (map['note'] ?? map['catatan'] ?? '').toString();
    final rawCreatedAt = map['createdAt'] ?? map['created_at'];
    map['createdAt'] = parseToLocal(rawCreatedAt).toIso8601String();
    map['isFromAdmin'] = map['isFromAdmin'] == true || map['is_from_admin'] == true;
    if (map['attachments'] is List) {
      map['attachments'] = (map['attachments'] as List)
          .map((a) => a is Map ? Map<String, dynamic>.from(a) : null)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return _$TicketReplyFromJson(map);
  }
}

extension TicketModelX on TicketModel {
  String? get priority => parsedFormData?['priority']?.toString();
  bool get isPengembalianAlat =>
      parsedFormData?['wajib_kembali'] == true ||
      category.toLowerCase().contains('peminjaman') ||
      title.toLowerCase().contains('peminjaman') ||
      parsedFormData?['dikembalikan_at'] != null;
  bool get isKendaraan {
    final cat = category.toLowerCase();
    final tit = title.toLowerCase();
    if (cat.contains('kendaraan') ||
        cat.contains('mobil') ||
        tit.contains('kendaraan') ||
        tit.contains('mobil')) {
      return true;
    }
    final form = parsedFormData;
    if (form != null) {
      for (final key in form.keys) {
        final k = key.toLowerCase();
        if (k.contains('kendaraan') ||
            k.contains('mobil') ||
            k.contains('plat') ||
            k.contains('driver')) {
          return true;
        }
      }
    }
    return false;
  }

  bool get isSchedulePast {
    if (parsedFormData?['is_booking_past'] == true) return true;

    final rawEnd = parsedFormData?['booking_end_time'] ??
        parsedFormData?['tanggal_selesai'] ??
        parsedFormData?['end_time'];
    if (rawEnd != null) {
      final parsed = DateTime.tryParse(rawEnd.toString());
      if (parsed != null) {
        return DateTime.now().isAfter(parsed);
      }
    }

    final form = parsedFormData;
    if (form != null && form.isNotEmpty) {
      String? dateStr;
      String? timeStr;

      for (final entry in form.entries) {
        final key = entry.key.toLowerCase();
        final val = entry.value?.toString().trim();
        if (val == null || val.isEmpty) continue;

        if (dateStr == null && (key.contains('tanggal') || key.contains('tgl'))) {
          if (RegExp(r'\d{4}[-/]\d{1,2}[-/]\d{1,2}').hasMatch(val) ||
              RegExp(r'\d{1,2}[-/]\d{1,2}[-/]\d{4}').hasMatch(val)) {
            dateStr = val;
          }
        }

        if (timeStr == null &&
            (key.contains('kembali') ||
                key.contains('selesai') ||
                key.contains('sampai') ||
                key.contains('pengembalian'))) {
          if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(val)) {
            timeStr = val;
          }
        }
      }

      if (dateStr != null) {
        try {
          DateTime? date;
          if (dateStr.contains('-')) {
            final parts = dateStr.split('-');
            if (parts[0].length == 4) {
              date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
            } else {
              date = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
            }
          } else if (dateStr.contains('/')) {
            final parts = dateStr.split('/');
            if (parts[0].length == 4) {
              date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
            } else {
              date = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
            }
          }

          if (date != null) {
            int hour = 23;
            int minute = 59;
            if (timeStr != null) {
              final tParts = timeStr.split(':');
              hour = int.parse(tParts[0]);
              minute = int.parse(tParts[1]);
            }
            final endDateTime = DateTime(date.year, date.month, date.day, hour, minute);
            return DateTime.now().isAfter(endDateTime);
          }
        } catch (_) {}
      }
    }

    return false;
  }

  bool get isSudahDikembalikan => parsedFormData?['dikembalikan_at'] != null;
  String? get dikembalikanAtFormatted => parsedFormData?['dikembalikan_at']?.toString();
  String? get kondisiKembali => parsedFormData?['kondisi_kembali']?.toString();
  String? get catatanKembali => parsedFormData?['catatan_kembali']?.toString();
  String? get slaResponseTime =>
      parsedFormData?['sla_response_time']?.toString() ??
      parsedFormData?['sla_response_deadline']?.toString();
  String? get slaResolutionTime =>
      parsedFormData?['sla_resolution_time']?.toString() ??
      parsedFormData?['sla_resolution_deadline']?.toString();
  bool get isSlaBreached =>
      parsedFormData?['is_sla_breached'] == true ||
      parsedFormData?['is_breached'] == true;
  bool get isSlaPaused =>
      parsedFormData?['is_sla_paused'] == true || status == TicketStatus.pending;
  String get statusIndonesianLabel {
    switch (status) {
      case TicketStatus.open:
        return 'Menunggu';
      case TicketStatus.processing:
        return 'Diproses';
      case TicketStatus.solved:
        return 'Selesai';
      case TicketStatus.rejected:
        return 'Ditolak';
      case TicketStatus.needRevision:
        return 'Perlu Revisi';
      case TicketStatus.cancelled:
        return 'Dibatalkan';
      case TicketStatus.pending:
        return 'Tertunda';
    }
  }

  Map<String, dynamic>? get parsedFormData {
    if (description.isEmpty) return null;
    try {
      final decoded = jsonDecode(description);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Format ringkasan form data cerdas untuk kartu tiket
  List<MapEntry<String, String>> get summaryItems {
    final map = parsedFormData;
    if (map == null || map.isEmpty) return [];

    final List<MapEntry<String, String>> items = [];

    const internalKeys = {
      'priority',
      'dikembalikan_at',
      'kondisi_kembali',
      'catatan_kembali',
      'wajib_kembali',
      'sla_response_time',
      'sla_resolution_time',
      'sla_response_deadline',
      'sla_resolution_deadline',
      'is_sla_breached',
      'is_breached',
    };

    map.forEach((rawKey, value) {
      if (internalKeys.contains(rawKey)) return;
      if (value == null) return;
      final valStr = value.toString().trim();
      if (valStr.isEmpty) return;

      // Jangan ulangi field jika nilainya persis sama dengan judul tiket
      if (valStr.toLowerCase() == title.toLowerCase()) return;

      // Jika key murni angka (field ID database seperti '57', '58'), kosongkan agar tidak muncul angka aneh
      String cleanKey = '';
      if (int.tryParse(rawKey.trim()) == null) {
        cleanKey = rawKey
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
            .join(' ');
      }

      items.add(MapEntry(cleanKey, valStr));
    });

    return items;
  }

  String get formattedDescription {
    if (description.isEmpty) return '-';
    final items = summaryItems;
    if (items.isNotEmpty) {
      return items.map((e) => e.key.isNotEmpty ? '${e.key}: ${e.value}' : e.value).join(' • ');
    }
    return description;
  }
}
