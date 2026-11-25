import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/chat_bubble.dart';
import 'package:halo_apu_mobile/presentation/tickets/widgets/edit_comment_sheet.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  group('TicketReply.fromJson', () {
    test('parses is_edited, edited_at, adminId, and admin_id safely', () {
      final editedReply = TicketReply.fromJson({
        'id': 15,
        'action': 'balasan',
        'note': 'Sudah diperbaiki',
        'createdAt': '2026-11-25T01:00:00Z',
        'adminId': '7',
        'adminName': 'Admin IT',
        'isFromAdmin': true,
        'is_edited': true,
        'edited_at': '2026-11-25T01:30:00Z',
      });

      expect(editedReply.id, 15);
      expect(editedReply.adminId, 7);
      expect(editedReply.isFromAdmin, isTrue);
      expect(editedReply.isEdited, isTrue);
      expect(editedReply.editedAt, isNotNull);

      final plainReply = TicketReply.fromJson({
        'id': 16,
        'aksi': 'balasan',
        'catatan': 'Komentar user',
        'created_at': '2026-11-25T02:00:00Z',
        'admin_id': null,
        'is_from_admin': false,
      });

      expect(plainReply.id, 16);
      expect(plainReply.adminId, isNull);
      expect(plainReply.isFromAdmin, isFalse);
      expect(plainReply.isEdited, isFalse);
      expect(plainReply.editedAt, isNull);
    });
  });

  group('ChatBubble edit indicator and permissions', () {
    final baseTime = DateTime(2026, 11, 25, 9, 15);

    testWidgets('shows (diedit) on edited bubbles for both self and other, hides when false',
        (tester) async {
      final myEdited = TicketReply(
        id: 1,
        action: 'balasan',
        note: 'Komentar saya diedit',
        createdAt: baseTime,
        isFromAdmin: false,
        isEdited: true,
        editedAt: baseTime.add(const Duration(minutes: 5)),
      );
      final otherEdited = TicketReply(
        id: 2,
        action: 'balasan',
        note: 'Balasan admin diedit',
        createdAt: baseTime,
        adminId: 9,
        adminName: 'Operator IT',
        isFromAdmin: true,
        isEdited: true,
        editedAt: baseTime.add(const Duration(minutes: 10)),
      );
      final unedited = TicketReply(
        id: 3,
        action: 'balasan',
        note: 'Belum diedit',
        createdAt: baseTime,
        isFromAdmin: false,
        isEdited: false,
      );

      await tester.pumpWidget(_wrap(Column(
        children: [
          ChatBubble(
            reply: myEdited,
            isCurrentUserAdmin: false,
            requesterName: 'Budi',
          ),
          ChatBubble(
            reply: otherEdited,
            isCurrentUserAdmin: false,
            requesterName: 'Budi',
          ),
          ChatBubble(
            reply: unedited,
            isCurrentUserAdmin: false,
            requesterName: 'Budi',
          ),
        ],
      )));

      expect(find.text('(diedit)'), findsNWidgets(2));
    });

    testWidgets('shows edit button only for own non-system comment on open ticket',
        (tester) async {
      TicketReply? editedTarget;

      final ownReply = TicketReply(
        id: 10,
        action: 'balasan',
        note: 'Pesan Admin A',
        createdAt: baseTime,
        adminId: 5,
        adminName: 'Admin A',
        isFromAdmin: true,
      );
      final otherAdminReply = TicketReply(
        id: 11,
        action: 'balasan',
        note: 'Pesan Admin B',
        createdAt: baseTime,
        adminId: 8,
        adminName: 'Admin B',
        isFromAdmin: true,
      );
      final userReply = TicketReply(
        id: 12,
        action: 'balasan',
        note: 'Pesan Pemohon',
        createdAt: baseTime,
        isFromAdmin: false,
      );
      final systemReply = TicketReply(
        id: 13,
        action: 'work_hours_paused',
        note: 'Di luar jam kerja',
        createdAt: baseTime,
        adminId: 5,
        adminName: 'Admin A',
        isFromAdmin: true,
      );

      await tester.pumpWidget(_wrap(ListView(
        children: [
          ChatBubble(
            reply: ownReply,
            isCurrentUserAdmin: true,
            requesterName: 'Budi',
            currentAdminId: 5,
            currentAdminName: 'Admin A',
            isTicketClosed: false,
            onEdit: (r) => editedTarget = r,
          ),
          ChatBubble(
            reply: otherAdminReply,
            isCurrentUserAdmin: true,
            requesterName: 'Budi',
            currentAdminId: 5,
            currentAdminName: 'Admin A',
            isTicketClosed: false,
            onEdit: (r) => editedTarget = r,
          ),
          ChatBubble(
            reply: userReply,
            isCurrentUserAdmin: true,
            requesterName: 'Budi',
            currentAdminId: 5,
            currentAdminName: 'Admin A',
            isTicketClosed: false,
            onEdit: (r) => editedTarget = r,
          ),
          ChatBubble(
            reply: systemReply,
            isCurrentUserAdmin: true,
            requesterName: 'Budi',
            currentAdminId: 5,
            currentAdminName: 'Admin A',
            isTicketClosed: false,
            onEdit: (r) => editedTarget = r,
          ),
        ],
      )));

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump();
      expect(editedTarget?.id, 10);

      // Re-render with closed ticket -> edit icon disappears
      await tester.pumpWidget(_wrap(ChatBubble(
        reply: ownReply,
        isCurrentUserAdmin: true,
        requesterName: 'Budi',
        currentAdminId: 5,
        currentAdminName: 'Admin A',
        isTicketClosed: true,
        onEdit: (r) => editedTarget = r,
      )));
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets(
        'admin creator sees edit button only for own adminId and strict exact name fallback rejects partial match',
        (tester) async {
      final adminCreatorOwn = TicketReply(
        id: 30,
        action: 'balasan',
        note: 'Komentar Admin Pengaju',
        createdAt: baseTime,
        adminId: 7,
        adminName: 'Admin Pengaju',
        isFromAdmin: true,
      );
      final otherAdmin = TicketReply(
        id: 31,
        action: 'balasan',
        note: 'Komentar Admin Lain',
        createdAt: baseTime,
        adminId: 8,
        adminName: 'Admin Lain',
        isFromAdmin: true,
      );
      final userComment = TicketReply(
        id: 32,
        action: 'balasan',
        note: 'Komentar User',
        createdAt: baseTime,
        isFromAdmin: false,
      );
      final partialNameNoId = TicketReply(
        id: 33,
        action: 'balasan',
        note: 'Balasan Budi Santoso',
        createdAt: baseTime,
        adminId: null,
        adminName: 'Budi Santoso',
        isFromAdmin: true,
      );

      await tester.pumpWidget(_wrap(ListView(
        children: [
          ChatBubble(
            reply: adminCreatorOwn,
            isCurrentUserAdmin: true,
            requesterName: 'Admin Pengaju',
            currentAdminId: 7,
            currentAdminName: 'Admin Pengaju',
            onEdit: (_) {},
          ),
          ChatBubble(
            reply: otherAdmin,
            isCurrentUserAdmin: true,
            requesterName: 'Admin Pengaju',
            currentAdminId: 7,
            currentAdminName: 'Admin Pengaju',
            onEdit: (_) {},
          ),
          ChatBubble(
            reply: userComment,
            isCurrentUserAdmin: true,
            requesterName: 'Admin Pengaju',
            currentAdminId: 7,
            currentAdminName: 'Admin Pengaju',
            onEdit: (_) {},
          ),
          ChatBubble(
            reply: partialNameNoId,
            isCurrentUserAdmin: true,
            requesterName: 'Pemohon',
            currentAdminId: 7,
            currentAdminName: 'Budi',
            onEdit: (_) {},
          ),
        ],
      )));

      // Only adminCreatorOwn (adminId == 7) shows edit button; partialNameNoId ('Budi Santoso' != 'Budi') does not
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.text('Anda'), findsOneWidget);
    });

    testWidgets('hides attachment placeholders in ChatBubble when attachments exist',
        (tester) async {
      final attachmentPlaceholder = TicketReply(
        id: 40,
        action: 'balasan',
        note: '[Lampiran Tiket]',
        createdAt: baseTime,
        isFromAdmin: false,
        attachments: [
          {'fileName': 'dokumen.pdf', 'url': 'https://example.com/dokumen.pdf'},
        ],
      );
      final chatPlaceholder = TicketReply(
        id: 41,
        action: 'balasan',
        note: '[Lampiran Chat]',
        createdAt: baseTime,
        isFromAdmin: false,
        attachments: [
          {'fileName': 'berkas.pdf', 'url': 'https://example.com/berkas.pdf'},
        ],
      );

      await tester.pumpWidget(_wrap(Column(
        children: [
          ChatBubble(
            reply: attachmentPlaceholder,
            isCurrentUserAdmin: false,
            requesterName: 'Pemohon',
          ),
          ChatBubble(
            reply: chatPlaceholder,
            isCurrentUserAdmin: false,
            requesterName: 'Pemohon',
          ),
        ],
      )));

      expect(find.text('[Lampiran Tiket]'), findsNothing);
      expect(find.text('[Lampiran Chat]'), findsNothing);
      expect(find.text('dokumen.pdf'), findsOneWidget);
      expect(find.text('berkas.pdf'), findsOneWidget);
    });
  });

  group('EditCommentSheet', () {
    testWidgets('validates blank/unchanged text and returns updated TicketReply on success',
        (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..httpClientAdapter = _StubAdapter(200, {
          'data': {
            'id': 20,
            'action': 'balasan',
            'note': 'Catatan terbaru',
            'is_edited': true,
            'edited_at': '2026-11-25T09:30:00Z',
            'isFromAdmin': false,
          },
          'message': 'Komentar berhasil diperbarui',
        });
      final service = TicketService(dio: dio);
      final original = TicketReply(
        id: 20,
        action: 'balasan',
        note: 'Catatan lama',
        createdAt: DateTime(2026, 11, 25, 9, 0),
        isFromAdmin: false,
      );

      TicketReply? sheetResult;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  sheetResult = await EditCommentSheet.show(
                    context,
                    ticketId: '99',
                    reply: original,
                    ticketService: service,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Komentar'), findsOneWidget);
      final saveButton = find.widgetWithText(FilledButton, 'Simpan');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Catatan terbaru');
      await tester.pump();
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(sheetResult, isNotNull);
      expect(sheetResult!.note, 'Catatan terbaru');
      expect(sheetResult!.isEdited, isTrue);
    });

    testWidgets('shows error inside sheet and preserves typed text when API returns 403/422',
        (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..httpClientAdapter = _StubAdapter(403, {
          'message': 'Anda tidak berhak mengedit komentar ini.',
        });
      final service = TicketService(dio: dio);
      final original = TicketReply(
        id: 21,
        action: 'balasan',
        note: 'Catatan awal',
        createdAt: DateTime(2026, 11, 25, 9, 0),
        isFromAdmin: false,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  EditCommentSheet.show(
                    context,
                    ticketId: '99',
                    reply: original,
                    ticketService: service,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Teks gagal kirim');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Komentar'), findsOneWidget);
      expect(find.text('Anda tidak berhak mengedit komentar ini.'), findsOneWidget);
      expect(find.text('Teks gagal kirim'), findsOneWidget);
    });

    testWidgets('pre-fills empty string for [Lampiran Tiket] and [Lampiran Chat] placeholders',
        (tester) async {
      final service = TicketService(dio: Dio(BaseOptions(baseUrl: 'http://localhost')));

      for (final placeholder in ['[Lampiran Tiket]', '[Lampiran Chat]']) {
        final reply = TicketReply(
          id: 50,
          action: 'balasan',
          note: placeholder,
          createdAt: DateTime(2026, 11, 25, 9, 0),
          isFromAdmin: false,
        );

        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    EditCommentSheet.show(
                      context,
                      ticketId: '99',
                      reply: reply,
                      ticketService: service,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.controller?.text, isEmpty);
        expect(find.text(placeholder), findsNothing);

        await tester.tap(find.text('Batal'));
        await tester.pumpAndSettle();
      }
    });
  });
}
