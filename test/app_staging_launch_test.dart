import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/main.dart';
import 'package:halo_apu_mobile/presentation/auth/login_screen.dart';

void main() {
  testWidgets('HaloApuApp launches successfully in staging flavor with Banner', (tester) async {
    expect(FlavorConfig.isStaging, isTrue);

    // Pump HaloApuApp within ProviderScope
    await tester.pumpWidget(
      const ProviderScope(
        child: HaloApuApp(),
      ),
    );

    // Ensure initial build produces no exceptions
    expect(tester.takeException(), isNull);

    // Verify Banner is present and configured with STAGING message
    final bannerFinder = find.byWidgetPredicate(
      (widget) => widget is Banner && widget.message == 'STAGING',
    );
    expect(bannerFinder, findsOneWidget);

    // Advance past splash animations and safety timer
    await tester.pump(const Duration(milliseconds: 3500));
    // Advance past router redirect and secure storage timeout
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Verify navigation successfully lands on LoginScreen
    expect(find.byType(LoginScreen), findsOneWidget);
    // Banner remains visible above child
    expect(bannerFinder, findsOneWidget);
  });
}
