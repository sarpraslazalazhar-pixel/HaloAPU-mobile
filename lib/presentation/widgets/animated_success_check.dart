import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';

/// Animasi centang vektor halus tanpa ketergantungan jaringan.
class AnimatedSuccessCheck extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  final VoidCallback? onCompleted;

  const AnimatedSuccessCheck({
    super.key,
    this.size = 88,
    this.color = AppTheme.success,
    this.duration = const Duration(milliseconds: 950),
    this.onCompleted,
  });

  @override
  State<AnimatedSuccessCheck> createState() => _AnimatedSuccessCheckState();
}

class _AnimatedSuccessCheckState extends State<AnimatedSuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted?.call();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SuccessCheckPainter(
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _SuccessCheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _SuccessCheckPainter({
    required this.progress,
    required this.color,
  });

  double _interval(double begin, double end, Curve curve) {
    if (progress <= begin) return 0.0;
    if (progress >= end) return 1.0;
    final t = ((progress - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = math.min(size.width, size.height) * 0.34;

    // 1. Halo ripple lembut saat centang selesai digambar
    final rippleT = _interval(0.55, 0.98, Curves.easeOutCubic);
    if (rippleT > 0.0 && rippleT < 1.0) {
      final rippleRadius = baseRadius * (1.0 + 0.36 * rippleT);
      final ripplePaint = Paint()
        ..color = color.withValues(alpha: 0.28 * (1.0 - rippleT))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (baseRadius * 0.12) * (1.0 - 0.5 * rippleT);
      canvas.drawCircle(center, rippleRadius, ripplePaint);
    }

    // 2. Denyut skala halus (C1-continuous) saat penyelesaian centang
    final settleT = _interval(0.58, 0.95, Curves.linear);
    final scaleBump = 1.0 + 0.055 * (1.0 - math.cos(2.0 * math.pi * settleT)) * 0.5;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scaleBump);
    canvas.translate(-center.dx, -center.dy);

    // 3. Latar lingkaran lembut yang memudar masuk
    final fillT = _interval(0.10, 0.52, Curves.easeOutCubic);
    if (fillT > 0.0) {
      final bgPaint = Paint()
        ..color = color.withValues(alpha: 0.12 * fillT)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, baseRadius * (0.72 + 0.28 * fillT), bgPaint);
    }

    // 4. Garis lingkaran menyapu halus
    final circleT = _interval(0.0, 0.48, Curves.easeInOutCubic);
    if (circleT > 0.001) {
      final ringPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseRadius * 0.13
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: baseRadius),
        -math.pi / 2,
        2 * math.pi * circleT,
        false,
        ringPaint,
      );
    }

    // 5. Goresan centang menyambung halus dengan PathMetric
    final checkT = _interval(0.34, 0.78, Curves.easeOutCubic);
    if (checkT > 0.001) {
      final checkPath = Path()
        ..moveTo(center.dx - baseRadius * 0.36, center.dy + baseRadius * 0.02)
        ..lineTo(center.dx - baseRadius * 0.08, center.dy + baseRadius * 0.30)
        ..lineTo(center.dx + baseRadius * 0.40, center.dy - baseRadius * 0.24);

      final checkPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseRadius * 0.15
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (final metric in checkPath.computeMetrics()) {
        final extractLength = metric.length * checkT;
        if (extractLength > 0) {
          canvas.drawPath(metric.extractPath(0, extractLength), checkPaint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SuccessCheckPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

/// Menampilkan dialog sukses tiket dengan transisi halus dan centang beranimasi.
Future<void> showTicketSuccessDialog(
  BuildContext context, {
  String title = 'Tiket Berhasil Dibuat',
  Duration holdDuration = const Duration(milliseconds: 1600),
}) async {
  if (!context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  var dialogDismissed = false;

  final dialogFuture = showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: title,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return PopScope(
        canPop: false,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 196, maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.darkBg.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AnimatedSuccessCheck(size: 88),
                  const SizedBox(height: 14),
                  _FadeSlideText(title: title),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final scale = Tween<double>(begin: 0.88, end: 1.0).animate(fade);
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: scale,
          child: child,
        ),
      );
    },
  ).whenComplete(() {
    dialogDismissed = true;
  });

  await Future.delayed(holdDuration);
  if (!dialogDismissed && navigator.mounted) {
    navigator.pop();
  }
  await dialogFuture;
  await Future.delayed(const Duration(milliseconds: 280));
}

class _FadeSlideText extends StatefulWidget {
  final String title;

  const _FadeSlideText({required this.title});

  @override
  State<_FadeSlideText> createState() => _FadeSlideTextState();
}

class _FadeSlideTextState extends State<_FadeSlideText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 740),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.43, 1.0, curve: Curves.easeOutCubic),
    );
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(curved);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: Text(
          widget.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.darkBg,
          ),
        ),
      ),
    );
  }
}
