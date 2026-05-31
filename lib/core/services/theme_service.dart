import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';

enum AppThemeMode { light, dark, system, autoTime }

class ThemeService with WidgetsBindingObserver {
  static final ThemeService _instance = ThemeService._internal();

  ThemeService._internal();

  static void init() {
    WidgetsBinding.instance.addObserver(_instance);
    _updateThemeMode(); // Evaluate initially so it applies immediately
  }

  // 1. App Theme Mode (Dark/Light/System/AutoTime)
  static final ValueNotifier<AppThemeMode> appThemeNotifier = ValueNotifier(AppThemeMode.autoTime);
  
  // Actually computed Flutter ThemeMode
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light); // updated dynamically in init()

  // 2. Font Style (Modern/Classic)
  static final ValueNotifier<String> fontNotifier = ValueNotifier('Modern');

  // Action to Switch Theme
  static void switchTheme(AppThemeMode mode) {
    appThemeNotifier.value = mode;
    _updateThemeMode();
  }

  static Future<void> _updateThemeMode() async {
    if (appThemeNotifier.value == AppThemeMode.autoTime) {
      final now = DateTime.now();
      
      // 1. INSTANT FALLBACK: Do not block the UI waiting for Web location permissions
      _applySolarTheme(now, 28.6139, 77.2090);

      // 2. ASYNC UPDATE: If location is already granted or becomes available, update silently
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          _applySolarTheme(now, pos.latitude, pos.longitude);
        }
      } catch (e) {
        debugPrint("Location denied or failed, using default coordinates for theme computation.");
      }
    } else {
      switch (appThemeNotifier.value) {
        case AppThemeMode.light:
          themeNotifier.value = ThemeMode.light;
          break;
        case AppThemeMode.dark:
          themeNotifier.value = ThemeMode.dark;
          break;
        case AppThemeMode.system:
        default:
          themeNotifier.value = ThemeMode.system;
          break;
      }
    }
  }

  static void _applySolarTheme(DateTime now, double lat, double lng) {
    try {
      final utcOffset = now.timeZoneOffset; // Passes a Duration object
      final calc = getSunriseSunset(lat, lng, utcOffset, now);
      
      final isDaytime = now.isAfter(calc.sunrise) && now.isBefore(calc.sunset);
      themeNotifier.value = isDaytime ? ThemeMode.light : ThemeMode.dark;
    } catch (e) {
      // Hard fallback
      final hour = now.hour;
      final isDaytime = hour >= 6 && hour < 18;
      themeNotifier.value = isDaytime ? ThemeMode.light : ThemeMode.dark;
    }
  }

  // Action to Switch Font
  static void switchFont(String fontType) {
    fontNotifier.value = fontType;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateThemeMode();
    }
  }
}