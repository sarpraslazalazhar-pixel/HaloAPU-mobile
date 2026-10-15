import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/services/attachment_service.dart';
import '../../core/theme/app_theme.dart';

class AuthAttachmentImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final VoidCallback? onTap;

  const AuthAttachmentImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorBuilder,
    this.onTap,
  });

  @override
  State<AuthAttachmentImage> createState() => _AuthAttachmentImageState();
}

class _AuthAttachmentImageState extends State<AuthAttachmentImage> {
  String? _token;
  bool _isLoadingToken = true;

  @override
  void initState() {
    super.initState();
    _fetchAuthToken();
  }

  Future<void> _fetchAuthToken() async {
    final token = await AttachmentService.getAuthToken();
    if (mounted) {
      setState(() {
        _token = token;
        _isLoadingToken = false;
      });
    }
  }

  Widget _buildDefaultPlaceholder(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.oceanWater),
        ),
      ),
    );
  }

  Widget _buildDefaultErrorWidget(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 28,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 4),
          Text(
            'Gagal memuat gambar',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _wrap(Widget child) {
    Widget current = child;

    if (widget.borderRadius != null) {
      current = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: current,
      );
    }

    if (widget.onTap != null) {
      current = InkWell(
        borderRadius: widget.borderRadius,
        onTap: widget.onTap,
        child: current,
      );
    }

    return current;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = AttachmentService.resolveAttachmentUrl(widget.imageUrl);

    if (resolvedUrl.isEmpty) {
      return _wrap(
        widget.errorBuilder != null
            ? widget.errorBuilder!(context, 'URL gambar kosong', null)
            : _buildDefaultErrorWidget(context),
      );
    }

    if (_isLoadingToken) {
      return _wrap(widget.placeholder ?? _buildDefaultPlaceholder(context));
    }

    final headers = (_token != null && _token!.isNotEmpty)
        ? {'Authorization': 'Bearer $_token'}
        : null;

    final imageWidget = CachedNetworkImage(
      imageUrl: resolvedUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      httpHeaders: headers,
      placeholder: (context, _) =>
          widget.placeholder ?? _buildDefaultPlaceholder(context),
      errorWidget: (context, _, error) {
        if (widget.errorBuilder != null) {
          return widget.errorBuilder!(context, error, null);
        }
        return _buildDefaultErrorWidget(context);
      },
    );

    return _wrap(imageWidget);
  }
}

/// Menampilkan pratinjau gambar dengan fitur pinch-to-zoom, tombol tutup, dan tombol unduh.
void showAuthImagePreview(
  BuildContext context, {
  required String url,
  required String title,
}) {
  final resolvedUrl = AttachmentService.resolveAttachmentUrl(url);
  final displayTitle = title.trim().isNotEmpty
      ? title.trim()
      : (url.split('?').first.split('/').last.isNotEmpty
          ? url.split('?').first.split('/').last
          : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg');

  showDialog<void>(
    context: context,
    useSafeArea: false,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (dialogCtx) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: AuthAttachmentImage(
                  imageUrl: resolvedUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.download_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    tooltip: 'Unduh',
                    onPressed: () {
                      AttachmentService.downloadAndOpenFile(
                        context,
                        url: resolvedUrl,
                        fileName: displayTitle,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
