import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/presentation/widgets/animated_success_check.dart';

void main() {
  testWidgets('AnimatedSuccessCheck completes animation and calls onCompleted', (tester) async {
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedSuccessCheck(
              duration: const Duration(milliseconds: 950),
              onCompleted: () => completed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedSuccessCheck), findsOneWidget);
    expect(completed, isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    expect(completed, isFalse);

    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('showTicketSuccessDialog displays and auto-dismisses cleanly', (tester) async {
    late BuildContext capturedContext;
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final future = showTicketSuccessDialog(
      capturedContext,
      holdDuration: const Duration(milliseconds: 1200),
    ).then((_) => finished = true);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AnimatedSuccessCheck), findsOneWidget);
    expect(find.text('Tiket Berhasil Dibuat'), findsOneWidget);
    expect(finished, isFalse);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    await future;

    expect(finished, isTrue);
    expect(find.byType(AnimatedSuccessCheck), findsNothing);
  });
}
