// lib/features/commute/shared/widgets/route_header.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';

class RouteHeader extends StatelessWidget {
  final String fromStation;
  final String toStation;
  final double topPadding;
  final bool isScrolled;
  final VoidCallback onBack;
  final Function(String, String) onSwap;

  const RouteHeader({
    super.key,
    required this.fromStation,
    required this.toStation,
    required this.topPadding,
    required this.isScrolled,
    required this.onBack,
    required this.onSwap,
  });

  // 🚀 Premium Title Case Formatter
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  // Formatting for long names to avoid overflow
  String _formatStationName(String name) {
    if (name.length > 15) return "${name.substring(0, 13)}...";
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final double safeTop = topPadding == 0 ? 20.0 : topPadding + 10.0;
    const themeBgDark = Color(0xFF0B0E17); // Premium deep background

    return ClipRect(
      // 🚀 The Magic: Gradient Mask for Smooth Fade-Out Blur
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.5, 1.0], // Blur fades out perfectly at the bottom
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding:
                EdgeInsets.only(top: safeTop, left: 16, right: 16, bottom: 24),
            decoration: BoxDecoration(
              // Smooth Color Gradient overlay
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isLightMode
                    ? [
                        Colors.white,
                        Colors.white.withValues(alpha: 0.6),
                        Colors.white.withValues(alpha: 0.0)
                      ]
                    : [
                        themeBgDark.withValues(alpha: 0.95), // Dark solid top
                        themeBgDark.withValues(alpha: 0.6), // Fading mid
                        themeBgDark.withValues(alpha: 0.0) // Transparent bottom
                      ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth < 240 ? 240 : constraints.maxWidth,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ==================== 1. CONSISTENT LIQUID BACK BUTTON ====================
                        RidelLiquidButton(
                          width: 44,
                          height: 44,
                          shapeType: LiquidShapeType.circle,
                          glassTint: isLightMode 
                              ? Colors.black.withValues(alpha: 0.04) 
                              : Colors.white.withValues(alpha: 0.08),
                          onTap: onBack,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 2.0),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                color: isLightMode ? Colors.black87 : Colors.white, size: 18),
                          ),
                        ),
        
                        const SizedBox(width: 16),
        
                        // ==================== 2. THE CALM FLOATING TEXT ====================
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // FROM STATION (Calm & Dimmed)
                              Flexible(
                                child: Text(
                                  _toTitleCase(_formatStationName(fromStation)),
                                  style: GoogleFonts.inter(
                                    color: isLightMode
                                        ? Colors.black54
                                        : Colors.white.withValues(alpha: 0.65), // 💎 Smooth fade
                                    fontSize: 16, // 🚀 Bada aur clean
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3, // 💎 Premium tight spacing
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
        
                              // SWAP ICON (Minimal)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                                child: RidelBounceButton(
                                  scaleFactor: 0.80,
                                  useHeavyHaptic: true,
                                  onTap: () => onSwap(toStation, fromStation),
                                  child: Icon(
                                    Icons.swap_horiz_rounded,
                                    color: isLightMode
                                        ? Colors.black26
                                        : Colors.white.withValues(alpha: 0.3),
                                    size: 20,
                                  ),
                                ),
                              ),
        
                              // TO STATION (Bright & Popping)
                              Flexible(
                                child: Text(
                                  _toTitleCase(_formatStationName(toStation)),
                                  style: GoogleFonts.inter(
                                    color: isLightMode
                                        ? Colors.black87
                                        : Colors.white.withValues(alpha: 0.95), // 💎 Bright focus
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700, // Thicker weight
                                    letterSpacing: -0.4,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ],
                          ),
                        ),
        
                        // Invisible spacer (width matches back button + padding) to keep text 100% mathematically centered
                        const SizedBox(width: 60),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
