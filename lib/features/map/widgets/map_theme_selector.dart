import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';

/// 🚀 ULTRA-MINIMALIST FLOATING GLASS MAP THEME SELECTOR
/// This ONLY changes the map's render style (Dark/Light tiles).
/// It does NOT trigger any global app theme change.
class MapThemeSelector {
  static void show(
    BuildContext anchorContext, {
    required MapThemeType currentTheme,
    required ValueChanged<MapThemeType> onThemeSelected,
  }) {
    final RenderBox renderBox = anchorContext.findRenderObject()! as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size anchorSize = renderBox.size;

    // Adjusted dimensions since the header is removed
    const double popupWidth = 150.0;
    const double estimatedHeight = 100.0;

    // Position the popup to the LEFT of the anchor, vertically centered
    final double top =
        offset.dy + (anchorSize.height / 2) - (estimatedHeight / 2);
    final double left = math.max(16.0, offset.dx - popupWidth - 12);

    showDialog(
      context: anchorContext,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return Stack(
          children: [
            Positioned(
              top: top,
              left: left,
              width: popupWidth,
              child: Material(
                color: Colors.transparent,
                child: _MapThemePopup(
                  currentTheme: currentTheme,
                  onThemeSelected: (theme) {
                    Navigator.pop(context);
                    onThemeSelected(theme);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MapThemePopup extends StatelessWidget {
  final MapThemeType currentTheme;
  final ValueChanged<MapThemeType> onThemeSelected;

  const _MapThemePopup({
    required this.currentTheme,
    required this.onThemeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    const Color darkBgColor = Color(0xFF0F1118);

    final content = Padding(
      padding: const EdgeInsets.all(6.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dark Mode Option
          _ThemeOption(
            icon: Icons.dark_mode_rounded,
            label: 'Dark',
            isSelected: currentTheme == MapThemeType.dark,
            isLightMode: isLightMode,
            onTap: () {
              AppHaptics.selectionClick();
              onThemeSelected(MapThemeType.dark);
            },
          ),

          const SizedBox(height: 4),

          // Light Mode Option
          _ThemeOption(
            icon: Icons.light_mode_rounded,
            label: 'Light',
            isSelected: currentTheme == MapThemeType.light,
            isLightMode: isLightMode,
            onTap: () {
              AppHaptics.selectionClick();
              onThemeSelected(MapThemeType.light);
            },
          ),
        ],
      ),
    );

    // Wrapping in GestureDetector with opaque behavior STOPS touch events
    // from leaking through to the map underneath.
    return GestureDetector(
      onTap: () {}, // Swallows empty taps on the background
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: isLightMode ? Colors.white : null,
          borderRadius: BorderRadius.circular(18),
          border: isLightMode ? Border.all(color: Colors.grey.shade200) : null,
          boxShadow: isLightMode
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))]
              : null,
        ),
        child: isLightMode
            ? content
            : RidelGlass(
                borderRadius: BorderRadius.circular(18),
                blurSigma: 30.0,
                baseColor: darkBgColor.withValues(alpha: 0.85),
                isVerticalCard: true,
                child: content,
              ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLightMode;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isLightMode,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentCyan = isLightMode ? Colors.cyan.shade700 : const Color(0xFF00E5FF);

    // Using GestureDetector instead of InkWell prevents visual ripple bleed
    // and strictly enforces HitTestBehavior to block map touches.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentCyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? accentCyan : (isLightMode ? Colors.black54 : Colors.white60),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: isSelected 
                      ? (isLightMode ? Colors.black87 : Colors.white)
                      : (isLightMode ? Colors.black87 : Colors.white70),
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                color: accentCyan,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
