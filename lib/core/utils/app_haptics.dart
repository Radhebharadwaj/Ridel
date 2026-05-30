import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum HapticLevel { full, light, off }

class AppHaptics {
  static final ValueNotifier<HapticLevel> hapticLevel =
      ValueNotifier(HapticLevel.full);
  static const _storage = FlutterSecureStorage();

  static Future<void> init() async {
    final saved = await _storage.read(key: 'haptic_level');
    if (saved == 'off') {
      hapticLevel.value = HapticLevel.off;
    } else if (saved == 'light') {
      hapticLevel.value = HapticLevel.light;
    } else {
      hapticLevel.value = HapticLevel.full;
    }
  }

  static Future<void> setLevel(HapticLevel level) async {
    hapticLevel.value = level;
    await _storage.write(key: 'haptic_level', value: level.name);
    if (level != HapticLevel.off && !kIsWeb) {
      HapticFeedback.mediumImpact();
    }
  }

  static bool get _isOff => hapticLevel.value == HapticLevel.off || kIsWeb;
  static bool get _isLight => hapticLevel.value == HapticLevel.light;

  // 🟢 CORE NATIVE IMPACTS (Optimized for Android Hardware)
  static void lightImpact() {
    if (_isOff) return;
    HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    if (_isOff) return;
    _isLight ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
  }

  static void heavyImpact() {
    if (_isOff) return;
    _isLight ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
  }

  static void selectionClick() {
    if (_isOff || _isLight) return;
    HapticFeedback.selectionClick();
  }

  // 🚀 PREMIUM UX PATTERNS (States)
  static void success() {
    if (_isOff) return;
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 120), () {
      // 120ms gives motor time to reset
      _isLight ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
    });
  }

  static void error() {
    if (_isOff) return;
    heavyImpact();
    Future.delayed(const Duration(milliseconds: 160), () {
      mediumImpact();
    });
  }

  static void warning() {
    if (_isOff) return;
    mediumImpact();
    Future.delayed(const Duration(milliseconds: 120), () => lightImpact());
  }

  // ⌨️ MICRO-INTERACTIONS
  static void buttonClick() {
    if (_isOff) return;
    // Crisp single tick. No double-buzzes for standard buttons.
    _isLight ? HapticFeedback.selectionClick() : HapticFeedback.lightImpact();
  }

  static void sheetInteraction() {
    if (_isOff || _isLight) return;
    HapticFeedback.mediumImpact(); // Solid thud when sheet hits the top
  }

  // 🆕 CONTINUOUS INTERACTIONS (Scroll & Swipe)
  static void scrollTick() {
    if (_isOff || _isLight) return;
    HapticFeedback.selectionClick(); // Hardware tick, won't lag the UI
  }

  static void sliderTick() {
    if (_isOff) return;
    HapticFeedback.selectionClick();
  }

  static void keypadTap() {
    if (_isOff || _isLight) return;
    HapticFeedback.selectionClick();
  }

  static void switchToggle() {
    if (_isOff) return;
    HapticFeedback.lightImpact();
  }

  static void typingTap() {
    if (_isOff || _isLight) return;
    HapticFeedback.selectionClick();
  }

  static void backspaceTap() {
    if (_isOff || _isLight) return;
    HapticFeedback.lightImpact();
  }
}
