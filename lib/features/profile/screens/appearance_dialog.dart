import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/services/theme_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';

class AppearanceDialog extends StatelessWidget {
  const AppearanceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔥 Check Theme Brightness
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;
    final Color cardColor = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;

    return AnimatedBuilder(
      animation: Listenable.merge([ThemeService.themeNotifier, ThemeService.fontNotifier]),
      builder: (context, _) {
        final currentMode = ThemeService.themeNotifier.value;
        final currentFont = ThemeService.fontNotifier.value;
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Title (Dynamic Color)
            Text("Appearance", style: GoogleFonts.inter(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),

            // 🎨 THEME TOGGLE
            Container(
              height: 50,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cardColor, // Dynamic Background
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  _ThemeTab("System", Icons.phone_android_rounded, currentMode == ThemeMode.system, () => ThemeService.switchTheme(ThemeMode.system)),
                  _ThemeTab("Dark", Icons.dark_mode_rounded, currentMode == ThemeMode.dark, () => ThemeService.switchTheme(ThemeMode.dark)),
                  _ThemeTab("Light", Icons.light_mode_rounded, currentMode == ThemeMode.light, () => ThemeService.switchTheme(ThemeMode.light)),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 🔤 FONTS SECTION
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 10),
                child: Text("FONT STYLE", style: GoogleFonts.inter(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
            
            // Pass isDark to helper widgets
            _FontOption("Modern", "Clean & Minimal", currentFont == "Modern", isDark, () => ThemeService.switchFont("Modern")),
            const SizedBox(height: 10),
            _FontOption("Classic", "Elegant Serif", currentFont == "Classic", isDark, () => ThemeService.switchFont("Classic")),

            const SizedBox(height: 30),

            // DONE BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () { AppHaptics.lightImpact(); Navigator.pop(context); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black, // Inverted for contrast
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
                ),
                child: Text("Done", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Helper Widgets Update

class _ThemeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _ThemeTab(this.label, this.icon, this.isSelected, this.onTap);
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Selected Color Logic
    final selectedBg = const Color(0xFF00E5FF); // Cyan
    
    return Expanded(
      child: GestureDetector(
        onTap: () { AppHaptics.selectionClick(); onTap(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? selectedBg : Colors.transparent, 
            borderRadius: BorderRadius.circular(22)
          ),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: isSelected ? Colors.black : Colors.grey),
              const SizedBox(width: 6),
              if (isSelected) Flexible(child: Text(label, style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))),
          ]),
        ),
      ),
    );
  }
}

class _FontOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isDark; // Added Param
  final VoidCallback onTap;
  
  const _FontOption(this.title, this.subtitle, this.isSelected, this.isDark, this.onTap);
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { AppHaptics.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          // Colors fixed for Light Mode
          color: isSelected 
              ? const Color(0xFF00E5FF).withOpacity(0.15) 
              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: const Color(0xFF00E5FF), width: 1.5) : Border.all(color: Colors.transparent),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Text Color Fixed
                Text(title, style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                Text(subtitle, style: title == 'Classic' ? GoogleFonts.dmSerifDisplay(color: Colors.grey, fontSize: 12) : GoogleFonts.inter(color: Colors.grey, fontSize: 12)),
            ]),
            if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF00E5FF), size: 20),
        ]),
      ),
    );
  }
}