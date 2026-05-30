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
  Offset? _screenPos;

  // Throttle: only re-project every N frames to avoid flooding method channel
  int _frameCounter = 0;
  static const int _projectionInterval = 2; // every 2nd frame ≈ 30fps position updates

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _pulseController.addListener(_onTick);
    _projectPosition();
  }

  @override
  void didUpdateWidget(AnimatedMapPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target || oldWidget.mapController != widget.mapController) {
      _projectPosition(); // Immediately re-project on target change
    }
  }

  void _onTick() {
    _frameCounter++;
    if (_frameCounter % _projectionInterval == 0) {
      _projectPosition();
    }
  }

  /// Call externally on camera idle / camera move events for extra accuracy.
  void syncPosition() => _projectPosition();

  Future<void> _projectPosition() async {
    final ctrl = widget.mapController;
    final target = widget.target;
    if (ctrl == null || target == null) {
      if (_screenPos != null && mounted) setState(() => _screenPos = null);
      return;
    }
    try {
      final pt = await ctrl.toScreenLocation(target);
      final next = Offset(pt.x.toDouble(), pt.y.toDouble());
      if (mounted && next != _screenPos) {
        setState(() => _screenPos = next);
      }
    } catch (_) {
      // Map controller disposed or not ready — safe to ignore
    }
  }

  @override
  void dispose() {
    _pulseController.removeListener(_onTick);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_screenPos == null || widget.target == null) {
      return const SizedBox.shrink();
    }

    const double canvasSize = 140.0;

    return Positioned(
      left: _screenPos!.dx - canvasSize / 2,
      top: _screenPos!.dy - canvasSize / 2,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: SizedBox(
            width: canvasSize,
            height: canvasSize,
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

    // ── PULSE RING 1 ──
    _paintPulseRing(canvas, center, progress);

    // ── PULSE RING 2 (phase-offset by 0.5 for continuous breathing) ──
    _paintPulseRing(canvas, center, (progress + 0.5) % 1.0);

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
