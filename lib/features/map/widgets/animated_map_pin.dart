import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// 🧭 Premium Animated Destination Pin
///
/// A Flutter-rendered, theme-aware, breathing-pulse destination marker
/// that overlays on top of the MapLibre map. Syncs to map coordinates
/// via [toScreenLocation] and runs a continuous radar-pulse animation
/// at 60fps using [CustomPainter].
///
/// Design Spec:
///   • Core: Neon Cyan (#00E5FF) solid dot with inner highlight
///   • Casing: Frosted dark glass (dark) / clean white with shadow (light)
///   • Pulse: 2 concentric expanding + fading rings

const Color _neonCyan = Color(0xFF00E5FF);

class AnimatedMapPin extends StatefulWidget {
  final MapLibreMapController? mapController;
  final LatLng? target;
  final bool isDark;

  const AnimatedMapPin({
    super.key,
    required this.mapController,
    required this.target,
    required this.isDark,
  });

  @override
  State<AnimatedMapPin> createState() => AnimatedMapPinState();
}

class AnimatedMapPinState extends State<AnimatedMapPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _projectionTimer;
  Offset? _screenPos;
  bool _isProjecting = false;

  @override
  void initState() {
    super.initState();
    // 1. Visual Pulse (Safe at 60fps, purely Flutter Canvas)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // 2. Heavy JS Interop Projection (Throttled to ~30fps to prevent Web Freezes)
    _projectionTimer = Timer.periodic(const Duration(milliseconds: 35), (_) {
      if (!_isProjecting) {
        _isProjecting = true;
        _updatePosition().whenComplete(() => _isProjecting = false);
      }
    });
  }

  @override
  void didUpdateWidget(AnimatedMapPin oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.target != widget.target) {
      _updatePosition();
      // Force projection after the camera settles
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _updatePosition();
      });
    }
  }

  void syncPosition() => _updatePosition();

  Future<void> _updatePosition() async {
    final ctrl = widget.mapController;
    final target = widget.target;
    if (ctrl == null || target == null) {
      if (_screenPos != null && mounted) setState(() => _screenPos = null);
      return;
    }
    
    try {
      final pt = await ctrl.toScreenLocation(target);
      // MapLibre sometimes returns x:0, y:0 when the coordinate is off-screen or unprojectable
      if (pt.x == 0 && pt.y == 0) return; 
      
      final next = Offset(pt.x.toDouble(), pt.y.toDouble());
      if (mounted && next != _screenPos) {
        setState(() => _screenPos = next);
      }
    } catch (e) {
      debugPrint("📍 PIN PROJECTION ERROR: $e");
    }
  }

  @override
  void dispose() {
    _projectionTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("📍 PIN RENDER CHECK -> Target: ${widget.target}, ScreenPos: $_screenPos");
    if (_screenPos == null || widget.target == null) {
      return const SizedBox.shrink();
    }

    const double pinWidth = 140.0;
    const double pinHeight = 140.0;

    return Positioned(
      left: _screenPos!.dx - (pinWidth / 2),
      top: _screenPos!.dy - pinHeight,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox(
            width: pinWidth,
            height: pinHeight,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => CustomPaint(
                painter: _PulsePinPainter(
                  progress: _pulseController.value,
                  isDark: widget.isDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 🎨 CUSTOM PAINTER — Premium Breathing Pin
// ═══════════════════════════════════════════════════════════════════════════════

class _PulsePinPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0 repeating
  final bool isDark;

  _PulsePinPainter({required this.progress, required this.isDark});

  // Design tokens
  static const double _coreRadius = 7.5;
  static const double _casingRadius = 13.0;
  static const double _maxPulseRadius = 50.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double safeProgress = progress.clamp(0.0, 1.0);

    // ── PULSE RING 1 ──
    _paintPulseRing(canvas, center, safeProgress);

    // ── PULSE RING 2 (phase-offset by 0.5 for continuous breathing) ─────────────────
    _paintPulseRing(canvas, center, (safeProgress + 0.5) % 1.0);

    // ── CASING (Theme-Aware) ──
    if (isDark) {
      // Dark Mode: frosted glass casing + subtle white glow
      canvas.drawCircle(
        center,
        _casingRadius + 6,
        Paint()
          ..color = _neonCyan.withValues(alpha: 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        center,
        _casingRadius,
        Paint()..color = const Color(0xFF1A1D24).withValues(alpha: 0.92),
      );
      canvas.drawCircle(
        center,
        _casingRadius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    } else {
      // Light Mode: clean white casing + soft drop shadow
      canvas.drawCircle(
        center + const Offset(0, 2.5),
        _casingRadius + 1,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        center,
        _casingRadius,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        center,
        _casingRadius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // ── CORE GLOW (neon bloom) ──
    canvas.drawCircle(
      center,
      _coreRadius + 3,
      Paint()
        ..color = _neonCyan.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // ── CORE DOT (solid neon cyan) ──
    canvas.drawCircle(
      center,
      _coreRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _neonCyan.withValues(alpha: 1.0),
            const Color(0xFF00B8D4),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: _coreRadius)),
    );

    // ── SPECULAR HIGHLIGHT (Apple-level depth) ──
    canvas.drawCircle(
      center + const Offset(-2.0, -2.5),
      _coreRadius * 0.35,
      Paint()..color = Colors.white.withValues(alpha: 0.50),
    );
  }

  void _paintPulseRing(Canvas canvas, Offset center, double t) {
    final eased = Curves.easeOutCubic.transform(t);
    final radius = _casingRadius + (_maxPulseRadius - _casingRadius) * eased;
    final opacity = 0.30 * (1.0 - t);

    if (opacity < 0.01) return;

    // Stroke ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _neonCyan.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - t * 0.6),
    );

    // Soft fill bloom behind the ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _neonCyan.withValues(alpha: opacity * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_PulsePinPainter old) =>
      old.progress != progress || old.isDark != isDark;
}
