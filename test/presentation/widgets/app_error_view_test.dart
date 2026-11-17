import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_error_view.dart';

void main() {
  testWidgets('AppErrorView inline tidak overflow di subtree sempit', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 90,
              child: AppErrorView(error: 'Failed assertion: items == null || items.isEmpty', fullPage: false),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('AppErrorView inline menampilkan judul saat slot cukup', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 180,
              child: AppErrorView(error: 'boom', fullPage: false),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Terjadi Kendala Tampilan'), findsOneWidget);
  });

  testWidgets('AppErrorView fullPage menampilkan aksi pulih', (tester) async {
    var retried = 0;
    var loggedIn = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AppErrorView(
          error: 'boom',
          onRetry: () => retried++,
          onLogin: () => loggedIn++,
        ),
      ),
    );

    expect(find.text('Terjadi Kendala Tampilan'), findsOneWidget);
    await tester.tap(find.text('Muat Ulang'));
    await tester.tap(find.text('Masuk ke Akun'));
    expect(retried, 1);
    expect(loggedIn, 1);
  });
}
