import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/revision_request_sheet.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/ticket_status_timeline.dart';

void main() {
  group('RevisionRequestSheet', () {
    testWidgets('validates empty note and returns RevisionRequestResult on submit', (tester) async {
      RevisionRequestResult? submitted;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  submitted = await RevisionRequestSheet.show(
                    context,
                    revisionCount: 1,
                    maxRevisions: 5,
                  );
                },
                child: const Text('Buka'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();

      expect(find.text('Minta Revisi'), findsOneWidget);
      expect(find.text('Revisi ke-2 dari 5 (sisa kuota: 4)'), findsOneWidget);

      // Submit empty -> shows validation error and stays open
      await tester.tap(find.text('Kirim Revisi'));
      await tester.pump();
      expect(find.text('Catatan alasan revisi wajib diisi.'), findsOneWidget);
      expect(submitted, isNull);

      // Enter note & submit -> pops with result
      await tester.enterText(find.byType(TextField), 'Tolong perbesar logo di banner');
      await tester.tap(find.text('Kirim Revisi'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.note, equals('Tolong perbesar logo di banner'));
      expect(submitted!.attachments, isEmpty);
    });
  });

  group('TicketStatusTimeline needRevision', () {
    testWidgets('shows operator-oriented subtitle for needRevision', (tester) async {
      final ticket = TicketModel(
        id: '123456789',
        title: 'Desain Banner Acara',
        description: '{}',
        category: 'Desain Grafis',
        status: TicketStatus.needRevision,
        createdAt: DateTime(2026, 11, 13, 10, 0),
        requesterName: 'Budi',
        assignedTo: 'Rina (Desainer)',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketStatusTimeline(ticket: ticket),
          ),
        ),
      );

      expect(find.text('Perlu Revisi'), findsNWidgets(2));
      expect(find.text('Revisi sedang ditangani oleh Rina (Desainer).'), findsOneWidget);
    });
  });
}
