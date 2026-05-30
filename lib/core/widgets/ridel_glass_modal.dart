import 'package:flutter/material.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';

class RidelGlassModal extends StatelessWidget {
  final Widget child;
  final double? height;
  final double? width;

  const RidelGlassModal(
      {super.key, required this.child, this.height, this.width});

  static Future<T?> show<T>(BuildContext context,
      {required Widget child, double? height}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Modal",
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, a1, a2) =>
          RidelGlassModal(height: height, child: child),
      transitionBuilder: (ctx, a1, a2, child) => FadeTransition(
          opacity: a1,
          child: ScaleTransition(
              scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
              child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF1E1E1E).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);

    return Center(
      child: Material(
        color: Colors.transparent,
        // 🚀 FIXED: Keyboard Handling + Max Height limit for Smartwatches/Small Screens
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width ?? MediaQuery.of(context).size.width * 0.85,
              maxHeight: height ?? MediaQuery.of(context).size.height * 0.80,
            ),
            child: RidelGlass(
              borderRadius: BorderRadius.circular(40),
              blurSigma: 35.0,
              baseColor: bgColor,
              isLargeRect: true,
              child: Padding(
                padding: const EdgeInsets.all(24.0), // Perfect spacing
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
