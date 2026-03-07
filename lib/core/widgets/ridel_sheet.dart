import 'package:flutter/material.dart';
// Note: Apne app_haptics ka correct path check kar lena
import '../utils/app_haptics.dart'; 
import 'package:google_fonts/google_fonts.dart';

class RidelSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final bool showBackButton;
  final bool showCloseButton;
  final bool customHeader;
  final Color? sheetColor; 

  const RidelSheet({
    super.key,
    required this.title,
    required this.child,
    this.showBackButton = false,
    this.showCloseButton = false,
    this.customHeader = false,
    this.sheetColor,
  });

  static Future<T?> show<T>(BuildContext context,
      {required String title,
      required Widget child,
      bool showBackButton = false,
      bool showCloseButton = false,
      bool customHeader = false,
      bool enableDrag = true,
      Color? sheetColor}) { 
    
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true, // Ye true rakhna zaroori hai full-height sheets ke liye
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      elevation: 0, 
      enableDrag: enableDrag,
      transitionAnimationController: AnimationController(
          vsync: Navigator.of(context),
          duration: const Duration(milliseconds: 300)),
      builder: (context) => RidelSheet(
          title: title, 
          showBackButton: showBackButton, 
          showCloseButton: showCloseButton, 
          customHeader: customHeader,
          sheetColor: sheetColor, 
          child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double headerHeight = 85.0;
    
    // 🚀 THE MAGIC FIX 1: Universal constant height for all screens (85% of screen height)
    final double universalSheetHeight = MediaQuery.of(context).size.height * 0.85;
    
    // 🔥 Background Color
    final finalBgColor = sheetColor ?? (isDark ? const Color(0xFF1C1C1E).withOpacity(0.98) : Colors.white.withOpacity(0.98));
    
    // THE MAGIC FIX 2: Border color ko custom sheetColor ke sath sync kiya
    final solidSealColor = sheetColor ?? (isDark ? const Color(0xFF1C1C1E) : Colors.white);
    
    // Text aur icon colors ko dark bg ke hisaab se adjust kiya (incase light mode me bhi dark sheet khule)
    final bool isCustomDark = sheetColor != null && sheetColor!.computeLuminance() < 0.5;
    final textColor = (isDark || isCustomDark) ? Colors.white : Colors.black;
    final btnColor = (isDark || isCustomDark) ? const Color(0xFF2C2C2E) : Colors.grey.shade200;
    final iconColor = (isDark || isCustomDark) ? const Color(0xFF8E8E93) : Colors.black54;

    return Container(
      height: universalSheetHeight, // 🔥 YAHAN HEIGHT APPLY KI HAI
      decoration: BoxDecoration(
        color: finalBgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        border: Border.all(
          color: solidSealColor, // Ab map sheet me ye 0xFF0B0E17 ho jayega
          width: 1.5, 
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.6 : 0.15), 
            blurRadius: 40, 
            spreadRadius: 2,
            offset: const Offset(0, -2) 
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Content Layer
          Positioned.fill(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child, 
            ),
          ),

          // Header Layer
          if (!customHeader) 
          Positioned(
            top: 0, left: 0, right: 0, height: headerHeight,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                  colors: [
                    finalBgColor.withOpacity(0.0), 
                    finalBgColor.withOpacity(0.95), 
                    finalBgColor,
                    finalBgColor, 
                  ],
                  stops: const [0.0, 0.4, 0.7, 1.0], 
                ),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(width: 40, child: showBackButton ? GestureDetector(
                    onTap: () { AppHaptics.lightImpact(); Navigator.pop(context); },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: btnColor, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_ios_new_rounded, color: iconColor, size: 16),
                    ),
                  ) : null),

                  Text(title, style: GoogleFonts.inter(color: textColor, fontSize: 17, fontWeight: FontWeight.w600)),

                  SizedBox(width: 40, child: showCloseButton ? Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () { AppHaptics.lightImpact(); Navigator.pop(context); },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: btnColor, shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded, color: iconColor, size: 18),
                      ),
                    ),
                  ) : null), 
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}