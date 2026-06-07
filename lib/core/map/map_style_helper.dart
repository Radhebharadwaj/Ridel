import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridel/core/config/app_config.dart';
// 🚀 NATIVE THEMES ONLY
enum MapThemeType { light, dark }

class MapStyleHelper {
  static const String _dataUriPrefix = 'data:application/json;charset=utf-8,';

  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType}) async {

    final bool useDark =
        themeType != null ? (themeType == MapThemeType.dark) : isSystemDark;
    final String styleName =
        useDark ? "default-dark-standard" : "default-light-standard";

    // 🚀 CACHE KEY v311 (Direct Ola URL enforcement)
    final String cacheKey = "ola_v311_$styleName";

    final prefs = await SharedPreferences.getInstance();
    final String? cachedStyle = prefs.getString(cacheKey);

    if (cachedStyle != null) {
      return cachedStyle;
    }

    final String apiKey = AppConfig.olaMapsKey;
    if (apiKey.isEmpty) {
      debugPrint('CRITICAL: Ola API Key is missing');
      throw Exception('CRITICAL: Ola API Key is missing');
    }
    
    final String styleUrl =
        "https://api.olamaps.io/tiles/vector/v1/styles/$styleName/style.json?api_key=$apiKey";

    final response = await http
        .get(Uri.parse(styleUrl))
        .timeout(const Duration(seconds: 15));
    
    if (response.statusCode != 200) {
      throw Exception("Ola Maps API failed with status ${response.statusCode}: ${response.body}");
    }

    Map<String, dynamic> styleData = json.decode(response.body);

    // 1. Sprites & Glyphs URL Fix (Direct to Ola Maps with API Key)
    if (styleData['sprite'] != null) {
      final String s = "${styleData['sprite'].toString().split('?').first}?api_key=$apiKey";
      styleData['sprite'] = s;
    }
    if (styleData['glyphs'] != null) {
      final String g = "${styleData['glyphs'].toString().split('?').first}?api_key=$apiKey";
      styleData['glyphs'] = g;
    }

    // 🚀 2. PRODUCTION-GRADE TILE SANITIZER
    if (styleData['sources'] != null && styleData['sources'] is Map) {
      final Map<String, dynamic> sources = styleData['sources'];
      sources.forEach((key, source) {
        if (source is Map) {
          // Change vector source JSON URL to direct PBF tiles to prevent flicker
          if (source['url'] != null) {
            final String baseUrl = "${source['url'].toString().split('?').first.replaceAll('.json', '/{z}/{x}/{y}.pbf')}?api_key=$apiKey";

            source.remove('url');
            source['tiles'] = [baseUrl];
            source['minzoom'] = 0;
            source['maxzoom'] = 14;
          }

          if (source['tiles'] != null && source['tiles'] is List) {
            final List<dynamic> tiles = source['tiles'];
            for (int i = 0; i < tiles.length; i++) {
              tiles[i] = "${tiles[i].toString().split('?').first}?api_key=$apiKey";
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
        bool isEssential = id.contains('road') ||
            id.contains('street') ||
            id.contains('place') ||
            id.contains('city') ||
            id.contains('state') ||
            id.contains('country') ||
            id.contains('neighborhood');

        if (!isEssential) {
          bool isFuel = id.contains('fuel') ||
              id.contains('gas') ||
              id.contains('petrol') ||
              id.contains('gas_station') ||
              sourceLayer.contains('fuel') ||
              sourceLayer.contains('gas') ||
              sourceLayer.contains('petrol');

          if (isFuel) {
            if (!layer.containsKey('layout') || layer['layout'] is! Map) {
              layer['layout'] = <String, dynamic>{};
            }
            layer['layout']['visibility'] = 'none';
          } else {
            bool isClutter = id.contains('poi') ||
                id.contains('shop') ||
                id.contains('food') ||
                id.contains('restaurant') ||
                id.contains('amenity') ||
                id.contains('commercial') ||
                id.contains('atm') ||
                id.contains('business') ||
                sourceLayer.contains('poi') ||
                sourceLayer.contains('shop') ||
                sourceLayer.contains('food') ||
                sourceLayer.contains('restaurant') ||
                sourceLayer.contains('amenity') ||
                sourceLayer.contains('commercial') ||
                sourceLayer.contains('atm') ||
                sourceLayer.contains('business');

            if (isClutter) {
              return false; // Remove layer completely
            }
          }
        }

        // RULE C (Metro/Transit - Icons Only, No Text): Clean up transit stations
        bool isTransit = id.contains('transit') ||
            id.contains('station') ||
            id.contains('railway') ||
            id.contains('subway') ||
            id.contains('metro');

        if (isTransit && type == 'symbol') {
          if (layer.containsKey('layout') && layer['layout'] is Map) {
            final Map<String, dynamic> layout = layer['layout'];
            layout.remove('text-field');
          }
        }

        // 🚀 3. APPLE-GRADE COLOR INJECTION
        if (layer.containsKey('paint') && layer['paint'] is Map) {
          final Map<String, dynamic> paint = layer['paint'];

          if (useDark) {
            if (type == 'background') {
              paint['background-color'] = '#181A1F';
            } else if ((id.contains('landuse') || id.contains('building')) &&
                type == 'fill') {
              paint['fill-color'] = '#1E2128';
            }
            else if (id.contains('water') && type == 'fill') {
              paint['fill-color'] = '#14202A';
            } else if ((id.contains('park') || id.contains('green')) &&
                type == 'fill') {
              paint['fill-color'] = '#1A2421';
            }
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
            else if ((id.contains('railway') || id.contains('transit')) &&
                type == 'line') {
              if (paint.containsKey('line-color')) {
                paint['line-color'] = '#454C59';
              }
            }
          } else {
            if (type == 'background') {
              paint['background-color'] =
                  '#E0E4E8'; // Distinctly visible cool grey
            } else if ((id.contains('landuse') || id.contains('building')) &&
                type == 'fill') {
              paint['fill-color'] =
                  '#D4D9DF'; // Slightly darker grey for buildings
            }
            else if (id.contains('water') && type == 'fill') {
              paint['fill-color'] = '#96C1E3'; // Clear, recognizable sky blue
            } else if ((id.contains('park') || id.contains('green')) &&
                type == 'fill') {
              paint['fill-color'] = '#B7D9BA'; // Fresh, clear pastel green
            }
            else if ((id.contains('road') || sourceLayer.contains('road')) &&
                type == 'line') {
              if (paint.containsKey('line-color')) {
                paint['line-color'] =
                    '#FFFFFF'; // Pure white makes roads pop out
              }
            }
            else if ((id.contains('railway') || id.contains('transit')) &&
                type == 'line') {
              if (paint.containsKey('line-color')) {
                paint['line-color'] = '#4F5D73'; // Sharp slate grey
              }
            }
          }
        }

        // 🚀 4. NULL-COLOR SANITIZER
        if (layer.containsKey('paint') && layer['paint'] is Map) {
          final Map<String, dynamic> paint = layer['paint'];
          paint.removeWhere((key, value) => value == null);
        }
        if (layer.containsKey('layout') && layer['layout'] is Map) {
          final Map<String, dynamic> layout = layer['layout'];
          layout.removeWhere((key, value) => value == null);
        }

        return true; 
      }).toList();
    }

    final String finalStyle = json.encode(styleData);

    final String outputStyle = kIsWeb
        ? "$_dataUriPrefix${Uri.encodeComponent(finalStyle)}"
        : finalStyle;

    await prefs.setString(cacheKey, outputStyle);
    return outputStyle;
  }
}
