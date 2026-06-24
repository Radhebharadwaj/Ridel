import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

enum MapThemeType { light, dark, satellite }

class MapStyleHelper {
  // 🚀 FALLBACK: Esri Satellite for Unauthenticated/Network Failure
  static String _getEsriFallbackStyle() {
    final fallbackStyle = {
      "version": 8,
      "name": "Ridel Network Fallback",
      "sources": {
        "esri-fallback": {
          "type": "raster",
          "tiles": [
            "https://ridel.ridel.workers.dev/api/satellite/{z}/{y}/{x}"
          ],
          "tileSize": 256,
          "maxzoom": 16 // Force overzooming for fallback too
        }
      },
      "layers": [
        {
          "id": "esri-fallback-layer",
          "type": "raster",
          "source": "esri-fallback"
        }
      ]
    };
    String encodedJson = jsonEncode(fallbackStyle);
    return 'data:application/json;charset=utf-8,${Uri.encodeComponent(encodedJson)}';
  }

  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType,
      bool showPOIs = true,
      bool show3D = false}) async {
    // Wait, kya key load hui?
    if (AppConfig.olaMapsKey.isEmpty || AppConfig.olaMapsKey == "2") {
       debugPrint("WAITING: Key not ready or invalid...");
       await Future.delayed(const Duration(seconds: 1)); // Wait, retry
    }
    
    final String apiKey = AppConfig.olaMapsKey;
    // 🔥 VALIDATION: Agar key "2" hai ya khali hai, toh mat chala
    if (apiKey.isEmpty || apiKey == "2") {
      debugPrint("CRITICAL: Invalid API Key detected: $apiKey");
      return _getEsriFallbackStyle();
    }

    final bool useDark = themeType != null
        ? (themeType == MapThemeType.dark ||
            themeType == MapThemeType.satellite)
        : isSystemDark;

    final String styleId =
        useDark ? "default-dark-standard" : "default-light-standard";
    final String styleUrl =
        "https://api.olamaps.io/tiles/vector/v1/styles/$styleId/style.json";

    // 2. Build URL manually to ensure NO "?key=" remains
    // Split on '?' to remove any previous bad query parameters
    final String cleanBaseUrl = styleUrl.split('?').first; 
    final String finalUrl = "$cleanBaseUrl?api_key=$apiKey";
    
    debugPrint("🚀 Final Map Request URL: $finalUrl");

    try {
      final response = await http.get(Uri.parse(finalUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return _getEsriFallbackStyle();

      Map<String, dynamic> styleData = json.decode(response.body);

      // 2. SPRITES & GLYPHS FIX
      if (styleData['sprite'] != null) {
        styleData['sprite'] =
            "${styleData['sprite'].toString().split('?').first}?api_key=$apiKey";
      }
      if (styleData['glyphs'] != null) {
        styleData['glyphs'] =
            "${styleData['glyphs'].toString().split('?').first}?api_key=$apiKey";
      }

      // 3. SOURCES: OVERZOOM FIX & RASTER SWAP
      if (styleData['sources'] != null && styleData['sources'] is Map) {
        final Map<String, dynamic> sources = styleData['sources'];
        sources.forEach((key, source) {
          if (source is Map) {
            // 🚀 OVERZOOM FIX: Stops 404s on deep zoom (>200m)
            source['maxzoom'] = 16;

            // Inject API Key into Vector URLs
            if (source['url'] != null) {
              String tileJsonUrl = source['url'].toString().split('?').first;
              source['url'] = '$tileJsonUrl?api_key=$apiKey';
            }

            // Crucial: Inject into all tile arrays if they exist
            if (source['tiles'] != null) {
              List tiles = source['tiles'];
              source['tiles'] = tiles.map((t) => "${t.toString().split('?').first}?api_key=$apiKey").toList();
            }

            // 🚀 CLOUDFLARE SATELLITE SWAP (Only for Satellite Theme)
            if (source['type'] == 'raster' &&
                themeType == MapThemeType.satellite) {
              source['tiles'] = [
                'https://ridel.ridel.workers.dev/api/satellite/{z}/{y}/{x}'
              ];
              source.remove('url');
            }
          }
        });
      }

      // 4. LAYERS: AESTHETICS & FATAL CRASH SANITIZER
      if (styleData['layers'] != null && styleData['layers'] is List) {
        List<dynamic> updatedLayers = [];
        List<dynamic> transitLayers = [];
        List<dynamic> symbolLayers = [];

        for (var layer in styleData['layers']) {
          if (layer is! Map) continue;

          // 🚀 FATAL CRASH SANITIZER: Remove Layer Limits & Broken Icons
          layer.remove('maxzoom'); // Fixes blanking out on deep zoom
          if (layer['layout'] != null && layer['layout'] is Map) {
            var iconImage = layer['layout']['icon-image'];
            if (iconImage is String &&
                (iconImage.trim().isEmpty ||
                    iconImage == 'pedestrian_polygon')) {
              layer['layout'].remove('icon-image'); // Kills the WebGL Crash!
            }
          }

          final String id = (layer['id'] as String? ?? '').toLowerCase();
          final String type = (layer['type'] as String? ?? '');

          // DECLUTTER: Remove 3D models and heavy POIs
          if (id.contains('3d_model')) continue;
          bool isClutter = id.contains('shop') ||
              id.contains('food') ||
              id.contains('restaurant') ||
              id.contains('atm');
          if (isClutter && type != 'symbol' && !id.contains('transit'))
            continue;

          if (layer['paint'] == null || layer['paint'] is! Map) {
            if (type == 'symbol')
              layer['paint'] = <String, dynamic>{};
            else {
              updatedLayers.add(layer);
              continue;
            }
          }

          final paint = layer['paint'] as Map<String, dynamic>;

          // 🍏 APPLE AESTHETICS INTEGRATION
          if (type == 'background') {
            paint['background-color'] = useDark ? '#202A37' : '#EFEFF4';
          } else if (type == 'fill') {
            if (id.contains('water') ||
                id.contains('ocean') ||
                id.contains('river')) {
              paint['fill-color'] = useDark ? '#171F2C' : '#A2C0D4';
            } else if (id.contains('park') ||
                id.contains('forest') ||
                id.contains('grass')) {
              paint['fill-color'] = useDark ? '#17332E' : '#BCE2B9';
              paint['fill-opacity'] = useDark ? 0.90 : 0.55;
            } else if (id.contains('building')) {
              paint['fill-color'] = useDark ? '#334152' : '#E5E5EA';
              paint['fill-opacity'] = useDark ? 1.0 : 0.85;
              paint['fill-outline-color'] = useDark ? '#1D2633' : '#D1D1D6';
            } else if (id.contains('highway') || id.contains('road')) {
              paint['fill-color'] = useDark ? '#2A3646' : '#FFFFFF';
            } else {
              paint['fill-color'] = useDark ? '#202A37' : '#EFEFF4';
            }
          } else if (type == 'line') {
            // METRO LINES (Strict Colors)
            if (id.contains('metro') ||
                id.contains('subway') ||
                id.contains('transit')) {
              paint['line-color'] = [
                "match", ["get", "color"],
                "#FFDF00", useDark ? "#FFD60A" : "#FFCC00",
                "#1e90ff", useDark ? "#0A84FF" : "#007AFF",
                "#ff0000", useDark ? "#FF453A" : "#FF3B30",
                "#009933", useDark ? "#32D74B" : "#34C759",
                "#e542de", useDark ? "#BF5AF2" : "#AF52DE",
                "#FC8EAC", useDark ? "#FF375F" : "#FF2D55",
                "orange", useDark ? "#FF9F0A" : "#FF9500",
                "#999999" // fallback
              ];
              paint['line-opacity'] = 1.0;
              paint['line-width'] = 2.0;
              paint.remove('line-blur');
              transitLayers.add(layer);
              continue;
            } else if (id.contains('casing') || id.contains('outline')) {
              paint['line-color'] = useDark ? '#12151C' : '#C7C7CC';
              paint['line-width'] = [
                "interpolate",
                ["linear"],
                ["zoom"],
                14,
                2.5,
                18,
                10.0
              ];
            } else if (id.contains('highway') || id.contains('motorway')) {
              paint['line-color'] = useDark ? '#161E28' : '#FFFFFF';
              paint['line-width'] = [
                "interpolate",
                ["linear"],
                ["zoom"],
                12,
                3.0,
                18,
                14.0
              ];
            } else if (id.contains('road') || id.contains('street')) {
              paint['line-color'] = useDark ? '#2A3646' : '#FFFFFF';
              paint['line-width'] = [
                "interpolate",
                ["linear"],
                ["zoom"],
                14,
                1.5,
                18,
                8.0
              ];
            } else {
              paint['line-opacity'] = 0.15;
            }
          } else if (type == 'symbol') {
            if (layer['layout'] == null) layer['layout'] = <String, dynamic>{};

            bool isEssential = id.contains('road') ||
                id.contains('street') ||
                id.contains('city') ||
                id.contains('transit') ||
                id.contains('station');
            layer['layout']['visibility'] =
                (isEssential || showPOIs) ? 'visible' : 'none';

            layer['layout']['text-allow-overlap'] = false;
            layer['layout']['icon-allow-overlap'] = false;
            layer['layout']['symbol-spacing'] = 300;

            paint['text-color'] = useDark ? '#E0E6ED' : '#1C1C1E';
            paint['text-halo-color'] = useDark ? '#202A37' : '#FFFFFF';
            paint['text-halo-width'] = 2.0;
            paint['icon-opacity'] = useDark ? 0.65 : 0.70;

            symbolLayers.add(layer);
            continue;
          }

          updatedLayers.add(layer);
        }

        updatedLayers.addAll(transitLayers);
        updatedLayers.addAll(symbolLayers);
        styleData['layers'] = updatedLayers;
      }

      String finalStyleString = json.encode(styleData);

      return kIsWeb
          ? "data:application/json;charset=utf-8,${Uri.encodeComponent(finalStyleString)}"
          : finalStyleString;
    } catch (e) {
      debugPrint("STYLE FETCH ERROR: $e");
      return _getEsriFallbackStyle();
    }
  }
}
