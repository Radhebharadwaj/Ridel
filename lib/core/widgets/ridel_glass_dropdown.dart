import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_haptics.dart';

class RidelGlassDropdown {
  static void show(BuildContext context, {
    required List<String> options, 
    required Function(String) onSelected, 
    String? selectedValue
  }) {
    AppHaptics.selectionClick();
    
    // Status bar height nikal rahe hain taaki har phone me exactly header ke niche khule
    final topPadding = MediaQuery.of(context).padding.top; 

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dropdown",
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250), // Thoda aur smooth
      pageBuilder: (context, a1, a2) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        final bgColor = isDark 
            ? Colors.white.withOpacity(0.12) 
            : Colors.white.withOpacity(0.95);
            
        final textColor = isDark ? Colors.white : Colors.black;
        final borderColor = isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.1);
        final checkColor = isDark ? Colors.cyanAccent : Colors.cyan;

        return Stack(
          children: [
            // Background Dim (Tap to close)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.black.withOpacity(0.15)), 
              )
            ),
            
            // 🔥 Yahan Positioned laga kar dropdown ko exactly Bell ke neeche shift kiya hai
            Positioned(
              top: topPadding + 55, // Header size ke according exact offset
              right: 20, // Right edge se thoda gap
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      width: 230, // Thoda compact kiya taaki aur clean lage
                      decoration: BoxDecoration(
                        color: bgColor, 
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: borderColor, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 10)
                          )
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final item = options[index];
                          final isSelected = item == selectedValue;
                          return InkWell(
                            onTap: () { Navigator.pop(context); onSelected(item); },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    item, 
                                    style: GoogleFonts.inter(
                                      color: textColor.withOpacity(isSelected ? 1.0 : 0.8), 
                                      fontSize: 15, 
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500
                                    )
                                  ),
                                  if (isSelected) 
                                    Icon(Icons.check_circle_rounded, color: checkColor, size: 18),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            alignment: Alignment.topRight, 
            child: child,
          ),
        );
      },
    );
  }
}