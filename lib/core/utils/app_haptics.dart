import 'package:flutter/services.dart';

class AppHaptics {
  /// Halke taps ke liye (Profile icon, chote buttons)
  static Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }

  /// Normal taps ke liye (Navigation, Tab change)
  static Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }

  /// Bade actions ke liye (AI Chat kholna, Payment)
  static Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }

  /// Toggle/Switch actions ke liye
  static Future<void> selectionClick() async {
    await HapticFeedback.selectionClick();
  }
  static void success() {
    HapticFeedback.heavyImpact();
    // Premium double-tap feel ke liye ek chota delay deke wapas light impact
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.lightImpact();
    });
  }
}