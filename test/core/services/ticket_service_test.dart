import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';

/// Adapter palsu: selalu mengembalikan body mentah dengan status tertentu.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusCode, this.body, this.contentType);

  final int statusCode;
  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

TicketService _serviceReturning(int statusCode, String body, String contentType) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..httpClientAdapter = _FakeAdapter(statusCode, body, contentType);
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
}
