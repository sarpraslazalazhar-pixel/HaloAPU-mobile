import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../config/api_config.dart';
import '../theme/app_theme.dart';

class AttachmentService {
  AttachmentService._();

  static String? _cachedToken;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Mengambil token autentikasi yang tersimpan di memori secara sinkron jika tersedia.
  static String? get cachedToken => _cachedToken;

  /// Menyimpan token autentikasi ke cache memori.
  static void setCachedToken(String? token) {
    _cachedToken = token;
  }

  /// Mengambil token autentikasi dari memori (jika ada) atau secure storage.
  static Future<String?> getAuthToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    try {
      _cachedToken = await _storage.read(key: 'auth_token');
    } catch (_) {
      _cachedToken = null;
    }
    return _cachedToken;
  }

  /// Menghapus cache token di memori.
  static void clearTokenCache() {
    _cachedToken = null;
  }

  /// Membersihkan prefix path 'storage/', 'public/', dan '/' berulang.
  static String _cleanPath(String p) {
    var s = p.trim();
    bool changed = true;
    while (changed && s.isNotEmpty) {
      changed = false;
      if (s.startsWith('/')) {
        s = s.substring(1).trim();
        changed = true;
      }
      if (s.startsWith('storage/')) {
        s = s.substring('storage/'.length).trim();
        changed = true;
      }
      if (s.startsWith('public/')) {
        s = s.substring('public/'.length).trim();
        changed = true;
      }
    }
    return s;
  }

  /// Menyelesaikan attachment (String atau Map) menjadi endpoint serve URL lengkap.
  static String resolveAttachmentUrl(dynamic attachment) {
    if (attachment == null) return '';

    String raw = '';
    if (attachment is String) {
      raw = attachment.trim();
    } else if (attachment is Map) {
      final dynamic pathVal =
          attachment['path'] ?? attachment['file_path'] ?? attachment['url'];
      if (pathVal != null) {
        raw = pathVal.toString().trim();
      }
    }

    if (raw.isEmpty) return '';

    final baseUrl = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;

    final isFullUrl = raw.startsWith('http://') || raw.startsWith('https://');

    if (isFullUrl) {
      if (raw.contains('/attachments/serve') ||
          raw.contains('attachments/serve')) {
        final uri = Uri.tryParse(raw);
        String pathParam = uri?.queryParameters['path'] ?? '';
        if (pathParam.isEmpty) {
          if (raw.contains('?path=')) {
            pathParam = raw.split('?path=').last.split('&').first;
          } else if (raw.contains('/attachments/serve/')) {
            pathParam = raw.split('/attachments/serve/').last;
          }
        }
        if (pathParam.contains('%')) {
          try {
            pathParam = Uri.decodeComponent(pathParam);
          } catch (_) {}
        }
        final clean = _cleanPath(pathParam.isNotEmpty ? pathParam : raw);
        if (clean.isEmpty) return raw;
        return '$baseUrl/attachments/serve?path=$clean';
      }

      if (raw.contains('/storage/')) {
        final pathAfterStorage = raw.split('/storage/').last;
        final clean = _cleanPath(pathAfterStorage);
        if (clean.isEmpty) return raw;
        return '$baseUrl/attachments/serve?path=$clean';
      }

      if (raw.contains('/avatars/')) {
        final pathAfterAvatars = 'avatars/${raw.split('/avatars/').last}';
        final clean = _cleanPath(pathAfterAvatars);
        if (clean.isNotEmpty) {
          return '$baseUrl/attachments/serve?path=$clean';
        }
      }

      return raw;
    }

    if (raw.contains('/attachments/serve') ||
        raw.contains('attachments/serve')) {
      final uri = Uri.tryParse(
          raw.startsWith('/') ? 'http://dummy$raw' : 'http://dummy/$raw');
      String pathParam = uri?.queryParameters['path'] ?? '';
      if (pathParam.isEmpty && raw.contains('?path=')) {
        pathParam = raw.split('?path=').last.split('&').first;
      }
      final clean = _cleanPath(pathParam.isNotEmpty ? pathParam : raw);
      if (clean.isEmpty) return '';
      return '$baseUrl/attachments/serve?path=$clean';
    }

    final clean = _cleanPath(raw);
    if (clean.isEmpty) return '';
    return '$baseUrl/attachments/serve?path=$clean';
  }

  /// Mengecek apakah file merupakan gambar berdasarkan ekstensi atau mimeType.
  static bool isImage(String fileName, [String? mimeType]) {
    if (mimeType != null && mimeType.toLowerCase().startsWith('image/')) {
      return true;
    }
    final cleanName = fileName.split('?').first.split('#').first.toLowerCase();
    const extensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
      '.heic'
    ];
    for (final ext in extensions) {
      if (cleanName.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  /// Mengunduh file lampiran dengan autentikasi lalu membukanya via OpenFilex.
  static Future<void> downloadAndOpenFile(
    BuildContext context, {
    required String url,
    required String fileName,
  }) async {
    final downloadUrl = (url.startsWith('http://') || url.startsWith('https://'))
        ? url
        : resolveAttachmentUrl(url);

    if (downloadUrl.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL lampiran tidak valid'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final safeFileName = fileName.trim().isNotEmpty
        ? fileName.trim().split(RegExp(r'[/\\]')).last
        : 'lampiran_${DateTime.now().millisecondsSinceEpoch}';

    final progressNotifier = ValueNotifier<double?>(null);
    final cancelToken = CancelToken();
    bool isDialogPopped = false;
    BuildContext? dialogContext;

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          dialogContext = ctx;
          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) {
                isDialogPopped = true;
                if (!cancelToken.isCancelled) {
                  cancelToken.cancel('Unduhan dibatalkan');
                }
              }
            },
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Mengunduh Lampiran',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: ValueListenableBuilder<double?>(
                valueListenable: progressNotifier,
                builder: (context, progress, _) {
                  final percent = progress != null
                      ? (progress * 100).clamp(0, 100).toInt()
                      : null;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        safeFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.oceanWater,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        percent != null
                            ? '$percent%'
                            : 'Menghubungkan ke server...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelToken.cancel('Unduhan dibatalkan');
                    if (!isDialogPopped &&
                        dialogContext != null &&
                        dialogContext!.mounted) {
                      isDialogPopped = true;
                      Navigator.of(dialogContext!).pop();
                    }
                  },
                  child: const Text('Batal'),
                ),
              ],
            ),
          );
        },
      );
    }

    try {
      final token = await getAuthToken();
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/$safeFileName';

      final dio = Dio();
      await dio.download(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        options: Options(
          headers: (token != null && token.isNotEmpty)
              ? {'Authorization': 'Bearer $token'}
              : null,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progressNotifier.value = received / total;
          } else {
            progressNotifier.value = null;
          }
        },
      );

      if (!isDialogPopped &&
          dialogContext != null &&
          dialogContext!.mounted) {
        isDialogPopped = true;
        Navigator.of(dialogContext!).pop();
      }

      final openResult = await OpenFilex.open(savePath);
      if (openResult.type != ResultType.done) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                openResult.message.isNotEmpty
                    ? 'Gagal membuka file: ${openResult.message}'
                    : 'Tidak ada aplikasi yang kompatibel untuk membuka file ini',
              ),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } on DioException catch (e) {
      if (!isDialogPopped &&
          dialogContext != null &&
          dialogContext!.mounted) {
        isDialogPopped = true;
        Navigator.of(dialogContext!).pop();
      }
      if (CancelToken.isCancel(e)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unduhan dibatalkan'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal mengunduh file: ${e.message ?? 'Terjadi kesalahan jaringan'}',
            ),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!isDialogPopped &&
          dialogContext != null &&
          dialogContext!.mounted) {
        isDialogPopped = true;
        Navigator.of(dialogContext!).pop();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memproses file: $e'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      progressNotifier.dispose();
    }
  }
}
