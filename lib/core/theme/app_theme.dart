// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Unified Google Maps iOS-grade floating surface tokens.
///
/// On Mobile (!kIsWeb): Crisp high-opacity ceramic white (light) and obsidian
/// slate (dark) with delicate 0.5px hairlines and soft layered shadows — zero
/// GPU BackdropFilter readback lag, razor-sharp map legibility.
///
/// On Web (kIsWeb): Subtle frosted translucency paired with AdaptiveBlur.
class RidelSurfaceTokens {
  RidelSurfaceTokens._();

  static const Color iosBlueLight = Color(0xFF1A73E8);
  static const Color iosBlueDark = Color(0xFF0A84FF);

  static Color pillBackground(bool isDark, {bool elevated = false}) {
    if (isDark) {
      return kIsWeb
          ? const Color(0xFF10141E).withValues(alpha: elevated ? 0.86 : 0.78)
          : const Color(0xFF151923).withValues(alpha: elevated ? 0.97 : 0.94);
    }
    return kIsWeb
        ? Colors.white.withValues(alpha: elevated ? 0.90 : 0.84)
        : const Color(0xFFFFFFFF).withValues(alpha: elevated ? 0.98 : 0.96);
  }

  static Color sheetBackground(bool isDark) {
    if (isDark) {
      return kIsWeb
          ? const Color(0xFF10141E).withValues(alpha: 0.86)
          : const Color(0xFF121620).withValues(alpha: 0.97);
    }
    return kIsWeb
        ? Colors.white.withValues(alpha: 0.88)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.98);
  }

  static Color border(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.11)
      : Colors.black.withValues(alpha: 0.07);

  static Color divider(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.09)
      : Colors.black.withValues(alpha: 0.08);

  static List<BoxShadow> pillShadows(bool isDark) => isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ]
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ];

  static List<BoxShadow> sheetShadows(bool isDark) => isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ]
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ];
}

class AppTheme {
  static const primaryColor = RidelSurfaceTokens.iosBlueDark;

  static const _darkBg = Color(0xFF0B0E17);
  static const _darkCard = Color(0xFF181C26);

  static const _lightBg = Color(0xFFFFFFFF);
  static const _lightCard = Color(0xFFFFFFFF);

  static TextTheme _getTextTheme(String fontType, bool isDark) {
    final TextTheme base =
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    return GoogleFonts.interTextTheme(base);
  }

  static ThemeData getDarkTheme(String fontType) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkBg,
      primaryColor: RidelSurfaceTokens.iosBlueDark,
      cardColor: _darkCard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _getTextTheme(fontType, true)
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBg,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkCard,
        modalBackgroundColor: _darkCard,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: const ColorScheme.dark(
        primary: RidelSurfaceTokens.iosBlueDark,
        surface: _darkBg,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData getLightTheme(String fontType) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBg,
      primaryColor: RidelSurfaceTokens.iosBlueLight,
      cardColor: _lightCard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _getTextTheme(fontType, false)
          .apply(bodyColor: const Color(0xFF111318), displayColor: const Color(0xFF111318)),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightBg,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: Color(0xFF111318)),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightCard,
        modalBackgroundColor: _lightCard,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: const ColorScheme.light(
        primary: RidelSurfaceTokens.iosBlueLight,
        surface: _lightBg,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
