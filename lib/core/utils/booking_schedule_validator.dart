/// Validasi rentang tanggal dan waktu pengajuan tiket (peminjaman aset & jadwal).
class ResolvedScheduleFields {
  final String? startDateFieldId;
  final String? endDateFieldId;
  final String? startTimeFieldId;
  final String? endTimeFieldId;

  const ResolvedScheduleFields({
    this.startDateFieldId,
    this.endDateFieldId,
    this.startTimeFieldId,
    this.endTimeFieldId,
  });
}

class BookingScheduleValidator {
  static ResolvedScheduleFields resolveFields(
    Map<String, dynamic>? subUnit,
    List<Map<String, dynamic>> formFields,
  ) {
    String? startDateId = _nonEmptyStr(subUnit?['monitor_date_field_id']);
    String? endDateId = _nonEmptyStr(subUnit?['monitor_end_date_field_id']);
    String? startTimeId = _nonEmptyStr(subUnit?['monitor_start_field_id']);
    String? endTimeId = _nonEmptyStr(subUnit?['monitor_end_field_id']);

    bool hasEndLabel(String label) =>
        label.contains('selesai') ||
        label.contains('kembali') ||
        label.contains('akhir') ||
        label.contains('sampai') ||
        label.contains('end') ||
        label.contains('pulang');

    bool hasStartLabel(String label) =>
        label.contains('mulai') ||
        label.contains('pinjam') ||
        label.contains('berangkat') ||
        label.contains('dari') ||
        label.contains('start');

    // Fallback tanggal mulai
    if (startDateId == null) {
      for (final f in formFields) {
        final type = (f['type'] ?? '').toString().toLowerCase();
        final label = (f['label'] ?? '').toString().toLowerCase();
        final id = _nonEmptyStr(f['id']);
        if (id == null || id == endDateId) continue;
        if (type == 'tanggal' && hasStartLabel(label)) {
          startDateId = id;
          break;
        }
      }
    }
    if (startDateId == null) {
      for (final f in formFields) {
        final type = (f['type'] ?? '').toString().toLowerCase();
        final label = (f['label'] ?? '').toString().toLowerCase();
        final id = _nonEmptyStr(f['id']);
        if (id == null || id == endDateId) continue;
        if (type == 'tanggal' && !hasEndLabel(label)) {
          startDateId = id;
          break;
        }
      }
    }

    // Fallback tanggal selesai
    if (endDateId == null) {
      for (final f in formFields) {
        final type = (f['type'] ?? '').toString().toLowerCase();
        final label = (f['label'] ?? '').toString().toLowerCase();
        final id = _nonEmptyStr(f['id']);
        if (id == null || id == startDateId) continue;
        if (type == 'tanggal' && hasEndLabel(label)) {
          endDateId = id;
          break;
        }
      }
    }

    // Fallback waktu/datetime mulai
    if (startTimeId == null) {
      for (final f in formFields) {
        final type = (f['type'] ?? '').toString().toLowerCase();
        final label = (f['label'] ?? '').toString().toLowerCase();
        final id = _nonEmptyStr(f['id']);
        if (id == null || id == endTimeId) continue;
        if ((type == 'waktu' || type == 'datetime') && hasStartLabel(label)) {
          startTimeId = id;
          break;
        }
      }
    }

    // Fallback waktu/datetime selesai
    if (endTimeId == null) {
      for (final f in formFields) {
        final type = (f['type'] ?? '').toString().toLowerCase();
        final label = (f['label'] ?? '').toString().toLowerCase();
        final id = _nonEmptyStr(f['id']);
        if (id == null || id == startTimeId) continue;
        if ((type == 'waktu' || type == 'datetime') && hasEndLabel(label)) {
          endTimeId = id;
          break;
        }
      }
    }

    return ResolvedScheduleFields(
      startDateFieldId: startDateId,
      endDateFieldId: endDateId,
      startTimeFieldId: startTimeId,
      endTimeFieldId: endTimeId,
    );
  }

  /// Mengembalikan pesan error jika tanggal/waktu selesai tidak valid atau di masa lalu (untuk booking termonitor); null jika valid atau belum lengkap.
  static String? validateScheduleRange({
    Map<String, dynamic>? subUnit,
    required List<Map<String, dynamic>> formFields,
    required Map<String, dynamic> formData,
    DateTime? now,
  }) {
    final fields = resolveFields(subUnit, formFields);
    final isMonitored = subUnit?['is_monitored'] == true ||
        subUnit?['is_monitored'] == 1 ||
        subUnit?['is_monitored'] == '1';
    final currentNow = now ?? DateTime.now();
    final today = DateTime(currentNow.year, currentNow.month, currentNow.day);

    final startDate = parseDateOnly(
      fields.startDateFieldId != null ? formData[fields.startDateFieldId]?.toString() : null,
    );
    final endDate = parseDateOnly(
      fields.endDateFieldId != null ? formData[fields.endDateFieldId]?.toString() : null,
    );

    if (isMonitored && startDate != null && startDate.isBefore(today)) {
      return 'Tanggal mulai tidak boleh di masa lalu.';
    }
    if (isMonitored && endDate != null && endDate.isBefore(today)) {
      return 'Tanggal selesai tidak boleh di masa lalu.';
    }

    if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
      return 'Tanggal selesai tidak boleh sebelum tanggal mulai.';
    }

    final rawStartTime =
        fields.startTimeFieldId != null ? formData[fields.startTimeFieldId]?.toString().trim() : null;
    final rawEndTime =
        fields.endTimeFieldId != null ? formData[fields.endTimeFieldId]?.toString().trim() : null;

    // Jika keduanya merupakan datetime lengkap ("YYYY-MM-DD HH:mm")
    final startFull = parseFullDateTime(rawStartTime);
    final endFull = parseFullDateTime(rawEndTime);
    if (isMonitored && startFull != null && startFull.isBefore(currentNow.subtract(const Duration(minutes: 5)))) {
      return 'Waktu mulai tidak boleh di masa lalu.';
    }
    if (startFull != null && endFull != null) {
      if (!endFull.isAfter(startFull)) {
        return 'Waktu selesai harus lebih besar dari waktu mulai.';
      }
      return null;
    }

    final startMinutes = parseMinutesOfDay(rawStartTime);
    final endMinutes = parseMinutesOfDay(rawEndTime);

    if (isMonitored && startMinutes != null) {
      final effectiveStartDate = startDate ?? today;
      final startDT = DateTime(
        effectiveStartDate.year,
        effectiveStartDate.month,
        effectiveStartDate.day,
        startMinutes ~/ 60,
        startMinutes % 60,
      );
      if (startDT.isBefore(currentNow.subtract(const Duration(minutes: 5)))) {
        return 'Waktu mulai tidak boleh di masa lalu.';
      }
    }

    if (startMinutes != null && endMinutes != null) {
      if (startDate != null && endDate != null) {
        final startDT = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
          startMinutes ~/ 60,
          startMinutes % 60,
        );
        final endDT = DateTime(
          endDate.year,
          endDate.month,
          endDate.day,
          endMinutes ~/ 60,
          endMinutes % 60,
        );
        if (!endDT.isAfter(startDT)) {
          return startDate == endDate
              ? 'Jam selesai harus lebih besar dari jam mulai.'
              : 'Waktu selesai harus lebih besar dari waktu mulai.';
        }
      } else {
        // Satu hari yang sama (tanpa field tanggal selesai terpisah)
        if (endMinutes <= startMinutes) {
          return 'Jam selesai harus lebih besar dari jam mulai.';
        }
      }
    }

    return null;
  }

  /// Tanggal minimum yang diizinkan untuk picker tanggal (hari ini jika subUnit termonitor,
  /// serta minimal sama dengan tanggal mulai jika field adalah tanggal selesai).
  static DateTime? getMinimumDate({
    Map<String, dynamic>? subUnit,
    required List<Map<String, dynamic>> formFields,
    required Map<String, dynamic> formData,
    required String fieldId,
    DateTime? now,
  }) {
    final isMonitored = subUnit?['is_monitored'] == true ||
        subUnit?['is_monitored'] == 1 ||
        subUnit?['is_monitored'] == '1';
    final currentNow = now ?? DateTime.now();
    final today = DateTime(currentNow.year, currentNow.month, currentNow.day);

    final minEnd = getMinimumEndDate(
      subUnit: subUnit,
      formFields: formFields,
      formData: formData,
      fieldId: fieldId,
    );
    if (!isMonitored) return minEnd;

    if (minEnd != null && minEnd.isAfter(today)) {
      return minEnd;
    }
    return today;
  }

  /// Jika [fieldId] adalah field tanggal selesai dan tanggal mulai sudah terisi, kembalikan tanggal mulai.
  static DateTime? getMinimumEndDate({
    Map<String, dynamic>? subUnit,
    required List<Map<String, dynamic>> formFields,
    required Map<String, dynamic> formData,
    required String fieldId,
  }) {
    final fields = resolveFields(subUnit, formFields);
    if (fields.endDateFieldId != fieldId && fields.endTimeFieldId != fieldId) {
      return null;
    }
    final startDate = parseDateOnly(
      fields.startDateFieldId != null ? formData[fields.startDateFieldId]?.toString() : null,
    );
    if (startDate != null) return startDate;
    final startFull = parseFullDateTime(
      fields.startTimeFieldId != null ? formData[fields.startTimeFieldId]?.toString() : null,
    );
    if (startFull != null) {
      return DateTime(startFull.year, startFull.month, startFull.day);
    }
    return null;
  }

  static DateTime? parseDateOnly(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final datePart = raw.trim().split(' ').first;
    final dt = DateTime.tryParse(datePart);
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day);
  }

  static DateTime? parseFullDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{1,2}[:.]\d{2}').hasMatch(trimmed)) {
      return null;
    }
    return DateTime.tryParse(trimmed.replaceAll('.', ':'));
  }

  static int? parseMinutesOfDay(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.trim().split(' ');
    final timePart = parts.length > 1 ? parts.last : parts.first;
    final match = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(timePart);
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static String? _nonEmptyStr(dynamic val) {
    if (val == null) return null;
    final s = val.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }
}
