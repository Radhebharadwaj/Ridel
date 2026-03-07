import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/services/theme_service.dart';

class AppearanceSheetContent extends StatelessWidget {
  const AppearanceSheetContent({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to changes for UI update
    return AnimatedBuilder(
      animation: Listenable.merge([ThemeService.themeNotifier, ThemeService.fontNotifier]),
      builder: (context, _) {
        final currentMode = ThemeService.themeNotifier.value;
        final currentFont = ThemeService.fontNotifier.value;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return ScrollConfiguration(
          // ✅ HIDES SCROLL BAR (Side Line)
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------------------------------------
              // 🟢 CLEAN HEADER (Back Arrow Only)
              // ---------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 10, 20, 20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        AppHaptics.lightImpact();
                        Navigator.pop(context);
                      },
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : Colors.black, size: 22),
                    ),
                    const SizedBox(width: 0),
                    Text(
                      "Appearance",
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white : Colors.black, 
                        fontSize: 20, 
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
              ),

              // ---------------------------------------------
              // 🎨 THEME SECTION (Compact & Glassy)
              // ---------------------------------------------
              _sectionLabel("THEME MODE"),
              const SizedBox(height: 10),
              Container(
                height: 55,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(child: _ThemeTab("Dark", Icons.dark_mode_rounded, currentMode == ThemeMode.dark, () => ThemeService.switchTheme(ThemeMode.dark))),
                    Expanded(child: _ThemeTab("Light", Icons.light_mode_rounded, currentMode == ThemeMode.light, () => ThemeService.switchTheme(ThemeMode.light))),
                    Expanded(child: _ThemeTab("System", Icons.phone_android_rounded, currentMode == ThemeMode.system, () => ThemeService.switchTheme(ThemeMode.system))),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // ---------------------------------------------
              // 🔤 FONT SECTION (Compact Tiles)
              // ---------------------------------------------
              _sectionLabel("FONT STYLE"),
              const SizedBox(height: 10),
              
              _FontTile(
                title: "Modern", 
                preview: "Clean & Minimal", 
                isSelected: currentFont == 'Modern',
                isDark: isDark,
                onTap: () => ThemeService.switchFont('Modern'),
              ),
              const SizedBox(height: 10),
              _FontTile(
                title: "Classic", 
                preview: "Elegant Serif", 
                isSelected: currentFont == 'Classic',
                isDark: isDark,
                onTap: () => ThemeService.switchFont('Classic'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }
}

// 🌑 COMPACT THEME TAB
class _ThemeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeTab(this.label, this.icon, this.isSelected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () { AppHaptics.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? const Color(0xFF2A2A2D) : Colors.white) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: const Color(0xFF00E5FF), width: 1.5) : null,
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)] : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? const Color(0xFF00E5FF) : Colors.grey),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(
              color: isSelected ? (isDark ? Colors.white : Colors.black) : Colors.grey, 
              fontWeight: FontWeight.w600, 
              fontSize: 13
            )),
          ],
        ),
      ),
    );
  }
}

// 🔤 COMPACT FONT TILE
class _FontTile extends StatelessWidget {
  final String title;
  final String preview;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _FontTile({required this.title, required this.preview, required this.isSelected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { AppHaptics.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected 
              ? (const Color(0xFF00E5FF).withOpacity(0.1)) 
              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(16),
          border: isSelected 
              ? Border.all(color: const Color(0xFF00E5FF), width: 1.5) 
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 15
                )),
                Text(preview, style: title == 'Classic' 
                    ? GoogleFonts.dmSerifDisplay(color: Colors.grey, fontSize: 13)
                    : GoogleFonts.inter(color: Colors.grey, fontSize: 13)
                ),
              ],
            ),
            if (isSelected) 
              const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5FF), size: 22),
          ],
        ),
      ),
    );
  }
}