import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/config/api_config.dart';
import 'package:halo_apu_mobile/core/services/attachment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttachmentService.resolveAttachmentUrl', () {
    test('handles null and empty input', () {
      expect(AttachmentService.resolveAttachmentUrl(null), '');
      expect(AttachmentService.resolveAttachmentUrl(''), '');
      expect(AttachmentService.resolveAttachmentUrl({}), '');
    });

    test('resolves relative path without storage prefix', () {
      final res = AttachmentService.resolveAttachmentUrl('ticket-attachments/sample.pdf');
      expect(res, '${ApiConfig.baseUrl}/attachments/serve?path=ticket-attachments/sample.pdf');
    });

    test('cleans leading storage/ and slashes', () {
      final res = AttachmentService.resolveAttachmentUrl('/storage/ticket-attachments/sample.pdf');
      expect(res, '${ApiConfig.baseUrl}/attachments/serve?path=ticket-attachments/sample.pdf');
    });

    test('cleans public/ prefix', () {
      final res = AttachmentService.resolveAttachmentUrl('public/ticket-attachments/image.png');
      expect(res, '${ApiConfig.baseUrl}/attachments/serve?path=ticket-attachments/image.png');
    });

    test('handles Map with path, file_path, or url', () {
      expect(
        AttachmentService.resolveAttachmentUrl({'path': 'storage/doc.pdf'}),
        '${ApiConfig.baseUrl}/attachments/serve?path=doc.pdf',
      );
      expect(
        AttachmentService.resolveAttachmentUrl({'file_path': '/storage/doc.pdf'}),
        '${ApiConfig.baseUrl}/attachments/serve?path=doc.pdf',
      );
      expect(
        AttachmentService.resolveAttachmentUrl({'url': 'https://dev.haloapu.id/storage/doc.pdf'}),
        '${ApiConfig.baseUrl}/attachments/serve?path=doc.pdf',
      );
    });

    test('handles full url with /attachments/serve?path=', () {
      final url = '${ApiConfig.baseUrl}/attachments/serve?path=storage/doc.pdf';
      expect(
        AttachmentService.resolveAttachmentUrl(url),
        '${ApiConfig.baseUrl}/attachments/serve?path=doc.pdf',
      );
    });

    test('preserves external url that has no /storage/ or /attachments/serve', () {
      const extUrl = 'https://example.com/files/manual.pdf';
      expect(AttachmentService.resolveAttachmentUrl(extUrl), extUrl);
    });
  });

  group('AttachmentService.isImage', () {
    test('detects image by extension', () {
      expect(AttachmentService.isImage('photo.jpg'), true);
      expect(AttachmentService.isImage('photo.JPEG'), true);
      expect(AttachmentService.isImage('photo.png'), true);
      expect(AttachmentService.isImage('photo.gif'), true);
      expect(AttachmentService.isImage('photo.webp'), true);
      expect(AttachmentService.isImage('photo.bmp'), true);
      expect(AttachmentService.isImage('photo.heic'), true);
      expect(AttachmentService.isImage('document.pdf'), false);
      expect(AttachmentService.isImage('data.docx'), false);
    });

    test('detects image by mimeType', () {
      expect(AttachmentService.isImage('file_without_ext', 'image/jpeg'), true);
      expect(AttachmentService.isImage('file_without_ext', 'image/png'), true);
      expect(AttachmentService.isImage('document.pdf', 'application/pdf'), false);
    });
  });
}
