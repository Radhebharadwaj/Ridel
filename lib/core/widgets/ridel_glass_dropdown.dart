import 'package:flutter/material.dart';
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

    final isDark = Theme.of(tileContext).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF1E1E1E).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.90);
    final textColor = isDark ? Colors.white : Colors.black;

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
        return Stack(
          children: [
            Positioned(
              top: top,
              left: left,
              width: menuWidth,
              child: Material(
                color: Colors.transparent,
                child: RidelGlass(
                  borderRadius: BorderRadius.circular(20),
                  blurSigma: 25.0,
                  baseColor: bgColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: options.map((option) {
                      final isSelected = option == selectedValue;
                      return InkWell(
                        onTap: () {
                          AppHaptics.selectionClick();
                          Navigator.pop(context);
                          onSelected(option);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.05),
                                width: option != options.last ? 1 : 0,
                              ),
                            ),
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
                                    color: Colors.cyan, size: 18),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
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
