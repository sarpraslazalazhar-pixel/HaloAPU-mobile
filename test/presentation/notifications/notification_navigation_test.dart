import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/notification_model.dart';

void main() {
  test('Resolves ticket ID correctly from notification or text regex', () {
    final notifWithDirectId = NotificationModel(
      id: '1',
      title: 'Tiket Diperbarui',
      body: 'Status berubah',
      type: NotificationType.ticket,
      createdAt: DateTime(2026, 11, 9),
      isRead: false,
      ticketId: '603-894-396',
    );

    expect(notifWithDirectId.ticketId?.replaceAll('-', ''), '603894396');

    // Notification without direct ticketId but with regex in body/title
    final notifWithoutDirectId = NotificationModel(
      id: '2',
      title: 'Tiket Baru Berhasil Dibuat #557-466-532',
      body: 'Tiket layanan Support SDM telah diterima',
      type: NotificationType.ticket,
      createdAt: DateTime(2026, 11, 9),
      isRead: false,
      ticketId: null,
    );

    final match = RegExp(r'#?(\d{3}-?\d{3}-?\d{3})|#(\d{9})')
        .firstMatch('${notifWithoutDirectId.title} ${notifWithoutDirectId.body}');
    final extracted = match?.group(1) ?? match?.group(2);
    expect(extracted?.replaceAll('-', ''), '557466532');
  });
}
