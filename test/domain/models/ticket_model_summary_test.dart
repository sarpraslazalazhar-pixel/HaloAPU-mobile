import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';

void main() {
  test('summaryItems excludes internal SLA and booking metadata keys', () {
    final rawJson = {
      'id': '603894396',
      'title': 'Software',
      'category': 'IT',
      'status': 'solve',
      'description': jsonEncode({
        'Software': 'Microsoft Office',
        'Keterangan Tambahan': 'Tolong instalkan Microsoft Office',
      }),
      'is_sla_paused': false,
      'is_booking_past': false,
      'booking_end_time': '2026-11-09T17:00:00Z',
      'is_sla_breached': false,
      'priority': 'normal',
      'createdAt': '2026-11-09T14:15:00Z',
    };

    final ticket = TicketModel.safeFromJson(rawJson);
    final items = ticket.summaryItems;

    // Must NOT contain internal keys
    final keys = items.map((e) => e.key.toLowerCase()).toList();
    expect(keys.contains('is sla paused'), isFalse);
    expect(keys.contains('is booking past'), isFalse);
    expect(keys.contains('booking end time'), isFalse);
    expect(keys.contains('priority'), isFalse);

    // Must contain only actual form fields
    expect(items.length, equals(2));
    expect(items[0].key, equals('Software'));
    expect(items[0].value, equals('Microsoft Office'));
    expect(items[1].key, equals('Keterangan Tambahan'));
    expect(items[1].value, equals('Tolong instalkan Microsoft Office'));
  });
}
