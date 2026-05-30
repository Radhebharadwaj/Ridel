import 'package:flutter/material.dart';

class ThemeService {
  // 1. Theme Mode (Dark/Light/System)
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
  
  // 2. Font Style (Modern/Classic)
  static final ValueNotifier<String> fontNotifier = ValueNotifier('Modern');

  // Action to Switch Theme
  static void switchTheme(ThemeMode mode) {
    themeNotifier.value = mode;
  }

  // Action to Switch Font
  static void switchFont(String fontType) {
    fontNotifier.value = fontType;
  }
}