import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../core/services/attachment_service.dart';

class AppAvatar extends StatefulWidget {
  final String? imageUrl;
  final String? imagePath;
  final Uint8List? imageBytes;
  final String name;
  final double radius;
  final double? fontSize;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;

  const AppAvatar({
    super.key,
    this.imageUrl,
    this.imagePath,
    this.imageBytes,
    required this.name,
    this.radius = 22,
    this.fontSize,
    this.onTap,
    this.showBorder = true,
    this.borderColor,
  });

  @override
  State<AppAvatar> createState() => _AppAvatarState();
}

class _AppAvatarState extends State<AppAvatar> {
  String? _token;

  @override
  void initState() {
    super.initState();
    _token = AttachmentService.cachedToken;
    _fetchToken();
  }

  @override
  void didUpdateWidget(covariant AppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_token == null || _token!.isEmpty) {
      _token = AttachmentService.cachedToken;
      _fetchToken();
    }
  }

  Future<void> _fetchToken() async {
    final token = await AttachmentService.getAuthToken();
    if (mounted && token != _token) {
      setState(() {
        _token = token;
      });
    }
  }

  String _getInitials(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  LinearGradient _getGradientForName(String input) {
    final hash = input.hashCode.abs();
    final gradientIndex = hash % 4;

    switch (gradientIndex) {
      case 0:
        return const LinearGradient(
          colors: [Color(0xFF00768C), Color(0xFF00B4D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 1:
        return const LinearGradient(
          colors: [Color(0xFF0066FF), Color(0xFF38BDF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 2:
        return const LinearGradient(
          colors: [Color(0xFF0D9488), Color(0xFF2DD4BF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 3:
      default:
        return const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  String _resolveImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final trimmed = url.trim();
    if (trimmed.contains('ui-avatars.com') || trimmed.contains('pravatar.cc')) return '';

    if (trimmed.startsWith('blob:') || trimmed.startsWith('data:')) {
      return trimmed;
    }

    final resolved = AttachmentService.resolveAttachmentUrl(trimmed);
    if (resolved.isNotEmpty) {
      return resolved;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    final baseUrl = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;

    final clean = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    return '$baseUrl/attachments/serve?path=$clean';
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    final initials = _getInitials(widget.name);
    final calculatedFontSize = widget.fontSize ?? (widget.radius * 0.78);
    final resolvedUrl = _resolveImageUrl(widget.imageUrl ?? widget.imagePath);

    Widget avatarChild;

    if (widget.imageBytes != null && widget.imageBytes!.isNotEmpty) {
      avatarChild = Image.memory(
        widget.imageBytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitialsPlaceholder(initials, calculatedFontSize),
      );
    } else if (resolvedUrl.isNotEmpty &&
        (resolvedUrl.startsWith('http://') ||
         resolvedUrl.startsWith('https://') ||
         resolvedUrl.startsWith('blob:'))) {
      final token = _token ?? AttachmentService.cachedToken;
      final isProtected = resolvedUrl.contains('/attachments/serve');

      if (isProtected && (token == null || token.isEmpty)) {
        avatarChild = _buildInitialsPlaceholder(initials, calculatedFontSize);
      } else {
        final headers = (token != null && token.isNotEmpty)
            ? {'Authorization': 'Bearer $token'}
            : null;

        avatarChild = CachedNetworkImage(
          imageUrl: resolvedUrl,
          httpHeaders: headers,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildInitialsPlaceholder(initials, calculatedFontSize),
          errorWidget: (context, url, error) => _buildInitialsPlaceholder(initials, calculatedFontSize),
          fadeInDuration: const Duration(milliseconds: 200),
          fadeOutDuration: const Duration(milliseconds: 200),
        );
      }
    } else {
      avatarChild = _buildInitialsPlaceholder(initials, calculatedFontSize);
    }

    Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: widget.showBorder
            ? Border.all(
                color: widget.borderColor ?? Colors.white,
                width: 2.0,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(child: avatarChild),
    );

    if (widget.onTap != null) {
      return InkWell(
        onTap: widget.onTap,
        customBorder: const CircleBorder(),
        child: content,
      );
    }

    return content;
  }

  Widget _buildInitialsPlaceholder(String initials, double fontSize) {
    final clean = initials.trim().replaceAll('?', '');
    return Container(
      decoration: BoxDecoration(
        gradient: _getGradientForName(widget.name),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: clean.isNotEmpty
          ? Text(
              clean,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            )
          : Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: fontSize * 1.3,
            ),
    );
  }
}
