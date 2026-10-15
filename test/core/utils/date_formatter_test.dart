import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/utils/date_formatter.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:intl/intl.dart';

void main() {
  group('date_formatter tests', () {
    final expectedLocal = DateTime.utc(2026, 10, 15, 6, 55).toLocal();

    test('parseToLocal handles ISO string with Z', () {
      final dt = parseToLocal('2026-10-15T06:55:00Z');
      expect(dt.isUtc, isFalse);
      expect(dt, equals(expectedLocal));
    });

    test('parseToLocal handles SQL format without Z as UTC', () {
      final dt = parseToLocal('2026-10-15 06:55:00');
      expect(dt.isUtc, isFalse);
      expect(dt, equals(expectedLocal));
    });

    test('parseToLocal handles ISO without Z as UTC', () {
      final dt = parseToLocal('2026-10-15T06:55:00');
      expect(dt.isUtc, isFalse);
      expect(dt, equals(expectedLocal));
    });

    test('parseToLocal handles ISO with microsecond and Z', () {
      final dt = parseToLocal('2026-10-15T06:55:00.000000Z');
      expect(dt.isUtc, isFalse);
      expect(dt, equals(expectedLocal));
    });

    test('parseToLocal handles string with timezone offset', () {
      final dt = parseToLocal('2026-10-15T06:55:00+00:00');
      expect(dt.isUtc, isFalse);
      expect(dt, equals(expectedLocal));
    });

    test('parseToLocal handles DateTime object', () {
      final utc = DateTime.utc(2026, 10, 15, 6, 55);
      final dt = parseToLocal(utc);
      expect(dt.isUtc, isFalse);
      expect(dt, equals(expectedLocal));
    });

    test('parseToLocal handles null and empty string', () {
      final before = DateTime.now();
      final dtNull = parseToLocal(null);
      final dtEmpty = parseToLocal('');
      final after = DateTime.now();

      expect(dtNull.isUtc, isFalse);
      expect(dtEmpty.isUtc, isFalse);
      expect(dtNull.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(dtNull.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('formatDateTime formats local time correctly', () {
      final utc = DateTime.utc(2026, 10, 15, 6, 55);
      final formatted = formatDateTime(utc, pattern: 'HH:mm');
      final expectedHour = DateFormat('HH:mm').format(expectedLocal);
      expect(formatted, equals(expectedHour));
    });

    test('formatDateTime returns empty string on null', () {
      expect(formatDateTime(null), equals(''));
    });

    test('TicketModel.safeFromJson parses UTC createdAt and logs to local time', () {
      final ticket = TicketModel.safeFromJson({
        'id': 'T-001',
        'title': 'Test Ticket',
        'status': 'open',
        'createdAt': '2026-10-15 06:55:00',
        'logs': [
          {
            'id': 1,
            'action': 'reply',
            'note': 'Pesan balasan',
            'createdAt': '2026-10-15T06:55:00.000000Z',
            'isFromAdmin': true,
          }
        ],
      });

      expect(ticket.createdAt.isUtc, isFalse);
      expect(ticket.createdAt, equals(expectedLocal));
      expect(ticket.logs, isNotNull);
      expect(ticket.logs!.first.createdAt.isUtc, isFalse);
      expect(ticket.logs!.first.createdAt, equals(expectedLocal));
    });

    test('TicketReply.fromJson parses UTC createdAt to local time', () {
      final reply = TicketReply.fromJson({
        'id': 2,
        'action': 'note',
        'note': 'Catatan',
        'created_at': '2026-10-15 06:55:00',
        'isFromAdmin': false,
      });

      expect(reply.createdAt.isUtc, isFalse);
      expect(reply.createdAt, equals(expectedLocal));
    });
  });
}
