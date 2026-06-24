import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';
import 'package:ridel/core/utils/app_haptics.dart';

class RidelGlassDropdown {
  static void show(
    BuildContext tileContext, {
    required List<String> options,
    required String? selectedValue,
    required Function(String) onSelected,
  }) {
    // 🚀 EXACT POSITION CALCULATION
    final RenderBox renderBox = tileContext.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    // Menu width & position logic
    const double menuWidth = 200.0;
    double top = offset.dy + size.height; // Open below tile
    double left = offset.dx + size.width - menuWidth - 16; // Align right

    // If opening below goes off screen, open above
    if (top + (options.length * 50) > MediaQuery.of(tileContext).size.height) {
      top = offset.dy - (options.length * 50) - 10;
    }

    showDialog(
      context: tileContext,
      barrierColor: Colors.transparent, // Invisible barrier to close on tap out
      builder: (BuildContext context) {
        final isLightMode = Theme.of(context).brightness == Brightness.light;
        final bgColor = isLightMode
            ? Colors.white.withValues(alpha: 0.95)
            : const Color(0xFF1C1F26).withValues(alpha: 0.95);
        final textColor = isLightMode ? Colors.black87 : Colors.white;
        
        return Stack(
          children: [
            Positioned(
              top: top,
              left: left,
              width: menuWidth,
              child: Material(
                color: Colors.transparent,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 850),
                  switchInCurve: Curves.easeInOutQuart,
                  switchOutCurve: Curves.easeInOutQuart,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isLightMode ? 0.08 : 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: RidelGlass(
                      key: ValueKey(isLightMode),
                      borderRadius: BorderRadius.circular(24),
                      blurSigma: 25.0,
                      baseColor: bgColor,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: options.map((option) {
                            final isSelected = option == selectedValue;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2.0),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  AppHaptics.selectionClick();
                                  Navigator.pop(context);
                                  onSelected(option);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isSelected 
                                      ? (isLightMode ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05))
                                      : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        option,
                                        style: GoogleFonts.inter(
                                          color: textColor,
                                          fontSize: 14,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle_rounded,
                                            color: CupertinoColors.systemBlue, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
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
