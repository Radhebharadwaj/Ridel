import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ridel/core/widgets/ridel_premium_loader.dart';

class BrandedLoader extends StatefulWidget {
  final bool isFullScreen;

  const BrandedLoader({
    super.key,
    this.isFullScreen = true,
  });

  @override
  State<BrandedLoader> createState() => _BrandedLoaderState();
}

class _BrandedLoaderState extends State<BrandedLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isFullScreen) {
      return const Center(
        child: RidelPremiumLoader(size: 32.0),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF161E28), // Premium Dark Base
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RepaintBoundary(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      // Sweeps tightly from left to right
                      begin: Alignment(-2.0 + (_controller.value * 4), -0.5),
                      end: Alignment(-1.0 + (_controller.value * 4), 0.5),
                      colors: [
                        Colors.white.withValues(alpha: 0.4), // Base dimmed state
                        Colors.white.withValues(alpha: 0.8), // Shimmer highlight
                        Colors.white.withValues(alpha: 0.4), // Back to base
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ).createShader(bounds);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.directions_bike,
                        color: Colors.white,
                        size: 38,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Maps",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "BETA",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
                const SizedBox(height: 30.0),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final timeSeconds = _controller.value * 3.5;
                    final delay = index * 0.2;
                    final cycleTime = (timeSeconds - delay) % 1.4;
                    
                    double offset = 0.0;
                    double opacity = 0.4;
                    
                    if (cycleTime > 0 && cycleTime < 0.7) {
                      final t = cycleTime / 0.7;
                      final val = sin(t * pi);
                      offset = val * -8.0;
                      opacity = 0.4 + (val * 0.6);
                    }
                    
                    return Transform.translate(
                      offset: Offset(0, offset),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white38,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
