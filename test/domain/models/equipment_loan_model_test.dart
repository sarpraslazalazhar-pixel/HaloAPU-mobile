import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';

void main() {
  test('TicketModel.safeFromJson parses all equipment loan handover & return fields', () {
    final rawJson = {
      'id': '160-864-5',
      'title': 'Peminjaman Alat',
      'category': 'Peminjaman Alat',
      'status': 'solve',
      'createdAt': '2026-11-25T08:00:00Z',
      'requesterName': 'Budi Peminjam',
      'description': jsonEncode({
        'Pilih Alat': 'Infokus, Kabel HDMI',
        'Keperluan': 'Rapat Divisi',
      }),
      'wajib_kembali': true,
      'diserahkan_at': '25 Nov 2026, 09:00',
      'diserahkan_oleh': 'Operator GA',
      'penerima_alat': 'Budi Peminjam',
      'penerima_alat_user_id': 15,
      'kondisi_serah': 'tidak_lengkap',
      'catatan_serah': 'Tas proyektor tidak tersedia',
      'dikembalikan_at': '25 Nov 2026, 17:00',
      'diterima_kembali_oleh': 'Supervisor GA',
      'kondisi_kembali': 'rusak',
      'catatan_kembali': 'Port HDMI longgar',
      'status_peminjaman': 'Dikembalikan',
      'alat_text': 'Infokus, Kabel HDMI',
      'rentang_waktu': '25 Nov 2026 - 25 Nov 2026',
      'can_serahkan': false,
      'can_kembalikan': false,
      'lampiran_serah': [
        {
          'id': 1,
          'fileName': 'foto_serah.jpg',
          'mimeType': 'image/jpeg',
          'fileSize': 10240,
          'path': 'storage/ticket-attachments/1/serah.jpg',
          'url': 'http://localhost/storage/ticket-attachments/1/serah.jpg',
        },
      ],
      'lampiran_kembali': [
        {
          'id': 2,
          'fileName': 'berita_acara.pdf',
          'mimeType': 'application/pdf',
          'fileSize': 20480,
          'path': 'storage/ticket-attachments/1/kembali.pdf',
          'url': 'http://localhost/storage/ticket-attachments/1/kembali.pdf',
        },
      ],
    };

    final ticket = TicketModel.safeFromJson(rawJson);

    expect(ticket.isPengembalianAlat, isTrue);
    expect(ticket.isSudahDiserahkan, isTrue);
    expect(ticket.diserahkanAtFormatted, '25 Nov 2026, 09:00');
    expect(ticket.diserahkanOleh, 'Operator GA');
    expect(ticket.penerimaAlat, 'Budi Peminjam');
    expect(ticket.penerimaAlatUserId, 15);
    expect(ticket.kondisiSerah, 'tidak_lengkap');
    expect(ticket.catatanSerah, 'Tas proyektor tidak tersedia');
    expect(ticket.isSudahDikembalikan, isTrue);
    expect(ticket.dikembalikanAtFormatted, '25 Nov 2026, 17:00');
    expect(ticket.diterimaKembaliOleh, 'Supervisor GA');
    expect(ticket.kondisiKembali, 'rusak');
    expect(ticket.catatanKembali, 'Port HDMI longgar');
    expect(ticket.statusPeminjaman, 'Dikembalikan');
    expect(ticket.alatText, 'Infokus, Kabel HDMI');
    expect(ticket.rentangWaktu, '25 Nov 2026 - 25 Nov 2026');
    expect(ticket.canSerahkan, isFalse);
    expect(ticket.canKembalikan, isFalse);
    expect(ticket.lampiranSerah.length, 1);
    expect(ticket.lampiranSerah.first['fileName'], 'foto_serah.jpg');
    expect(ticket.lampiranKembali.length, 1);
    expect(ticket.lampiranKembali.first['fileName'], 'berita_acara.pdf');

    // summaryItems must not leak any internal loan keys
    final summaryKeys = ticket.summaryItems.map((e) => e.key.toLowerCase()).toList();
    expect(summaryKeys, containsAll(['pilih alat', 'keperluan']));
    expect(summaryKeys.length, 2);
  });

  test('normalizeKondisiKey and formatKondisiLabel normalize canonical and legacy labels', () {
    expect(TicketModel.normalizeKondisiKey('baik'), 'baik');
    expect(TicketModel.normalizeKondisiKey('Baik'), 'baik');
    expect(TicketModel.normalizeKondisiKey('Bagus (Baik)'), 'baik');
    expect(TicketModel.normalizeKondisiKey('tidak_lengkap'), 'tidak_lengkap');
    expect(TicketModel.normalizeKondisiKey('Tidak Lengkap'), 'tidak_lengkap');
    expect(TicketModel.normalizeKondisiKey('Kurang Lengkap'), 'tidak_lengkap');
    expect(TicketModel.normalizeKondisiKey('rusak'), 'rusak');
    expect(TicketModel.normalizeKondisiKey('Rusak'), 'rusak');
    expect(TicketModel.normalizeKondisiKey(null), 'baik');

    expect(TicketModel.formatKondisiLabel('baik'), 'Bagus (Baik)');
    expect(TicketModel.formatKondisiLabel('tidak_lengkap'), 'Kurang Lengkap');
    expect(TicketModel.formatKondisiLabel('tidak lengkap'), 'Kurang Lengkap');
    expect(TicketModel.formatKondisiLabel('rusak'), 'Rusak');
    expect(TicketModel.formatKondisiLabel(null), 'Bagus (Baik)');
  });
}
