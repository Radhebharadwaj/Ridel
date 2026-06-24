// lib/features/commute/shared/widgets/route_header.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';

class RouteHeader extends StatelessWidget implements PreferredSizeWidget {
  final String fromStation;
  final String toStation;
  final double topPadding;
  final bool isScrolled;
  final VoidCallback onBack;
  final Function(String, String) onSwap;
  final VoidCallback? onNavigateToStart;

  const RouteHeader({
    super.key,
    required this.fromStation,
    required this.toStation,
    required this.topPadding,
    required this.isScrolled,
    required this.onBack,
    required this.onSwap,
    this.onNavigateToStart,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

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

    return AppBar(
      backgroundColor: isLightMode
          ? Colors.white.withValues(alpha: 0.4)
          : Colors.black.withValues(alpha: 0.4),
      elevation: 0,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(color: Colors.transparent),
        ),
      ),
      leadingWidth: 70, // To give enough space for the custom liquid button
      leading: Center(
        child: RidelLiquidButton(
          width: 44,
          height: 44,
          shapeType: LiquidShapeType.circle,
          glassTint: isLightMode
              ? Colors.black.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.1), // Subtle frosted glass circular background
          onTap: onBack,
          child: Padding(
            padding: const EdgeInsets.only(right: 2.0),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                color: isLightMode ? Colors.black87 : Colors.white, size: 18),
          ),
        ),
      ),
      title: Row(
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
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
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
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
      actions: [
        if (onNavigateToStart != null)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: RidelLiquidButton(
                width: 44,
                height: 44,
                shapeType: LiquidShapeType.circle,
                glassTint: isLightMode
                    ? Colors.black.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.1),
                onTap: onNavigateToStart!,
                child: Icon(
                  Icons.near_me_rounded, // Sleek directional arrow
                  color: isLightMode ? Colors.black87 : Colors.white,
                  size: 20,
                ),
              ),
            ),
          )
        else
          // Invisible spacer to keep text 100% mathematically centered
          const SizedBox(width: 70),
      ],
      centerTitle: true,
    );
  }
}
