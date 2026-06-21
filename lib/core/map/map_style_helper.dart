import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

// 🚀 NATIVE THEMES ONLY
enum MapThemeType { light, dark }

class MapStyleHelper {
  static const String _dataUriPrefix = 'data:application/json;charset=utf-8,';

  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType, bool showPOIs = true, bool show3D = false}) async {
    final bool useDark =
        themeType != null ? (themeType == MapThemeType.dark) : isSystemDark;
    
    debugPrint("🚀 MapStyleHelper running: isSystemDark=$isSystemDark, themeType=$themeType, useDark=$useDark");

    // We are building a robust, native Dart architecture starting from scratch using assets/style.json
    final String styleJson = await rootBundle.loadString('assets/style.json');

    final String outputStyle = kIsWeb
        ? "$_dataUriPrefix${Uri.encodeComponent(styleJson)}"
        : styleJson;

    return outputStyle;
  }
}
