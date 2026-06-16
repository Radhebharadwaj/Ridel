// lib/core/widgets/ridel_liquid_button.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ridel/core/utils/app_haptics.dart';

enum LiquidShapeType { circle, pill, squircle }

class RidelLiquidButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final LiquidShapeType shapeType;
  final Color glassTint;
  final bool enableStretch;
  final double lightAngle;
  final bool hasBorder;
  final Gradient? customGradient;

  const RidelLiquidButton({
    super.key,
    required this.child,
    this.onTap,
    this.width = double.infinity,
    this.height = 56,
    this.shapeType = LiquidShapeType.pill,
    this.glassTint = const Color(0x1AFFFFFF),
    this.enableStretch = true,
    this.lightAngle = 0.785398,
    this.hasBorder = true,
    this.customGradient,
  });

  @override
  State<RidelLiquidButton> createState() => _RidelLiquidButtonState();
}

class _RidelLiquidButtonState extends State<RidelLiquidButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      AppHaptics.lightImpact();
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap != null) {
      AppHaptics.buttonClick();
      setState(() => _isPressed = false);
      Future.microtask(() => widget.onTap!());
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null) setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final isCircle = widget.shapeType == LiquidShapeType.circle;
    final borderRadius = isCircle ? widget.width / 2 : widget.height / 2;
    final double magneticShrink = _isPressed ? widget.height * 0.04 : 0.0;
    
    // 🔥 Ultra-Clean Light Mode Logic
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    // A simple, flat "whitish-dark" (light grey) tint for light mode
    final effectiveGlassTint = isLightMode 
        ? Colors.black.withValues(alpha: 0.04) 
        : widget.glassTint;
        
    // 🌟 New PREMIUM DOUBLE SHADOW for "float" feel (Light Mode optimized)
    final shadowColorDepth = isLightMode
        ? Colors.black.withValues(alpha: _isPressed ? 0.01 : 0.03) // Extremely faint shadow
        : Colors.black.withValues(alpha: _isPressed ? 0.15 : 0.35); // Original deep shadow

    final shadowColorSoft = isLightMode
        ? Colors.transparent // Secondary, diffused contact shadow (effectively hidden in light mode)
        : Colors.transparent; // Not used in dark mode originally

    final simpleBorderColor = isLightMode
        ? Colors.black.withValues(alpha: 0.06) // Clean, uniform edge
        : Colors.white.withValues(alpha: 0.18);

    // Completely flat gradient for light mode
    final activeGradient = isLightMode
        ? LinearGradient(
            colors: [effectiveGlassTint, effectiveGlassTint],
          )
        : (widget.customGradient ?? LinearGradient(
            begin: isCircle ? Alignment.topLeft : Alignment.topCenter,
            end: isCircle ? Alignment.bottomRight : Alignment.bottomCenter,
            colors: [
              widget.glassTint.withValues(alpha: (widget.glassTint.a + 0.10).clamp(0.0, 1.0)),
              widget.glassTint,
              widget.glassTint.withValues(alpha: (widget.glassTint.a - 0.04).clamp(0.0, 1.0)),
            ],
          ));

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedPadding(
        padding: EdgeInsets.all(magneticShrink),
        duration: Duration(milliseconds: _isPressed ? 50 : 400),
        curve: _isPressed ? Curves.easeOutQuart : Curves.elasticOut,
        child: AnimatedOpacity(
          opacity: _isPressed ? 0.85 : 1.0,
          duration: Duration(milliseconds: _isPressed ? 50 : 250),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              children: [
                // 🌟 LAYER 1: OUTER SHADOWS CONTAINER (UPDATED WITH DOUBLE SHADOW)
                Container(
                  width: widget.width,
                  height: widget.height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    boxShadow: widget.onTap != null
                        ? (isLightMode ? [
                            BoxShadow(
                              color: shadowColorDepth,
                              blurRadius: isLightMode ? 24 : (_isPressed ? 10 : 20), // Increased main blur
                              spreadRadius: _isPressed ? 0 : -2,
                              offset: Offset(0, _isPressed ? 6 : 14), // Main offset for lift
                            ),
                            BoxShadow(
                              color: shadowColorSoft,
                              blurRadius: isLightMode ? 10 : 10, // Contact shadow blur
                              spreadRadius: isLightMode ? 0 : -2, // Diffused spread
                              offset: Offset(0, isLightMode ? 4 : 8), // Soft offset for contact
                            ),
                          ] : [
                            BoxShadow(
                              color: shadowColorDepth, // Original dark mode shadow
                              blurRadius: _isPressed ? 10 : 20,
                              spreadRadius: _isPressed ? 0 : -2,
                              offset: Offset(0, _isPressed ? 6 : 14),
                            ),
                          ])
                        : null,
                  ),
                ),

                // 🌟 LAYER 2: GLASS BODY (CLIP + BLUR + OPTICAL GRADIENT)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(borderRadius),
                    clipBehavior: Clip.antiAlias,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(borderRadius),
                          gradient: activeGradient, // Apply the new optical gradient
                        ),
                        child: Center(child: widget.child),
                      ),
                    ),
                  ),
                ),

                // 🌟 LAYER 3: ANTI-ALIASING BORDER SHIELD (UPDATED PAINTERS)
                if (widget.hasBorder)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: isLightMode
                            ? _UniformPillPainter(radius: borderRadius, color: simpleBorderColor) // Force uniform border in light mode for all shapes
                            : (isCircle
                                ? _DiagonalBorderPainter( // Original dark mode painter
                                    radius: borderRadius,
                                  )
                                : _UniformPillPainter(
                                    radius: borderRadius,
                                    color: simpleBorderColor,
                                  )),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 🌟 Original Dark Mode Painter
class _DiagonalBorderPainter extends CustomPainter {
  final double radius;
  _DiagonalBorderPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true 
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x73FFFFFF), // Colors.white.withValues(alpha: 0.45)
          Color(0x0CFFFFFF), // Colors.white.withValues(alpha: 0.05)
          Color(0x33FFFFFF), // Colors.white.withValues(alpha: 0.20)
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(rect);
    final RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _DiagonalBorderPainter oldDelegate) => false;
}

// 🌟 New Pill Painter: Draws uniform border smoothly outside clip (reproducing original clean look perfectly)
class _UniformPillPainter extends CustomPainter {
  final double radius;
  final Color color;
  _UniformPillPainter({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..strokeWidth = 1.0 // Standard crisp uniform line
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true // Explicitly enable painter aliasing
      ..color = color;
    final RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _UniformPillPainter oldDelegate) => false;
}
