import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 🚀 NATIVE THEMES ONLY
enum MapThemeType { light, dark }

class MapStyleHelper {
  static const String _dataUriPrefix = 'data:application/json;charset=utf-8,';

  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType}) async {
    final String apiKey = dotenv.env['OLA_MAPS_API_KEY'] ?? '';

    // API Key nahi hai toh seedha fallback
    if (apiKey.isEmpty) {
      return _getFallbackStyle(isSystemDark);
    }

    final bool useDark =
        themeType != null ? (themeType == MapThemeType.dark) : isSystemDark;
    final String styleName =
        useDark ? "default-dark-standard" : "default-light-standard";

    // 🚀 CACHE KEY v310 (Fuel stations dynamic visibility support)
    final String cacheKey = "ola_v310_$styleName";

    final prefs = await SharedPreferences.getInstance();
    final String? cachedStyle = prefs.getString(cacheKey);

    if (cachedStyle != null) {
      return cachedStyle;
    }

    final String styleUrl =
        "https://api.olamaps.io/tiles/vector/v1/styles/$styleName/style.json?api_key=$apiKey";

    try {
      final response = await http
          .get(Uri.parse(styleUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return _getFallbackStyle(useDark);
      }

      Map<String, dynamic> styleData = json.decode(response.body);

      // 1. Sprites & Glyphs URL Fix
      if (styleData['sprite'] != null) {
        final String s = styleData['sprite'].toString().split('?').first;
        styleData['sprite'] = "$s?api_key=$apiKey";
      }
      if (styleData['glyphs'] != null) {
        final String g = styleData['glyphs'].toString().split('?').first;
        styleData['glyphs'] = "$g?api_key=$apiKey";
      }

      // 🚀 2. PRODUCTION-GRADE TILE SANITIZER
      if (styleData['sources'] != null && styleData['sources'] is Map) {
        final Map<String, dynamic> sources = styleData['sources'];
        sources.forEach((key, source) {
          if (source is Map) {
            // URL property hatao taaki SDK direct tiles use kare (Flicker prevention)
            if (source['url'] != null) {
              final String baseUrl = source['url']
                  .toString()
                  .split('?')
                  .first
                  .replaceAll('.json', '/{z}/{x}/{y}.pbf');

              source.remove('url');
              source['tiles'] = ["$baseUrl?api_key=$apiKey"];
              source['minzoom'] = 0;
              source['maxzoom'] = 14;
            }

            // Tiles array sanitize karo
            if (source['tiles'] != null && source['tiles'] is List) {
              final List<dynamic> tiles = source['tiles'];
              for (int i = 0; i < tiles.length; i++) {
                final String cleanTileUrl =
                    tiles[i].toString().split('?').first;
                tiles[i] = "$cleanTileUrl?api_key=$apiKey";
              }
            }
          }
        });
      }

      // 🚀 3. LAYER OPTIMIZATION + COLOR INJECTION
      if (styleData['layers'] != null && styleData['layers'] is List) {
        final List<dynamic> rawLayers = styleData['layers'];
        styleData['layers'] = rawLayers.where((layer) {
          if (layer is! Map) return true;
          final String id = layer['id']?.toString().toLowerCase() ?? '';
          final String sourceLayer =
              layer['source-layer']?.toString().toLowerCase() ?? '';
          final String type = layer['type']?.toString().toLowerCase() ?? '';

          // 1. Remove 3D Models
          if (id.contains('3d_model') || sourceLayer.contains('3d_model')) {
            return false;
          }

          // 2. PREMIUM PERMANENT DECLUTTERING
          
          // RULE B (Keep Roads & Places): Core geography and roads are sacred
          bool isEssential = id.contains('road') || id.contains('street') || 
                             id.contains('place') || id.contains('city') || 
                             id.contains('state') || id.contains('country') || 
                             id.contains('neighborhood');

          if (!isEssential) {
            // EXEMPTION: Fuel stations remain in the JSON but are hidden by default
            bool isFuel = id.contains('fuel') || id.contains('gas') || id.contains('petrol') || 
                          id.contains('gas_station') || sourceLayer.contains('fuel') || 
                          sourceLayer.contains('gas') || sourceLayer.contains('petrol');
            
            if (isFuel) {
              if (!layer.containsKey('layout') || layer['layout'] is! Map) {
                layer['layout'] = <String, dynamic>{};
              }
              layer['layout']['visibility'] = 'none';
            } else {
              // RULE A (Kill Commercial POIs): Remove all businesses, food, ATMs, etc.
              bool isClutter = id.contains('poi') || id.contains('shop') || 
                               id.contains('food') || id.contains('restaurant') || 
                               id.contains('amenity') || id.contains('commercial') || 
                               id.contains('atm') || id.contains('business') ||
                               sourceLayer.contains('poi') || sourceLayer.contains('shop') || 
                               sourceLayer.contains('food') || sourceLayer.contains('restaurant') || 
                               sourceLayer.contains('amenity') || sourceLayer.contains('commercial') || 
                               sourceLayer.contains('atm') || sourceLayer.contains('business');
              
              if (isClutter) {
                return false; // Remove layer completely
              }
            }
          }

          // RULE C (Metro/Transit - Icons Only, No Text): Clean up transit stations
          bool isTransit = id.contains('transit') || id.contains('station') || 
                           id.contains('railway') || id.contains('subway') || 
                           id.contains('metro');
          
          if (isTransit && type == 'symbol') {
            if (layer.containsKey('layout') && layer['layout'] is Map) {
              final Map<String, dynamic> layout = layer['layout'];
              // Delete the text-field so only the icon renders
              layout.remove('text-field');
            }
          }

          // 🚀 3. APPLE-GRADE COLOR INJECTION
          if (layer.containsKey('paint') && layer['paint'] is Map) {
            final Map<String, dynamic> paint = layer['paint'];

            if (useDark) {
              // 1. Land / Background (Deep Base)
              if (type == 'background') {
                paint['background-color'] = '#181A1F';
              } else if ((id.contains('landuse') || id.contains('building')) &&
                  type == 'fill') {
                paint['fill-color'] = '#1E2128';
              }
              // 2. Water Bodies & Parks (Subtle & Muted)
              else if (id.contains('water') && type == 'fill') {
                paint['fill-color'] = '#14202A';
              } else if ((id.contains('park') || id.contains('green')) &&
                  type == 'fill') {
                paint['fill-color'] = '#1A2421';
              }
              // 3. Roads (Clear Navigation Paths)
              else if ((id.contains('road') || sourceLayer.contains('road')) &&
                  type == 'line') {
                if (paint.containsKey('line-color')) {
                  if (id.contains('highway') ||
                      id.contains('primary') ||
                      id.contains('trunk')) {
                    paint['line-color'] = '#3A404A'; // Major roads
                  } else {
                    paint['line-color'] = '#2D323A'; // Regular roads
                  }
                }
              }
              // 4. Transit Lines (Base Network)
              else if ((id.contains('railway') || id.contains('transit')) &&
                  type == 'line') {
                if (paint.containsKey('line-color')) {
                  paint['line-color'] = '#454C59';
                }
              }
            } else {
              // ==========================================
              // ☀️ LIGHT MODE (High-Contrast Premium)
              // ==========================================
              
              // 1. Land / Background (Deepen the Base for Contrast)
              if (type == 'background') {
                paint['background-color'] = '#E0E4E8'; // Distinctly visible cool grey
              } else if ((id.contains('landuse') || id.contains('building')) &&
                  type == 'fill') {
                paint['fill-color'] = '#D4D9DF'; // Slightly darker grey for buildings
              }
              // 2. Water Bodies & Parks (Vibrant but Elegant)
              else if (id.contains('water') && type == 'fill') {
                paint['fill-color'] = '#96C1E3'; // Clear, recognizable sky blue
              } else if ((id.contains('park') || id.contains('green')) &&
                  type == 'fill') {
                paint['fill-color'] = '#B7D9BA'; // Fresh, clear pastel green
              }
              // 3. Roads & Streets (Maximum Pop)
              else if ((id.contains('road') || sourceLayer.contains('road')) &&
                  type == 'line') {
                if (paint.containsKey('line-color')) {
                  paint['line-color'] = '#FFFFFF'; // Pure white makes roads pop out
                }
              }
              // 4. Transit Lines (Sharp Visibility)
              else if ((id.contains('railway') || id.contains('transit')) &&
                  type == 'line') {
                if (paint.containsKey('line-color')) {
                  paint['line-color'] = '#4F5D73'; // Sharp slate grey
                }
              }
            }
          }

          // 🚀 4. NULL-COLOR SANITIZER — Prevents "Could not parse color from value 'null'" crash
          // Some layers from the Ola Maps API have null paint/layout values that crash MapLibre.
          if (layer.containsKey('paint') && layer['paint'] is Map) {
            final Map<String, dynamic> paint = layer['paint'];
            paint.removeWhere((key, value) => value == null);
          }
          if (layer.containsKey('layout') && layer['layout'] is Map) {
            final Map<String, dynamic> layout = layer['layout'];
            layout.removeWhere((key, value) => value == null);
          }

          return true; // Baki render hoga
        }).toList();
      }

      final String finalStyle = json.encode(styleData);

      // ✅ FIXED: String Interpolation applied (Warning #1)
      final String outputStyle = kIsWeb
          ? "$_dataUriPrefix${Uri.encodeComponent(finalStyle)}"
          : finalStyle;

      await prefs.setString(cacheKey, outputStyle);
      return outputStyle;
    } catch (e) {
      debugPrint("❌ Map Production Style Error: $e");
      return _getFallbackStyle(useDark);
    }
  }

  static String _getFallbackStyle(bool isDark) {
    final tileUrl = isDark
        ? "https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png"
        : "https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png";

    final String style = json.encode({
      "version": 8,
      "sources": {
        "global": {
          "type": "raster",
          "tiles": [tileUrl],
          "tileSize": 256
        }
      },
      "layers": [
        {"id": "bg", "type": "raster", "source": "global", "minzoom": 0}
      ]
    });

    // ✅ FIXED: String Interpolation applied (Warning #2)
    return kIsWeb ? "$_dataUriPrefix${Uri.encodeComponent(style)}" : style;
  }
}
