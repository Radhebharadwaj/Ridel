import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

// 🚀 NATIVE THEMES ONLY
enum MapThemeType { light, dark, satellite }

class MapStyleHelper {
  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType,
      bool showPOIs = true,
      bool show3D = false}) async {
    // CRITICAL: Replace 'YOUR_API_KEY_VARIABLE' with the actual API key string or variable used in this app.
    final String apiKey = AppConfig.olaMapsKey;

    String styleId;
    if (themeType == MapThemeType.satellite) {
      styleId = 'default-dark-standard-satellite';
    } else {
      final isDark =
          themeType != null ? (themeType == MapThemeType.dark) : isSystemDark;
      styleId = isDark ? 'default-dark-standard' : 'default-light-standard';
    }

    final styleUrl =
        'https://api.olamaps.io/tiles/vector/v1/styles/$styleId/style.json?api_key=$apiKey';

    try {
      final response = await http.get(Uri.parse(styleUrl));
      if (response.statusCode != 200) return styleUrl;

      Map<String, dynamic> styleJson = jsonDecode(response.body);

      // 1. INJECT API KEY INTO GLYPHS (FONTS)
      if (styleJson['glyphs'] != null) {
        String glyphs = styleJson['glyphs'].toString();
        if (glyphs.contains('?key=')) {
          glyphs = glyphs.split('?key=')[0]; // Strip Ola's broken caching key
        }
        styleJson['glyphs'] =
            '$glyphs${glyphs.contains('?') ? '&' : '?'}api_key=$apiKey';
      }

      // 2. INJECT API KEY INTO SPRITE (ICONS)
      if (styleJson['sprite'] != null) {
        String sprite = styleJson['sprite'].toString();
        if (sprite.contains('?key=')) {
          sprite = sprite.split('?key=')[0]; // Strip Ola's broken caching key
        }
        styleJson['sprite'] =
            '$sprite${sprite.contains('?') ? '&' : '?'}api_key=$apiKey';
      }

      // 3. FLATTEN SOURCES AND INJECT API KEY INTO TILES
      if (styleJson['sources'] != null) {
        Map<String, dynamic> sources = styleJson['sources'];
        for (String sourceKey in sources.keys) {
          final source = sources[sourceKey];

          // 🚀 THE FIX: Swap Ola's fragile raster for Esri's robust HD imagery
          if (source['type'] == 'raster' &&
              themeType == MapThemeType.satellite) {
            // 1. YAHAN APNI KEY PASTE KAR 👇
            const String esriToken =
                'AAPTal4MsXcfAEbpH6jpRXBHTuQ..UVXJRz0l3cvQ_zawLXOv_0aZXTksPiqOkS_4srJLrLyc9Ekrj8EIqCPrYSH3PhL289z001O22pbnkUSx1nZc88VEt7m4o97odpjP_XJIyy9Swkiop4jEqjqY1UNR9lfpK4srGoLwztzFq7fHpfAjo4ahiNYvNyZvGHcx9bVrbgoh4BdOsD4kH6-QqxP0SnqjSgmXqTLVUX4vIN2KsmKkbXtguJpI7SHarGu_Bxb9FwBpedkfqIQdYCMJ84U7jJehAT1_pc0xfk5x';

            // 2. URL KE END MEIN ?token=$esriToken LAGA DIYA HAI 👇
            source['tiles'] = [
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}?token=$esriToken'
            ];
            source.remove('url');
            source['tileSize'] = 256;
            continue; // Skip the Ola API key injection for this specific source
          }

          if (source['url'] != null) {
            String tileJsonUrl = source['url'].toString();
            if (tileJsonUrl.contains('?key=')) {
              tileJsonUrl = tileJsonUrl.split('?key=')[0];
            }
            if (!tileJsonUrl.contains('api_key=')) {
              tileJsonUrl =
                  '$tileJsonUrl${tileJsonUrl.contains('?') ? '&' : '?'}api_key=$apiKey';
            }

            final tileJsonResponse = await http.get(Uri.parse(tileJsonUrl));
            if (tileJsonResponse.statusCode == 200) {
              Map<String, dynamic> tileJson = jsonDecode(tileJsonResponse.body);

              if (tileJson['tiles'] != null) {
                List<dynamic> tiles = tileJson['tiles'];
                List<String> modifiedTiles = tiles.map((t) {
                  String tileUrl = t.toString();
                  if (tileUrl.contains('?key=')) {
                    tileUrl = tileUrl.split('?key=')[0];
                  }
                  if (!tileUrl.contains('api_key=')) {
                    return '$tileUrl${tileUrl.contains('?') ? '&' : '?'}api_key=$apiKey';
                  }
                  return tileUrl;
                }).toList();

                source.remove('url');
                source['tiles'] = modifiedTiles;
              }
            }
          }
        }
      }

      // Encode and return
      String finalJson = jsonEncode(styleJson);
      return 'data:application/json;charset=utf-8,${Uri.encodeComponent(finalJson)}';
    } catch (e) {
      debugPrint('Error flattening Ola Style: $e');
      return styleUrl; // Fallback to raw URL
    }
  }
}
