import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/equipment_loan_card.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/handover_asset_sheet.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/return_asset_sheet.dart';
import 'package:image_picker/image_picker.dart';

TicketModel _makeLoanTicket({
  String status = 'solve',
  String? statusPeminjaman,
  bool canSerahkan = false,
  bool canKembalikan = false,
  String? diserahkanAt,
  String? diserahkanOleh,
  String? penerimaAlat,
  String? kondisiSerah,
  String? catatanSerah,
  String? dikembalikanAt,
  String? diterimaKembaliOleh,
  String? kondisiKembali,
  String? catatanKembali,
  List<Map<String, dynamic>>? lampiranSerah,
  List<Map<String, dynamic>>? lampiranKembali,
}) {
  return TicketModel.safeFromJson({
    'id': '160-864-5',
    'title': 'Peminjaman Alat',
    'category': 'Peminjaman Alat',
    'status': status,
    'createdAt': '2026-11-25T08:00:00Z',
    'requesterName': 'Budi Peminjam',
    'wajib_kembali': true,
    'alat_text': 'Infokus, Kabel HDMI',
    'rentang_waktu': '25 Nov 2026 - 26 Nov 2026',
    'status_peminjaman': statusPeminjaman,
    'can_serahkan': canSerahkan,
    'can_kembalikan': canKembalikan,
    'diserahkan_at': diserahkanAt,
    'diserahkan_oleh': diserahkanOleh,
    'penerima_alat': penerimaAlat,
    'kondisi_serah': kondisiSerah,
    'catatan_serah': catatanSerah,
    'dikembalikan_at': dikembalikanAt,
    'diterima_kembali_oleh': diterimaKembaliOleh,
    'kondisi_kembali': kondisiKembali,
    'catatan_kembali': catatanKembali,
    'lampiran_serah': lampiranSerah,
    'lampiran_kembali': lampiranKembali,
  });
}

void main() {
  testWidgets('EquipmentLoanCard admin mode shows handover & direct return buttons when awaiting handover', (tester) async {
    var handoverTapped = false;
    var returnTapped = false;

    final ticket = _makeLoanTicket(
      statusPeminjaman: 'Menunggu Diserahkan',
      canSerahkan: true,
      canKembalikan: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EquipmentLoanCard(
              ticket: ticket,
              canManage: true,
              onHandover: () => handoverTapped = true,
              onReturn: () => returnTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Siklus Peminjaman Alat'), findsOneWidget);
    expect(find.text('Menunggu Diserahkan'), findsOneWidget);
    expect(find.text('Tandai Sudah Dikasih'), findsOneWidget);
    expect(find.text('Langsung Tandai Dikembalikan'), findsOneWidget);
    expect(find.text('Tandai Sudah Dikembalikan'), findsNothing);

    await tester.tap(find.text('Tandai Sudah Dikasih'));
    expect(handoverTapped, isTrue);

    await tester.tap(find.text('Langsung Tandai Dikembalikan'));
    expect(returnTapped, isTrue);
  });

  testWidgets('EquipmentLoanCard admin mode shows return button only after handover', (tester) async {
    var returnTapped = false;

    final ticket = _makeLoanTicket(
      statusPeminjaman: 'Sedang Dipinjam',
      canSerahkan: false,
      canKembalikan: true,
      diserahkanAt: '25 Nov 2026, 09:00',
      diserahkanOleh: 'Operator GA',
      penerimaAlat: 'Budi Peminjam',
      kondisiSerah: 'baik',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EquipmentLoanCard(
              ticket: ticket,
              canManage: true,
              onReturn: () => returnTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Sedang Dipinjam'), findsOneWidget);
    expect(find.text('Tandai Sudah Dikasih'), findsNothing);
    expect(find.text('Langsung Tandai Dikembalikan'), findsNothing);
    expect(find.text('Tandai Sudah Dikembalikan'), findsOneWidget);
    expect(find.text('Bagus (Baik)'), findsOneWidget);
    expect(find.text('Penerima: Budi Peminjam'), findsOneWidget);

    await tester.tap(find.text('Tandai Sudah Dikembalikan'));
    expect(returnTapped, isTrue);
  });

  testWidgets('EquipmentLoanCard user mode (canManage=false) is read-only and displays condition, notes & attachments', (tester) async {
    final ticket = _makeLoanTicket(
      statusPeminjaman: 'Dikembalikan',
      canSerahkan: true,
      canKembalikan: true,
      diserahkanAt: '25 Nov 2026, 09:00',
      diserahkanOleh: 'Operator GA',
      penerimaAlat: 'Budi Peminjam',
      kondisiSerah: 'tidak_lengkap',
      catatanSerah: 'Tas belum dibawa',
      dikembalikanAt: '25 Nov 2026, 17:00',
      diterimaKembaliOleh: 'Supervisor GA',
      kondisiKembali: 'rusak',
      catatanKembali: 'Lensa tergores',
      lampiranSerah: [
        {'id': 1, 'fileName': 'dokumen_serah.pdf', 'mimeType': 'application/pdf', 'fileSize': 4096},
      ],
      lampiranKembali: [
        {'id': 2, 'fileName': 'dokumen_kembali.pdf', 'mimeType': 'application/pdf', 'fileSize': 8192},
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EquipmentLoanCard(
              ticket: ticket,
              canManage: false,
            ),
          ),
        ),
      ),
    );

    // No action buttons in read-only mode
    expect(find.text('Tandai Sudah Dikasih'), findsNothing);
    expect(find.text('Langsung Tandai Dikembalikan'), findsNothing);
    expect(find.text('Tandai Sudah Dikembalikan'), findsNothing);

    expect(find.text('Dikembalikan'), findsOneWidget);
    expect(find.text('Kurang Lengkap'), findsOneWidget);
    expect(find.text('Rusak'), findsOneWidget);
    expect(find.text('"Tas belum dibawa"'), findsOneWidget);
    expect(find.text('"Lensa tergores"'), findsOneWidget);
    expect(find.text('Lampiran Serah-Terima (1)'), findsOneWidget);
    expect(find.text('Lampiran Pengembalian (1)'), findsOneWidget);
    expect(find.text('dokumen_serah.pdf'), findsOneWidget);
    expect(find.text('dokumen_kembali.pdf'), findsOneWidget);
  });

  testWidgets('EquipmentLoanCard shows shortcut badge when returned directly without handover', (tester) async {
    final ticket = _makeLoanTicket(
      statusPeminjaman: 'Dikembalikan',
      dikembalikanAt: '25 Nov 2026, 17:00',
      kondisiKembali: 'baik',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EquipmentLoanCard(ticket: ticket, canManage: false),
          ),
        ),
      ),
    );

    expect(find.text('Langsung dikembalikan'), findsOneWidget);
    expect(find.text('Bagus (Baik)'), findsOneWidget);
  });

  testWidgets('HandoverAssetSheet selects recipient & canonical condition and submits', (tester) async {
    int? submittedUserId;
    String? submittedKondisi;
    String? submittedCatatan;
    List<XFile>? submittedFiles;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HandoverAssetSheet(
            ticketId: '160-864-5',
            borrowerName: 'Budi Peminjam',
            equipmentText: 'Infokus',
            scheduleText: '25 Nov 2026',
            loadRecipients: ({int? ticketId, String? search}) async => {
              'success': true,
              'data': {
                'default_recipient': {'id': 1, 'name': 'Operator GA', 'username': 'ga_op'},
                'options': [
                  {
                    'id': 15,
                    'name': 'Budi Peminjam',
                    'username': 'budi',
                    'divisi': 'Marketing',
                    'is_requester': true,
                  },
                ],
              },
            },
            onConfirm: (userId, kondisi, catatan, attachments) async {
              submittedUserId = userId;
              submittedKondisi = kondisi;
              submittedCatatan = catatan;
              submittedFiles = attachments;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Otomatis: Operator GA (Anda)'), findsOneWidget);
    expect(find.text('Pemohon'), findsOneWidget);

    await tester.tap(find.text('Budi Peminjam').last);
    await tester.tap(find.text('Kurang Lengkap'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Lengkap dengan tas, charger, dan kabel HDMI'),
      'Tas tertinggal',
    );
    await tester.ensureVisible(find.text('Tandai Sudah Dikasih'));
    await tester.tap(find.text('Tandai Sudah Dikasih'));
    await tester.pumpAndSettle();

    expect(submittedUserId, 15);
    expect(submittedKondisi, 'tidak_lengkap');
    expect(submittedCatatan, 'Tas tertinggal');
    expect(submittedFiles, isEmpty);
  });

  testWidgets('ReturnAssetSheet displays direct-return banner when not handed over and submits canonical condition', (tester) async {
    String? submittedKondisi;
    String? submittedCatatan;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReturnAssetSheet(
            ticketId: '160-864-5',
            hasHandedOver: false,
            borrowerName: 'Budi Peminjam',
            equipmentText: 'Infokus',
            scheduleText: '25 Nov 2026',
            onConfirm: (kondisi, catatan, attachments) async {
              submittedKondisi = kondisi;
              submittedCatatan = catatan;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Serah-terima belum ditandai; Anda tetap bisa langsung menyimpan pengembalian alat.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Rusak'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Contoh: Kabel lengkap dan tas bersih, atau ada goresan halus...'),
      'Lensa retak',
    );
    await tester.ensureVisible(find.text('Simpan Pengembalian'));
    await tester.tap(find.text('Simpan Pengembalian'));
    await tester.pumpAndSettle();

    expect(submittedKondisi, 'rusak');
    expect(submittedCatatan, 'Lensa retak');
  });
}
