
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

// 🚀 NATIVE THEMES ONLY
enum MapThemeType { light, dark }

class MapStyleHelper {
  static const String _dataUriPrefix = 'data:application/json;charset=utf-8,';

  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType,
      bool showPOIs = true,
      bool show3D = false}) async {
    final bool useDark =
        themeType != null ? (themeType == MapThemeType.dark) : isSystemDark;

    debugPrint(
        "🚀 MapStyleHelper running: isSystemDark=$isSystemDark, themeType=$themeType, useDark=$useDark");

    try {
      // 1. Load the raw JSON from local assets based on theme
      final String styleFileName = useDark ? 'assets/ridel_dark_theme.json' : 'assets/style.json';
      final String rawStyleString = await rootBundle.loadString(styleFileName);

      // 2. Output properly based on platform
      final String outputStyle = kIsWeb
          ? "$_dataUriPrefix${Uri.encodeComponent(rawStyleString)}"
          : rawStyleString;

      return outputStyle;
    } catch (e) {
      debugPrint("🚨 CRITICAL: Failed to load style $e");
      // Fallback to the original file if everything completely fails
      final fallbackString = await rootBundle.loadString('assets/style.json');
      return kIsWeb
          ? "$_dataUriPrefix${Uri.encodeComponent(fallbackString)}"
          : fallbackString;
    }
  }
}
