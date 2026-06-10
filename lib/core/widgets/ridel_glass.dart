import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

class RidelGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;
  final Color? baseColor;

  final bool isVerticalCard;
  final bool isLargeRect;
  final bool isWeatherCompact;
  final bool isVerticalPill;
  final bool isCircle; // 🚀 PERFECT ROUND BUTTONS

  const RidelGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blurSigma = 35.0,
    this.baseColor,
    this.isVerticalCard = false,
    this.isLargeRect = false,
    this.isWeatherCompact = false,
    this.isVerticalPill = false,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(100);
    final themeBg =
        baseColor ?? const Color(0xFF1E1E1E).withValues(alpha: 0.55);

    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: RepaintBoundary(
        child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: CustomPaint(
            foregroundPainter: _GlassBorderPainter(
              borderRadius: br,
              isVerticalCard: isVerticalCard,
              isLargeRect: isLargeRect,
              isWeatherCompact: isWeatherCompact,
              isVerticalPill: isVerticalPill,
              isCircle: isCircle,
            ),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: themeBg,
                borderRadius: br,
              ),
              child: Material(
                color: Colors.transparent,
                child: child,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _GlassBorderPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final bool isVerticalCard;
  final bool isLargeRect;
  final bool isWeatherCompact;
  final bool isVerticalPill;
  final bool isCircle;

  _GlassBorderPainter({
    required this.borderRadius,
    this.isVerticalCard = false,
    this.isLargeRect = false,
    this.isWeatherCompact = false,
    this.isVerticalPill = false,
    this.isCircle = false,
  });

  double _normalizeAngle(double x, double y) {
    double angle = math.atan2(y, x);
    angle = angle - (math.pi / 2);
    double normalized = (angle / (2 * math.pi)) % 1.0;
    if (normalized < 0) normalized += 1.0;
    return normalized;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    const double strokeWidth = 1.2;

    final Color shine = Colors.white.withValues(alpha: 0.35);
    final Color gap = Colors.white.withValues(alpha: 0.0);
    Gradient gradient;

    if (isCircle) {
      // 🟢 PERFECT CIRCLE (Sharp, slim, diagonal cuts for Real Glass effect)
      gradient = SweepGradient(
        transform: const GradientRotation(math.pi / 4), // 45 degree tilt
        colors: [shine, shine, gap, gap, shine, shine, gap, gap, shine, shine],
        stops: const [
          0.0,
          0.42, // Long shine
          0.45, // SLIM GAP START
          0.55, // SLIM GAP END
          0.58, // Back to shine
          0.92, // Long shine 2
          0.95, // SLIM GAP 2 START
          1.0, // SLIM GAP 2 END
          1.0,
          1.0
        ],
      );
    } else if (isVerticalCard) {
      gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          shine,
          Colors.white.withValues(alpha: 0.15),
          gap,
          gap,
          Colors.white.withValues(alpha: 0.15),
          shine
        ],
        stops: const [0.0, 0.35, 0.45, 0.55, 0.65, 1.0],
      );
    } else if (isLargeRect) {
      double cBL = (math.atan2(h, -w) / (2 * math.pi)) % 1.0;
      if (cBL < 0) cBL += 1.0;
      double cTR = (math.atan2(-h, w) / (2 * math.pi)) % 1.0;
      if (cTR < 0) cTR += 1.0;
      double spread = 0.04;
      gradient = SweepGradient(
        colors: [shine, shine, gap, gap, shine, shine, gap, gap, shine, shine],
        stops: [
          0.00,
          cBL - spread,
          cBL - (spread / 2),
          cBL + (spread / 2),
          cBL + spread,
          cTR - spread,
          cTR - (spread / 2),
          cTR + (spread / 2),
          cTR + spread,
          1.00
        ],
      );
    } else if (isWeatherCompact) {
      double cBL = _normalizeAngle(-w, h);
      double cTR = _normalizeAngle(w, -h);
      double fadeLen = 0.12;
      double darkLen = 0.03;
      cBL = math.max(cBL, fadeLen + 0.001);
      cTR = math.min(cTR, 1.0 - fadeLen - 0.001);
      gradient = SweepGradient(
        transform: const GradientRotation(math.pi / 2),
        colors: [shine, shine, gap, gap, shine, shine, gap, gap, shine, shine],
        stops: [
          0.0,
          cBL - fadeLen,
          cBL - darkLen,
          cBL + darkLen,
          cBL + fadeLen,
          cTR - fadeLen,
          cTR - darkLen,
          cTR + darkLen,
          cTR + fadeLen,
          1.0
        ],
      );
    } else if (isVerticalPill) {
      double cBL = _normalizeAngle(-w, h);
      double cTR = _normalizeAngle(w, -h);
      double fadeLen = 0.14;
      double darkLen = 0.02;
      cBL = math.max(cBL, fadeLen + 0.001);
      cTR = math.min(cTR, 1.0 - fadeLen - 0.001);
      gradient = SweepGradient(
        transform: const GradientRotation(math.pi / 2),
        colors: [shine, shine, gap, gap, shine, shine, gap, gap, shine, shine],
        stops: [
          0.0,
          cBL - fadeLen,
          cBL - darkLen,
          cBL + darkLen,
          cBL + fadeLen,
          cTR - fadeLen,
          cTR - darkLen,
          cTR + darkLen,
          cTR + fadeLen,
          1.0
        ],
      );
    } else {
      // 🖥️ LAMBE NAV BAR
      double cBL = _normalizeAngle(-w, h);
      double cTR = _normalizeAngle(w, -h);
      double fadeLen = 0.035;
      double darkLen = 0.002;
      cBL = math.max(cBL, fadeLen + 0.001);
      cTR = math.min(cTR, 1.0 - fadeLen - 0.001);
      gradient = SweepGradient(
        transform: const GradientRotation(math.pi / 2),
        colors: [shine, shine, gap, gap, shine, shine, gap, gap, shine, shine],
        stops: [
          0.0,
          cBL - fadeLen,
          cBL - darkLen,
          cBL + darkLen,
          cBL + fadeLen,
          cTR - fadeLen,
          cTR - darkLen,
          cTR + darkLen,
          cTR + fadeLen,
          1.0
        ],
      );
    }

    final Rect rect = Rect.fromLTWH(
        strokeWidth / 2, strokeWidth / 2, w - strokeWidth, h - strokeWidth);
    final RRect rrect = borderRadius.toRRect(rect);
    final Paint paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
