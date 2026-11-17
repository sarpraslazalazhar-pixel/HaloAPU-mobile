import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/domain/models/rating_model.dart';
import 'package:halo_apu_mobile/presentation/ratings/providers/rating_provider.dart';
import 'package:halo_apu_mobile/presentation/ratings/rating_history_screen.dart';

class _StubNotifier extends StateNotifier<AsyncValue<List<RatingModel>>>
    implements RatingNotifier {
  _StubNotifier(List<RatingModel> r) : super(AsyncValue.data(r));
  @override
  bool get hasMore => false;
  @override
  bool get isLoadingMore => false;
  @override
  Future<void> loadMore() async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  testWidgets('header, kartu rating & bottom nav tidak overflow di 320dp', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
    addTearDown(() => FlutterError.onError = original);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        adminRatingProvider.overrideWith((ref) => _StubNotifier([
          RatingModel(
            id: '1',
            ticketId: 't',
            ticketTitle: 'Software',
            category: 'Maintenance Hardware & Software & Jaringan Komputer Kantor Pusat',
            score: 5,
            comment: 'Mantual. Terimakasih',
            createdAt: DateTime(2026, 11, 9),
          ),
        ])),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RatingHistoryScreen(isAdmin: true),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));

    expect(errors, isEmpty, reason: errors.join('\n---\n'));
    expect(find.text('Rating dari Karyawan'), findsOneWidget);
  });
}
