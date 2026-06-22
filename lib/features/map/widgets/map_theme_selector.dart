import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/utils/app_haptics.dart';

/// 🚀 ULTRA-MINIMALIST FLOATING GLASS MAP THEME SELECTOR
/// This ONLY changes the map's render style (Dark/Light tiles).
/// It does NOT trigger any global app theme change.
class MapThemeSelector {
  static void show(
    BuildContext context, {
    required MapThemeType currentTheme,
    required Function(MapThemeType) onThemeSelected,
    required bool showPOIs,
    required ValueChanged<bool> onPOIsToggled,
  }) {
    // 1. Get exact button coordinates
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    final size = renderBox.size;

    // 2. Calculate offsets so card appears to the left of the pill
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;

    // Right edge of card = distance from right screen edge to the left side of the button + 16px padding
    final rightPosition = screenWidth - offset.dx + 16.0;

    // Bottom edge of card = distance from bottom screen edge to the bottom of the button
    final bottomPosition = screenHeight - (offset.dy + size.height);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DismissThemeSelector',
      barrierColor:
          Colors.transparent, // Invisible barrier so map is still visible
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              right: rightPosition,
              bottom: bottomPosition,
              child: ScaleTransition(
                scale: CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic),
                alignment: Alignment.bottomRight, // Scales out from the button
                child: FadeTransition(
                  opacity: animation,
                  child: Material(
                    color: Colors.transparent,
                    child: _MapThemePopup(
                      currentTheme: currentTheme,
                      showPOIs: showPOIs,
                      onPOIsToggled: onPOIsToggled,
                      onThemeSelected: (theme) {
                        onThemeSelected(theme);
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MapThemePopup extends StatefulWidget {
  final MapThemeType currentTheme;
  final ValueChanged<MapThemeType> onThemeSelected;
  final bool showPOIs;
  final ValueChanged<bool> onPOIsToggled;

  const _MapThemePopup({
    required this.currentTheme,
    required this.onThemeSelected,
    required this.showPOIs,
    required this.onPOIsToggled,
  });

  @override
  State<_MapThemePopup> createState() => _MapThemePopupState();
}

class _MapThemePopupState extends State<_MapThemePopup> {
  late bool _localShowPOIs;

  @override
  void initState() {
    super.initState();
    _localShowPOIs = widget.showPOIs;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {}, // Swallows empty taps on the background
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        // 🚀 CRITICAL FPS FIX: Cache the blur rasterization during animation
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Container(
              width: 200, // Sleek, constrained width
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0B0E17).withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(24),
                  border: Theme.of(context).brightness == Brightness.dark
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1.0)
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ThemeOption(
                    icon: Icons.dark_mode_rounded,
                    label: 'Dark',
                    isSelected: widget.currentTheme == MapThemeType.dark,
                    onTap: () {
                      AppHaptics.selectionClick();
                      widget.onThemeSelected(MapThemeType.dark);
                    },
                  ),
                  const SizedBox(height: 4),
                  _ThemeOption(
                    icon: Icons.light_mode_rounded,
                    label: 'Light',
                    isSelected: widget.currentTheme == MapThemeType.light,
                    onTap: () {
                      AppHaptics.selectionClick();
                      widget.onThemeSelected(MapThemeType.light);
                    },
                  ),
                  const SizedBox(height: 4),
                  _ThemeOption(
                    icon: Icons.satellite_alt_rounded,
                    label: 'Satellite',
                    isSelected: widget.currentTheme == MapThemeType.satellite,
                    onTap: () {
                      AppHaptics.selectionClick();
                      widget.onThemeSelected(MapThemeType.satellite);
                    },
                  ),
                  const SizedBox(height: 8),
                  Divider(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                    height: 1,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 4.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_offer_outlined,
                          size: 18,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.black54,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Shops & Places',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: Transform.scale(
                            scale: 0.75,
                            child: Switch(
                              value: _localShowPOIs,
                              activeTrackColor: const Color(0xFF0A84FF),
                              onChanged: (val) {
                                AppHaptics.selectionClick();
                                setState(() {
                                  _localShowPOIs = val;
                                });
                                widget.onPOIsToggled(val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const Color highlightColor = Color(0xFF0A84FF);
    final Color textColor =
        isSelected ? highlightColor : (isDark ? Colors.white : Colors.black87);
    final Color iconColor = isSelected
        ? highlightColor
        : (isDark ? Colors.white70 : Colors.black54);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: highlightColor,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
