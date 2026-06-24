// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary Brand Color
  static const primaryColor = CupertinoColors.systemBlue;

  static const _darkBg = Color(0xFF0B0E17);
  static const _darkCard = Color(0xFF262626);

  static const _lightBg = Colors.white;
  static const _lightCard = Colors.white;

  // Font Picker Logic
  static TextTheme _getTextTheme(String fontType, bool isDark) {
    TextTheme base =
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return GoogleFonts.interTextTheme(base);
  }

  // 🌙 DARK THEME
  static ThemeData getDarkTheme(String fontType) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkBg,
      primaryColor: primaryColor,
      cardColor: _darkCard,
      textTheme: _getTextTheme(fontType, true)
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBg,
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkCard,
        modalBackgroundColor: _darkCard,
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        surface: _darkBg,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android:
              ZoomPageTransitionsBuilder(), // Ya jo bhi aap use kar rahe hain
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ☀️ LIGHT THEME
  static ThemeData getLightTheme(String fontType) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBg,
      primaryColor: Colors.black,
      cardColor: _lightCard,
      textTheme: _getTextTheme(fontType, false)
          .apply(bodyColor: Colors.black, displayColor: Colors.black),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightBg,
        iconTheme: IconThemeData(color: Colors.black),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        surface: _lightBg,
      ),
    );
  }
}
