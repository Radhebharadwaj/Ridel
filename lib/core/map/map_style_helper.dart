import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

// 🚀 NATIVE THEMES ONLY
enum MapThemeType { light, dark, satellite }

class MapStyleHelper {
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
          "maxzoom": 19
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
    return 'data:application/json;charset=utf-8,${Uri.encodeComponent(jsonEncode(fallbackStyle))}';
  }

  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType,
      bool showPOIs = true,
      bool show3D = false}) async {
    final apiKey = AppConfig.olaMapsKey;

    // 1. FALLBACK: Invalid or missing API keys
    if (apiKey.trim().isEmpty || apiKey == "2") {
      debugPrint(
          "NETWORK FAILURE: Ola Key Missing or Invalid. Rendering Fallback.");
      return _getEsriFallbackStyle();
    }

    final MapThemeType resolvedTheme =
        themeType ?? (isSystemDark ? MapThemeType.dark : MapThemeType.light);

    // Base Ola style is always light or dark (Satellite uses dark as a base)
    String styleId = 'default-light-standard';
    if (resolvedTheme == MapThemeType.dark ||
        resolvedTheme == MapThemeType.satellite) {
      styleId = 'default-dark-standard';
    }

    final styleUrl =
        'https://api.olamaps.io/tiles/vector/v1/styles/$styleId/style.json?api_key=$apiKey';

    try {
      final response = await http
          .get(Uri.parse(styleUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return _getEsriFallbackStyle();

      Map<String, dynamic> styleData = jsonDecode(response.body);

      // 2. SPRITES & GLYPHS INJECTION
      if (styleData['glyphs'] != null) {
        styleData['glyphs'] =
            "${styleData['glyphs'].toString().split('?').first}?api_key=$apiKey";
      }
      if (styleData['sprite'] != null) {
        styleData['sprite'] =
            "${styleData['sprite'].toString().split('?').first}?api_key=$apiKey";
      }

      // 3. SOURCES MODIFICATION
      if (styleData['sources'] == null) {
        styleData['sources'] = <String, dynamic>{};
      }
      Map<String, dynamic> sources = styleData['sources'];

      // 🚀 VECTOR INTEGRITY (Kills the 900+ Tile Loop & Deep Zoom Blanking)
      final keys = sources.keys.toList();
      for (String sourceKey in keys) {
        final source = sources[sourceKey];
        if (source is Map) {
          source['maxzoom'] = 16; // STRICT Limit: Prevents deep zoom 404 loops

          if (source['type'] == 'vector' && source['url'] != null) {
            String tileJsonUrl = source['url'].toString().split('?').first;
            String pbfUrl = tileJsonUrl.replaceAll('.json', '/{z}/{x}/{y}.pbf');

            // Bypass planet.json completely and use direct tiles
            source['tiles'] = ['$pbfUrl?api_key=$apiKey'];
            source.remove('url');
          }
        }
      }

      // 🚀 SATELLITE SOURCE INJECTION (STRICTLY for Satellite Theme)
      if (resolvedTheme == MapThemeType.satellite) {
        sources['ridel-satellite'] = {
          "type": "raster",
          "tiles": [
            "https://ridel.ridel.workers.dev/api/satellite/{z}/{y}/{x}"
          ],
          "tileSize": 256,
          "maxzoom": 19
        };
      }

      // 4. LAYERS MODIFICATION
      if (styleData['layers'] != null) {
        List<dynamic> layers = styleData['layers'];

        // 🚀 SATELLITE LAYER INJECTION (At the very bottom - index 0)
        if (resolvedTheme == MapThemeType.satellite) {
          layers.insert(0, {
            "id": "ridel-satellite-base",
            "type": "raster",
            "source": "ridel-satellite"
          });
        }

        for (var layer in layers) {
          if (layer is Map) {
            layer.remove('maxzoom'); // Let visual elements stretch infinitely

            // 🚀 DEEP WEBGL SANITIZER (Kills "Missing required image id" crash)
            if (layer.containsKey('layout') && layer['layout'] is Map) {
              var layout = layer['layout'];
              if (layout.containsKey('icon-image')) {
                var iconImg = layout['icon-image'];
                if (iconImg is String) {
                  if (iconImg.trim().isEmpty ||
                      iconImg == "pedestrian_polygon") {
                    layout.remove('icon-image');
                  }
                } else if (iconImg is List) {
                  // Ola hides empty strings in expressions
                  String expStr = iconImg.toString();
                  if (expStr.contains('""') ||
                      expStr.contains("''") ||
                      expStr.contains("pedestrian_polygon")) {
                    layout.remove('icon-image');
                  }
                }
              }
            }

            // 🚀 SATELLITE TRANSPARENCY (Strictly typed to prevent WebGL aborts)
            if (resolvedTheme == MapThemeType.satellite) {
              if (layer['paint'] == null) layer['paint'] = <String, dynamic>{};

              if (layer['type'] == 'fill') {
                layer['paint']['fill-opacity'] = 0.0;
                layer['paint'].remove('fill-extrusion-opacity');
              } else if (layer['type'] == 'fill-extrusion') {
                layer['paint']['fill-extrusion-opacity'] = 0.0;
                layer['paint'].remove('fill-opacity');
              } else if (layer['type'] == 'background') {
                layer['paint']['background-color'] = 'rgba(0,0,0,0)';
                layer['paint']['background-opacity'] = 0.0;
              }
            }
          }
        }
      }

      return 'data:application/json;charset=utf-8,${Uri.encodeComponent(jsonEncode(styleData))}';
    } catch (e) {
      debugPrint("STYLE FETCH/PARSE ERROR: $e");
      return _getEsriFallbackStyle();
    }
  }
}
