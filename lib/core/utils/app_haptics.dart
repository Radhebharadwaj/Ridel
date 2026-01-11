// lib/utils/app_haptics.dart

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; 
import 'dart:io' show Platform; 

class AppHaptics {
  static bool canVibrate = true; 

  // 1. Light (Tabs, Small Toggles)
  static Future<void> lightImpact() async {
    if (kIsWeb || !canVibrate) return; 

    if (Platform.isAndroid) { 
      await HapticFeedback.selectionClick();
    } else {
      await HapticFeedback.lightImpact();
    }
  }

  // 2. Medium (Buttons, Cards)
  static Future<void> mediumImpact() async {
    if (kIsWeb || !canVibrate) return;
    await HapticFeedback.mediumImpact();
  }

  // 3. Heavy (Navigation, Confirm actions)
  static Future<void> heavyImpact() async {
    if (kIsWeb || !canVibrate) return;

    if (Platform.isAndroid) {
      await HapticFeedback.vibrate(); 
    } else {
      await HapticFeedback.heavyImpact();
    }
  }

  // 4. Tick (Scrolls)
  static Future<void> tickImpact() async {
    if (kIsWeb || !canVibrate) return;
    await HapticFeedback.selectionClick();
  }
}