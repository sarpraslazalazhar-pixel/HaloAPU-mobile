import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/monitor_asset_model.dart';
import 'package:halo_apu_mobile/domain/models/monitor_calendar_model.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/monitor_provider.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/asset_booking_schedule_widget.dart';

class FakeMonitorNotifier extends StateNotifier<MonitorState> implements MonitorNotifier {
  FakeMonitorNotifier(List<MonitorAssetModel> assets, List<MonitorCalendarModel> calendar)
      : super(MonitorState(
          assets: AsyncValue.data(assets),
          calendar: AsyncValue.data(calendar),
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sampleAssets = [
    MonitorAssetModel(
      namaAset: 'Ruang Rapat Utama',
      tipe: 'Ruangan',
      status: 'Sedang Dipakai',
      user: 'Budi Santoso',
      waktu: '09:00 - 11:00',
    ),
    MonitorAssetModel(
      namaAset: 'Ruang Aula',
      tipe: 'Ruangan',
      status: 'Tersedia',
    ),
    MonitorAssetModel(
      namaAset: 'Toyota Avanza B 1234 CD',
      tipe: 'Kendaraan',
      status: 'Dipesan',
      user: 'Siti Aminah',
      waktu: '13:00 - 15:00',
    ),
  ];

  final sampleCalendar = [
    MonitorCalendarModel(
      date: '2026-10-19',
      bookings: [
        MonitorCalendarItemModel(
          id: 1,
          namaAset: 'Ruang Rapat Utama',
          tipe: 'Ruangan',
          status: 'Sedang Dipakai',
          user: 'Budi Santoso',
          waktu: '09:00 - 11:00',
        ),
      ],
    ),
  ];

  final subUnitSample = {
    'id': 10,
    'nama_layanan': 'Pemesanan Ruang Rapat',
    'is_monitored': true,
    'monitor_kategori': 'Ruangan',
    'monitor_asset_field_id': '101',
    'monitor_date_field_id': '102',
    'monitor_start_field_id': '103',
    'monitor_end_field_id': '104',
  };

  Widget createWidget({
    required Map<String, dynamic> formData,
    void Function(bool hasConflict, String? conflictMessage)? onConflictChanged,
  }) {
    return ProviderScope(
      overrides: [
        monitorProvider.overrideWith((ref) => FakeMonitorNotifier(sampleAssets, sampleCalendar)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssetBookingScheduleWidget(
              subUnit: subUnitSample,
              formData: formData,
              onConflictChanged: onConflictChanged,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Menampilkan prompt jika aset belum dipilih', (tester) async {
    await tester.pumpWidget(createWidget(formData: {}));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pilih Ruangan pada formulir'), findsOneWidget);
    expect(find.text('LIVE MONITOR • RUANGAN'), findsOneWidget);
  });

  testWidgets('Menampilkan banner "Sedang Digunakan" ketika aset yang dipakai dipilih', (tester) async {
    await tester.pumpWidget(createWidget(formData: {
      '101': 'Ruang Rapat Utama',
      '102': '2026-10-19',
    }));
    await tester.pumpAndSettle();

    expect(find.text('SEDANG DIGUNAKAN'), findsOneWidget);
    expect(find.textContaining('Budi Santoso'), findsWidgets);
    expect(find.textContaining('Catatan: Anda tetap bisa memesan untuk jam setelahnya'), findsOneWidget);
  });

  testWidgets('Menampilkan banner "Tersedia" ketika aset kosong dipilih', (tester) async {
    await tester.pumpWidget(createWidget(formData: {
      '101': 'Ruang Aula',
      '102': '2026-10-19',
    }));
    await tester.pumpAndSettle();

    expect(find.text('TERSEDIA'), findsOneWidget);
    expect(find.textContaining('Tidak ada kegiatan berlangsung'), findsOneWidget);
  });

  testWidgets('Mendeteksi bentrok jadwal dan menampilkan peringatan merah', (tester) async {
    bool? conflictDetected;
    String? conflictMsg;

    await tester.pumpWidget(createWidget(
      formData: {
        '101': 'Ruang Rapat Utama',
        '102': '2026-10-19',
        '103': '10:00',
        '104': '12:00', // Bentrok dengan 09:00 - 11:00
      },
      onConflictChanged: (hasConflict, msg) {
        conflictDetected = hasConflict;
        conflictMsg = msg;
      },
    ));
    await tester.pumpAndSettle();

    expect(conflictDetected, isTrue);
    expect(conflictMsg, contains('Jadwal Bentrok'));
    expect(find.text('Jadwal Bentrok!'), findsOneWidget);
    expect(find.textContaining('sudah dipesan pada jam 09:00 - 11:00 oleh Budi Santoso'), findsOneWidget);
  });

  testWidgets('Tidak bentrok ketika jam dipesan di luar jadwal terisi (back-to-back)', (tester) async {
    bool? conflictDetected;

    await tester.pumpWidget(createWidget(
      formData: {
        '101': 'Ruang Rapat Utama',
        '102': '2026-10-19',
        '103': '11:00', // Selesai jam 11:00, mulai jam 11:00 -> Aman!
        '104': '13:00',
      },
      onConflictChanged: (hasConflict, msg) {
        conflictDetected = hasConflict;
      },
    ));
    await tester.pumpAndSettle();

    expect(conflictDetected, isFalse);
    expect(find.text('Jadwal Bentrok!'), findsNothing);
  });

  testWidgets('Menampilkan slot bar dan daftar reservasi terjadwal', (tester) async {
    await tester.pumpWidget(createWidget(formData: {
      '101': 'Ruang Rapat Utama',
      '102': '2026-10-19',
    }));
    await tester.pumpAndSettle();

    // 10 slot jam: 08 s/d 17
    expect(find.text('08'), findsOneWidget);
    expect(find.text('09'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);

    // Keterangan legend
    expect(find.text('Tersedia'), findsOneWidget);
    expect(find.text('Terisi'), findsOneWidget);
    expect(find.text('Pilihan Anda'), findsOneWidget);

    // Daftar reservasi
    expect(find.text('09:00 - 11:00'), findsWidgets);
  });
}
