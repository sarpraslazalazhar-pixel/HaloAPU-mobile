import 'dart:convert';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';

const _categories = [
  'IT Support',
  'General Affair',
  'HR',
  'Keuangan',
  'Operasional',
];

const _requesters = [
  'Budi',
  'Siti',
  'Ahmad',
  'Rina',
  'Dewi',
  'Joko',
  'Maria',
];

const _titles = [
  'AC Ruang Meeting Rusak',
  'Request Akses VPN',
  'Pengajuan Laptop Baru',
  'Install Software Design',
  'Lampu Ruangan Mati',
  'Printer Paper Jam',
  'Reset Password Akun HRIS',
  'Perbaikan Meja Kerja',
  'Gangguan Jaringan WiFi',
  'Penggantian Keyboard Laptop',
  'Request Akses Folder Bersama',
  'Perbaikan Sound System',
  'Cek Kulkas Pantry',
  'Instalasi CCTV',
  'Bantuan Persiapan Zoom Meeting',
];

final _statuses = [
  TicketStatus.open,
  TicketStatus.processing,
  TicketStatus.processing,
  TicketStatus.solved,
  TicketStatus.rejected,
];

List<TicketModel> generateMockTickets({required int count, int startHourOffset = 0}) {
  final now = DateTime.now();
  final tickets = <TicketModel>[
    TicketModel(
      id: 'TKT-LOAN-0001',
      title: 'Peminjaman Proyektor Epson & Kabel HDMI',
      description: jsonEncode({
        'Keperluan': 'Presentasi Klien PT Maju Mundur',
        'Ruangan': 'Meeting Room 2 Lantai 3',
        'wajib_kembali': true,
        'priority': 'Tinggi',
        'sla_response_time': '15 Menit',
        'sla_resolution_time': '2 Jam',
        'is_sla_breached': false,
      }),
      category: 'Peminjaman Alat',
      status: TicketStatus.solved,
      createdAt: now.subtract(const Duration(hours: 4)),
      requesterName: 'Budi Santoso',
      assignedTo: 'Admin IT Support',
    ),
    TicketModel(
      id: 'TKT-LOAN-0002',
      title: 'Peminjaman Laptop Cadangan IT Support',
      description: jsonEncode({
        'Keperluan': 'Uji Coba Testing Lapangan',
        'wajib_kembali': true,
        'dikembalikan_at': '14 Okt 2026, 14:30',
        'kondisi_kembali': 'Baik',
        'catatan_kembali': 'Lengkap adaptor power & mouse wireless',
        'priority': 'Sedang',
        'sla_response_time': '30 Menit',
        'sla_resolution_time': '4 Jam',
        'is_sla_breached': false,
      }),
      category: 'Peminjaman Alat',
      status: TicketStatus.solved,
      createdAt: now.subtract(const Duration(days: 1)),
      requesterName: 'Siti Rahma',
      assignedTo: 'Admin IT Support',
    ),
    TicketModel(
      id: 'TKT-SLA-BREACH',
      title: 'Gangguan Server Database Transaksi',
      description: jsonEncode({
        'Dampak': 'Aplikasi kasir offline di semua terminal',
        'priority': 'Urgen',
        'sla_response_time': '15 Menit',
        'sla_resolution_time': '1 Jam',
        'is_sla_breached': true,
      }),
      category: 'IT Support',
      status: TicketStatus.processing,
      createdAt: now.subtract(const Duration(hours: 3)),
      requesterName: 'Ahmad Manager',
      assignedTo: 'Lead DevOps',
    ),
    TicketModel(
      id: 'TKT-SLA-PAUSED',
      title: 'Penggantian Motherboard PC Kasir Utama',
      description: jsonEncode({
        'Kendala': 'Menunggu konfirmasi kedatangan part dari distributor',
        'priority': 'Tinggi',
        'sla_response_time': '1 Jam',
        'sla_resolution_time': '24 Jam',
        'is_sla_breached': false,
      }),
      category: 'Hardware',
      status: TicketStatus.pending,
      createdAt: now.subtract(const Duration(days: 2)),
      requesterName: 'Dewi Kasir',
      assignedTo: 'Teknisi GA',
    ),
  ];
  for (var i = 0; i < count; i++) {
    final title = _titles[i % _titles.length];
    final created = now.subtract(
      Duration(days: startHourOffset + i ~/ 2, hours: (i * 3) % 24),
    );
    tickets.add(
      TicketModel(
        id: 'TKT-GEN-${(i + 1).toString().padLeft(4, '0')}',
        title: title,
        description:
            'Permintaan bantuan terkait ${title.toLowerCase()}. Mohon ditindaklanjuti, terima kasih.',
        category: _categories[i % _categories.length],
        status: _statuses[i % _statuses.length],
        createdAt: created,
        requesterName: _requesters[i % _requesters.length],
        assignedTo: i % 3 == 0 ? 'Admin IT' : 'Admin GA',
      ),
    );
  }

  return tickets;
}
