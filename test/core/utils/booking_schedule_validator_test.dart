import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/utils/booking_schedule_validator.dart';

void main() {
  final fixedNow = DateTime(2026, 11, 13, 14, 0);

  final roomSubUnit = {
    'id': 2,
    'is_monitored': true,
    'monitor_asset_field_id': '8',
    'monitor_date_field_id': '9',
    'monitor_start_field_id': '10',
    'monitor_end_field_id': '11',
  };

  final carSubUnit = {
    'id': 3,
    'is_monitored': true,
    'monitor_asset_field_id': '14',
    'monitor_date_field_id': '16',
    'monitor_end_date_field_id': '97',
    'monitor_start_field_id': '17',
    'monitor_end_field_id': '18',
  };

  final carFormFields = [
    {'id': '14', 'label': 'Pilih Kendaraan', 'type': 'dropdown'},
    {'id': '16', 'label': 'Tanggal Pinjam', 'type': 'tanggal'},
    {'id': '97', 'label': 'Tanggal Kembali', 'type': 'tanggal'},
    {'id': '17', 'label': 'Jam Mulai', 'type': 'waktu'},
    {'id': '18', 'label': 'Jam Selesai', 'type': 'waktu'},
  ];

  test('rejects past date on monitored booking (e.g. Nov 10 submitted on Nov 13)', () {
    final err = BookingScheduleValidator.validateScheduleRange(
      subUnit: carSubUnit,
      formFields: carFormFields,
      formData: {
        '14': 'APV',
        '16': '2026-11-10',
        '97': '2026-11-10',
        '17': '09:00',
        '18': '12:00',
      },
      now: fixedNow,
    );
    expect(err, equals('Tanggal mulai tidak boleh di masa lalu.'));
  });

  test('rejects past start time on today for monitored booking', () {
    final err = BookingScheduleValidator.validateScheduleRange(
      subUnit: roomSubUnit,
      formFields: const [],
      formData: {
        '8': 'Ruang Rapat',
        '9': '2026-11-13',
        '10': '09:00',
        '11': '11:00',
      },
      now: fixedNow,
    );
    expect(err, equals('Waktu mulai tidak boleh di masa lalu.'));
  });

  test('rejects end time earlier than or equal to start time on same day', () {
    final err = BookingScheduleValidator.validateScheduleRange(
      subUnit: roomSubUnit,
      formFields: const [],
      formData: {
        '8': 'Ruang Rapat',
        '9': '2026-11-14',
        '10': '09:20',
        '11': '09:01',
      },
      now: fixedNow,
    );
    expect(err, equals('Jam selesai harus lebih besar dari jam mulai.'));

    final equalErr = BookingScheduleValidator.validateScheduleRange(
      subUnit: roomSubUnit,
      formFields: const [],
      formData: {
        '9': '2026-11-14',
        '10': '09:20',
        '11': '09:20',
      },
      now: fixedNow,
    );
    expect(equalErr, equals('Jam selesai harus lebih besar dari jam mulai.'));
  });

  test('rejects end date before start date on vehicle booking (tickets.sql repro)', () {
    final err = BookingScheduleValidator.validateScheduleRange(
      subUnit: carSubUnit,
      formFields: carFormFields,
      formData: {
        '14': 'APV',
        '16': '2026-11-14',
        '97': '2026-11-13',
        '17': '09:00',
        '18': '16:31',
      },
      now: fixedNow,
    );
    expect(err, equals('Tanggal selesai tidak boleh sebelum tanggal mulai.'));
  });

  test('allows multi-day vehicle booking even when end clock time is earlier than start clock time', () {
    final err = BookingScheduleValidator.validateScheduleRange(
      subUnit: carSubUnit,
      formFields: carFormFields,
      formData: {
        '14': 'APV',
        '16': '2026-11-14',
        '97': '2026-11-15',
        '17': '09:00',
        '18': '08:00',
      },
      now: fixedNow,
    );
    expect(err, isNull);
  });

  test('getMinimumDate enforces today for monitored start date and max(today, startDate) for end date', () {
    final startMin = BookingScheduleValidator.getMinimumDate(
      subUnit: carSubUnit,
      formFields: carFormFields,
      formData: {},
      fieldId: '16',
      now: fixedNow,
    );
    expect(startMin, DateTime(2026, 11, 13));

    final endMin = BookingScheduleValidator.getMinimumDate(
      subUnit: carSubUnit,
      formFields: carFormFields,
      formData: {'16': '2026-11-15'},
      fieldId: '97',
      now: fixedNow,
    );
    expect(endMin, DateTime(2026, 11, 15));
  });

  test('allows past date on non-monitored incident report forms', () {
    final err = BookingScheduleValidator.validateScheduleRange(
      subUnit: {'id': 10, 'is_monitored': false},
      formFields: const [
        {'id': '1', 'label': 'Tanggal Kejadian', 'type': 'tanggal'},
      ],
      formData: {'1': '2026-11-10'},
      now: fixedNow,
    );
    expect(err, isNull);
  });

  test('validates datetime pairs even without monitored metadata', () {
    final err = BookingScheduleValidator.validateScheduleRange(
      subUnit: null,
      formFields: const [
        {'id': '1', 'label': 'Waktu Mulai', 'type': 'datetime'},
        {'id': '2', 'label': 'Waktu Selesai', 'type': 'datetime'},
      ],
      formData: {
        '1': '2026-11-14 09:20',
        '2': '2026-11-14 09:01',
      },
      now: fixedNow,
    );
    expect(err, isNotNull);
  });
}
