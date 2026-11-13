import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/domain/models/csat_model.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/csat_provider.dart';
import 'package:halo_apu_mobile/presentation/dashboard/widgets/pending_rating_section.dart';
import 'package:halo_apu_mobile/presentation/tickets/providers/user_ticket_provider.dart';

class FakeCsatNotifier extends StateNotifier<CsatState> implements CsatNotifier {
  FakeCsatNotifier(List<PendingCsatModel> pending)
      : super(CsatState(pendingCsats: AsyncValue.data(pending)));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserTicketNotifier extends StateNotifier<AsyncValue<List<TicketModel>>>
    implements UserTicketNotifier {
  FakeUserTicketNotifier(List<TicketModel> tickets)
      : super(AsyncValue.data(tickets));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('PendingRatingSection(isAdmin: true) displays pending CSAT from csatProvider only',
      (tester) async {
    final pendingItem = PendingCsatModel(
      id: '101',
      ticketId: 'TKT-0101',
      ticketTitle: 'Permintaan Kabel LAN',
      category: 'IT Support',
      completedAt: '2026-11-13T10:00:00Z',
    );
    final incomingUnitTicket = TicketModel(
      id: '999',
      title: 'Tiket Unit Masuk',
      description: 'Tiket orang lain',
      category: 'Umum',
      status: TicketStatus.solved,
      createdAt: DateTime(2026, 11, 13),
      requesterName: 'Karyawan',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          csatProvider.overrideWith((_) => FakeCsatNotifier([pendingItem])),
          userTicketProvider.overrideWith((_) => FakeUserTicketNotifier([incomingUnitTicket])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PendingRatingSection(isAdmin: true),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Menunggu Penilaian'), findsOneWidget);
    expect(find.text('Permintaan Kabel LAN'), findsOneWidget);
    expect(find.text('Tiket Unit Masuk'), findsNothing);
  });

  testWidgets('PendingRatingSection(isAdmin: true) stays hidden when pending CSAT is empty even if userTicketProvider has solved tickets',
      (tester) async {
    final incomingUnitTicket = TicketModel(
      id: '999',
      title: 'Tiket Unit Masuk',
      description: 'Tiket orang lain',
      category: 'Umum',
      status: TicketStatus.solved,
      createdAt: DateTime(2026, 11, 13),
      requesterName: 'Karyawan',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          csatProvider.overrideWith((_) => FakeCsatNotifier(const [])),
          userTicketProvider.overrideWith((_) => FakeUserTicketNotifier([incomingUnitTicket])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PendingRatingSection(isAdmin: true),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Menunggu Penilaian'), findsNothing);
    expect(find.text('Tiket Unit Masuk'), findsNothing);
  });
}
