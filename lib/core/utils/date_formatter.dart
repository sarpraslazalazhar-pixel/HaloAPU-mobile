import 'package:intl/intl.dart';

DateTime parseToLocal(dynamic val) {
  if (val == null) return DateTime.now();
  if (val is DateTime) return val.toLocal();
  if (val is String) {
    final s = val.trim();
    if (s.isEmpty) return DateTime.now();

    try {
      final hasZ = s.contains('Z') || s.contains('z');
      final timeIndex = s.contains('T') ? s.indexOf('T') : s.indexOf(' ');
      final hasOffset = timeIndex != -1 &&
          RegExp(r'[+-]\d{2}(?::?\d{2})?$').hasMatch(s);

      if (!hasZ && !hasOffset) {
        if (timeIndex != -1) {
          final normalized = s.replaceFirst(' ', 'T');
          return DateTime.parse('${normalized}Z').toLocal();
        }
      }
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
    }
  }
  return DateTime.now();
}

String formatDateTime(DateTime? dt, {String pattern = 'dd MMM yyyy, HH:mm'}) {
  if (dt == null) return '';
  return DateFormat(pattern).format(dt.toLocal());
}
