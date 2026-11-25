import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';
import 'package:image_picker/image_picker.dart';

/// Adapter palsu: selalu mengembalikan body mentah dengan status tertentu
/// dan mencatat RequestOptions terakhir.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusCode, this.body, this.contentType);

  final int statusCode;
  final String body;
  final String contentType;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

TicketService _serviceReturning(
  int statusCode,
  String body,
  String contentType, {
  void Function(_FakeAdapter adapter)? onAdapterCreated,
}) {
  final adapter = _FakeAdapter(statusCode, body, contentType);
  onAdapterCreated?.call(adapter);
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..httpClientAdapter = adapter;
  return TicketService(dio: dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getTicketDetail tidak melempar saat server balas HTML 500', () async {
    final service = _serviceReturning(500, '<html><body>Server Error</body></html>', 'text/html');

    final result = await service.getTicketDetail('160-864-5');

    expect(result['success'], isFalse);
    expect(result['message'], 'Gagal memuat tiket');
  });

  test('getTicketDetail menolak body 200 yang bukan JSON detail', () async {
    final service = _serviceReturning(200, '<html>login</html>', 'text/html');

    final result = await service.getTicketDetail('160-864-5');

    expect(result['success'], isFalse);
  });

  test('getTicketDetail mengembalikan data saat JSON valid', () async {
    final service = _serviceReturning(200, '{"data":{"id":1,"status":"open"}}', 'application/json');

    final result = await service.getTicketDetail('1');

    expect(result['success'], isTrue);
    expect((result['data'] as Map)['status'], 'open');
  });

  test('editTicketReply mengirim PATCH /tickets/{cleanId}/reply/{logId} dengan catatan', () async {
    late _FakeAdapter captured;
    final payload = jsonEncode({
      'data': {
        'id': 42,
        'action': 'balasan',
        'note': 'Pesan telah diperbarui',
        'is_edited': true,
        'edited_at': '2026-11-25T08:50:00Z',
        'adminId': 7,
        'adminName': 'Admin IT',
        'isFromAdmin': true,
      },
      'message': 'Komentar berhasil diperbarui',
    });
    final service = _serviceReturning(
      200,
      payload,
      'application/json',
      onAdapterCreated: (a) => captured = a,
    );

    final result = await service.editTicketReply('160-864-5', 42, '  Pesan telah diperbarui  ');

    expect(result['success'], isTrue);
    expect(captured.lastOptions?.method, 'PATCH');
    expect(captured.lastOptions?.path, '/tickets/1608645/reply/42');
    expect(captured.lastOptions?.data, {'catatan': 'Pesan telah diperbarui'});
    expect((result['data'] as Map)['is_edited'], isTrue);
    expect((result['data'] as Map)['note'], 'Pesan telah diperbarui');
  });

  test('editTicketReply menangani error 422 dan 403 dari server', () async {
    final service422 = _serviceReturning(
      422,
      '{"message":"Tiket sudah ditutup","errors":{"catatan":["Tiket sudah ditutup"]}}',
      'application/json',
    );
    final res422 = await service422.editTicketReply('10', 1, 'Ubah');
    expect(res422['success'], isFalse);
    expect(res422['message'], 'Tiket sudah ditutup');

    final service403 = _serviceReturning(
      403,
      '{"message":"Anda tidak berhak mengedit komentar ini."}',
      'application/json',
    );
    final res403 = await service403.editTicketReply('10', 1, 'Ubah');
    expect(res403['success'], isFalse);
    expect(res403['message'], 'Anda tidak berhak mengedit komentar ini.');
  });

  test('getTickets mengirim tab dan loan_stage saat tab peminjaman_alat', () async {
    late _FakeAdapter captured;
    final service = _serviceReturning(
      200,
      '{"data":[],"meta":{"current_page":1,"last_page":1,"can_view_equipment_loans":true,"peminjaman_alat_count":2,"current_tab":"peminjaman_alat","loan_stage":"menunggu_diserahkan"}}',
      'application/json',
      onAdapterCreated: (a) => captured = a,
    );

    final res = await service.getTickets(
      tab: 'peminjaman_alat',
      loanStage: 'menunggu_diserahkan',
    );

    expect(res['success'], isTrue);
    expect(captured.lastOptions?.path, '/tickets');
    expect(captured.lastOptions?.queryParameters['tab'], 'peminjaman_alat');
    expect(
      captured.lastOptions?.queryParameters['loan_stage'],
      'menunggu_diserahkan',
    );
    expect((res['meta'] as Map)['can_view_equipment_loans'], isTrue);
  });

  test('getLoanRecipients memanggil GET /tickets/loan-recipients', () async {
    late _FakeAdapter captured;
    final service = _serviceReturning(
      200,
      '{"data":{"default_recipient":{"id":1,"name":"Operator GA"},"options":[{"id":12,"name":"Budi","is_requester":true}]}}',
      'application/json',
      onAdapterCreated: (a) => captured = a,
    );

    final res = await service.getLoanRecipients(ticketId: 123, search: 'Budi');

    expect(res['success'], isTrue);
    expect(captured.lastOptions?.path, '/tickets/loan-recipients');
    expect(captured.lastOptions?.queryParameters['ticket_id'], 123);
    expect(captured.lastOptions?.queryParameters['search'], 'Budi');
  });

  test('serahkanAlat dan kembalikanAlat mengirim FormData multipart dengan kondisi kanonis & lampiran[]', () async {
    late _FakeAdapter capturedHandover;
    final handoverService = _serviceReturning(
      200,
      '{"success":true,"message":"Alat diserahkan","data":{"id":"10"}}',
      'application/json',
      onAdapterCreated: (a) => capturedHandover = a,
    );

    final dummyFile = XFile.fromData(
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      name: 'bukti_serah.jpg',
    );

    final handoverRes = await handoverService.serahkanAlat(
      '10-20',
      penerimaUserId: 7,
      kondisi: 'Tidak Lengkap',
      catatan: 'Tas tidak ada',
      attachments: [dummyFile],
    );

    expect(handoverRes['success'], isTrue);
    expect(capturedHandover.lastOptions?.method, 'POST');
    expect(capturedHandover.lastOptions?.path, '/tickets/1020/serahkan-alat');
    final handoverForm = capturedHandover.lastOptions?.data as FormData;
    expect(
      Map.fromEntries(handoverForm.fields)['kondisi_serah'],
      'tidak_lengkap',
    );
    expect(
      Map.fromEntries(handoverForm.fields)['penerima_alat_user_id'],
      '7',
    );
    expect(
      Map.fromEntries(handoverForm.fields)['catatan_serah'],
      'Tas tidak ada',
    );
    expect(handoverForm.files.length, 1);
    expect(handoverForm.files.first.key, 'lampiran[]');

    late _FakeAdapter capturedReturn;
    final returnService = _serviceReturning(
      200,
      '{"success":true,"message":"Alat dikembalikan","data":{"id":"10"}}',
      'application/json',
      onAdapterCreated: (a) => capturedReturn = a,
    );

    final returnRes = await returnService.kembalikanAlat(
      '10-20',
      kondisi: 'Rusak',
      catatan: 'Lensa retak',
      attachments: [dummyFile],
    );

    expect(returnRes['success'], isTrue);
    expect(capturedReturn.lastOptions?.method, 'POST');
    expect(capturedReturn.lastOptions?.path, '/tickets/1020/kembalikan-alat');
    final returnForm = capturedReturn.lastOptions?.data as FormData;
    expect(Map.fromEntries(returnForm.fields)['kondisi_kembali'], 'rusak');
    expect(
      Map.fromEntries(returnForm.fields)['catatan_kembali'],
      'Lensa retak',
    );
    expect(returnForm.files.length, 1);
    expect(returnForm.files.first.key, 'lampiran[]');
  });
}
