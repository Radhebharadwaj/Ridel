import 'dart:ui';
import 'package:flutter/material.dart';

class RidelGlassModal extends StatelessWidget {
  final Widget child;
  final double? height;
  final double? width;

  const RidelGlassModal({super.key, required this.child, this.height, this.width});

  // Static function to show modal anywhere
  static Future<T?> show<T>(BuildContext context, {required Widget child, double? height}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Modal",
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, a1, a2) => RidelGlassModal(height: height, child: child),
      transitionBuilder: (ctx, a1, a2, child) => FadeTransition(opacity: a1, child: ScaleTransition(scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack), child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ DYNAMIC THEME COLOR
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Agar Dark Mode hai to Dark Glass, Light Mode hai to White Glass
    final bgColor = isDark 
        ? const Color(0xFF1C1C1E).withOpacity(0.85) 
        : Colors.white.withOpacity(0.9);
        
    final borderColor = isDark 
        ? Colors.white.withOpacity(0.1) 
        : Colors.black.withOpacity(0.05);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: width ?? MediaQuery.of(context).size.width * 0.85,
              height: height,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgColor, // ✅ Uses Theme Color
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: borderColor),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 30, spreadRadius: 5)],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}