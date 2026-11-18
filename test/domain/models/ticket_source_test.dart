import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';

Map<String, dynamic> _base(Map<String, dynamic> extra) => {
      'id': '603-894-396',
      'title': 'AC Rusak',
      'description': '',
      'category': 'Umum',
      'status': 'open',
      'createdAt': '2026-11-18T10:00:00Z',
      'requesterName': 'Budi',
      ...extra,
    };

void main() {
  test('source default web bila backend lama belum mengirim field', () {
    final t = TicketModel.safeFromJson(_base({}));
    expect(t.source, 'web');
  });

  test('source mobile dipertahankan dari payload API', () {
    final t = TicketModel.safeFromJson(_base({'source': 'mobile'}));
    expect(t.source, 'mobile');
  });

  test('logs tetap ter-parse walau helper json dibuat manual', () {
    final t = TicketModel.safeFromJson(_base({
      'logs': [
        {
          'id': 7,
          'action': 'assign_operator',
          'note': 'Tiket ditugaskan',
          'createdAt': '2026-11-18T10:05:00Z',
          'isFromAdmin': true,
        }
      ],
    }));
    expect(t.logs, hasLength(1));
    expect(t.logs!.first.note, 'Tiket ditugaskan');
  });
}
