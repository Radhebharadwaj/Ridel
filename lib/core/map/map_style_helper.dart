import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridel/core/config/app_config.dart';

// 🚀 NATIVE THEMES ONLY
enum MapThemeType { light, dark, satellite }

class MapStyleHelper {
  static const String _dataUriPrefix = 'data:application/json;charset=utf-8,';

  static String _mutateLayerVisibilities(String jsonString, {required bool showLabels, required bool showPOIs}) {
    try {
      Map<String, dynamic> styleMap = json.decode(jsonString);
      List<dynamic> layers = styleMap['layers'] as List<dynamic>? ?? [];
      
      for (var layer in layers) {
        if (layer is Map<String, dynamic>) {
          final String type = (layer['type'] ?? '').toString().toLowerCase();
          
          if (type == 'symbol') {
            final String id = (layer['id'] ?? '').toString().toLowerCase();
            final String sourceLayer = (layer['source-layer'] ?? '').toString().toLowerCase();
            
            layer['layout'] = layer['layout'] ?? <String, dynamic>{};
            
            // TIER 1: NAVIGATION & TRANSIT ESSENTIALS -> LABELS BUCKET
            // Exactly captures bus stops, metro/train stations, airports, and red/green/yellow traffic signals
            final bool isNavEssential = id.contains('transit') || sourceLayer.contains('transit') || 
                                        id.contains('bus') || id.contains('station') || 
                                        id.contains('metro') || id.contains('subway') || 
                                        id.contains('train') || id.contains('railway') || 
                                        id.contains('aeroway') || id.contains('airport') || 
                                        id.contains('traffic_signal') || id.contains('signal') || 
                                        id.contains('traffic-light') || id.contains('stop_sign') || 
                                        id.contains('yield');
            
            // TIER 2: COMMERCIAL & AMENITY POIS -> POIS BUCKET
            // Strictly commercial, dining, retail, hospitality, medical, and entertainment venues
            final bool isCommercialPoi = id.contains('poi') || sourceLayer.contains('poi') || 
                                         id.contains('shop') || id.contains('amenity') || 
                                         id.contains('landmark') || id.contains('business') || 
                                         id.contains('restaurant') || id.contains('food') || 
                                         id.contains('hotel') || id.contains('hospital') || 
                                         id.contains('commercial') || id.contains('retail') || 
                                         id.contains('entertainment') || id.contains('leisure') || 
                                         id.contains('tourism') || id.contains('fuel') || 
                                         id.contains('bank') || id.contains('atm') || 
                                         id.contains('attraction') || id.contains('icon') || 
                                         id.contains('marker');
            
            if (isNavEssential) {
              layer['layout']['visibility'] = showLabels ? 'visible' : 'none';
            } else if (isCommercialPoi) {
              layer['layout']['visibility'] = showPOIs ? 'visible' : 'none';
            } else {
              // TIER 3: CATCH-ALL -> LABELS BUCKET (Street names, typography, area labels)
              layer['layout']['visibility'] = showLabels ? 'visible' : 'none';
            }
          }
        }
      }
      return json.encode(styleMap);
    } catch (e) {
      debugPrint("❌ CRITICAL FAILURE IN LAYER MUTATION: $e");
      return jsonString;
    }
  }

  static Future<String> _getBaseStyleSource(bool useDark, String cacheKey, SharedPreferences prefs) async {
    final String? cachedStyle = prefs.getString(cacheKey);
    if (cachedStyle != null) {
      // Decode cached data URI if necessary
      if (cachedStyle.startsWith(_dataUriPrefix)) {
        return Uri.decodeComponent(cachedStyle.substring(_dataUriPrefix.length));
      }
      return cachedStyle;
    }

    final String apiKey = AppConfig.olaMapsKey;
    if (apiKey.isEmpty) {
      debugPrint('CRITICAL: Ola API Key is missing');
      throw Exception('CRITICAL: Ola API Key is missing');
    }

    final String styleName = useDark ? "default-dark-standard" : "default-light-standard";
    final String styleUrl = "https://api.olamaps.io/tiles/vector/v1/styles/$styleName/style.json?api_key=$apiKey";

    final response = await http.get(Uri.parse(styleUrl)).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception("Ola Maps API failed with status ${response.statusCode}: ${response.body}");
    }

    Map<String, dynamic> styleData = json.decode(response.body);

    void removeNulls(dynamic node) {
      if (node is Map) {
        node.removeWhere((key, value) => value == null || value == "null");
        for (var value in node.values) {
          removeNulls(value);
        }
      } else if (node is List) {
        for (var item in node) {
          removeNulls(item);
        }
      }
    }
    
    removeNulls(styleData);

    if (styleData['sprite'] != null) {
      final String s = "${styleData['sprite'].toString().split('?').first}?api_key=$apiKey";
      styleData['sprite'] = s;
    }
    if (styleData['glyphs'] != null) {
      final String g = "${styleData['glyphs'].toString().split('?').first}?api_key=$apiKey";
      styleData['glyphs'] = g;
    }

    if (styleData['sources'] != null && styleData['sources'] is Map) {
      final Map<String, dynamic> sources = styleData['sources'];
      sources.forEach((key, source) {
        if (source is Map) {
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

    if (styleData['layers'] != null && styleData['layers'] is List) {
      final List<dynamic> rawLayers = styleData['layers'];
      styleData['layers'] = rawLayers.expand((layer) {
        if (layer is! Map) return [layer];
        final String id = layer['id']?.toString().toLowerCase() ?? '';
        final String sourceLayer = layer['source-layer']?.toString().toLowerCase() ?? '';
        final String type = layer['type']?.toString().toLowerCase() ?? '';

        if (id.contains('3d_model') || sourceLayer.contains('3d_model')) {
          return [];
        }

        bool isTransit = id.contains('transit') || id.contains('station') || id.contains('railway') || id.contains('subway') || id.contains('metro');
        if (isTransit && type == 'symbol') {
          if (layer.containsKey('layout') && layer['layout'] is Map) {
            final Map<String, dynamic> layout = layer['layout'];
            layout.remove('text-field');
          }
        }

        // SILKY-SMOOTH CURVES: Force round joins & caps on EVERY line layer (zero sharp corners)
        if (type == 'line') {
          if (!layer.containsKey('layout') || layer['layout'] is! Map) {
            layer['layout'] = <String, dynamic>{};
          }
          layer['layout']['line-join'] = 'round';
          layer['layout']['line-cap'] = 'round';
          layer['layout']['line-round-limit'] = 1.05;
        }

        if (layer.containsKey('paint') && layer['paint'] is Map) {
          final Map<String, dynamic> paint = layer['paint'];
          final bool isCasing = id.contains('casing');
          final bool isRoad = id.contains('road') ||
              id.contains('street') ||
              id.contains('highway') ||
              id.contains('motorway') ||
              id.contains('trunk') ||
              id.contains('primary') ||
              id.contains('secondary') ||
              id.contains('tertiary') ||
              id.contains('bridge') ||
              id.contains('tunnel') ||
              sourceLayer.contains('transportation') ||
              sourceLayer.contains('road');

          if (useDark) {
            if (type == 'background') {
              paint['background-color'] = '#0E1117';
            } else if (type == 'fill-extrusion') {
              paint['fill-extrusion-color'] = '#1A202D';
              paint['fill-extrusion-opacity'] = 0.90;
            } else if (id.contains('water') && type == 'fill') {
              paint['fill-color'] = '#0A192D';
            } else if ((id.contains('park') || id.contains('green') || id.contains('wood') || id.contains('grass')) && type == 'fill') {
              paint['fill-color'] = '#122620';
            } else if ((id.contains('landuse') || id.contains('building')) && type == 'fill') {
              paint['fill-color'] = id.contains('building') ? '#1A202D' : '#141821';
            } else if (id.contains('waterway') && type == 'line') {
              paint['line-color'] = '#102540';
            } else if ((id.contains('railway') || id.contains('transit')) && type == 'line') {
              if (paint.containsKey('line-color') && !id.contains('metro') && !id.contains('monorail')) {
                paint['line-color'] = '#424E66';
              }
            } else if (isRoad && type == 'line' && paint.containsKey('line-color')) {
              if (id.contains('motorway')) {
                paint['line-color'] = isCasing ? '#2C2216' : '#6E5535';
              } else if (id.contains('highway') || id.contains('trunk') || id.contains('primary')) {
                paint['line-color'] = isCasing ? '#1A212E' : '#3C4961';
              } else if (id.contains('secondary') || id.contains('tertiary')) {
                paint['line-color'] = isCasing ? '#131822' : '#2C3547';
              } else {
                paint['line-color'] = isCasing ? '#12161F' : '#212836';
              }
            } else if (type == 'symbol' && paint.containsKey('text-color')) {
              paint['text-halo-color'] = 'rgba(11, 14, 20, 0.90)';
              paint['text-halo-width'] = 1.6;
              paint['text-halo-blur'] = 0.7;
            }
          } else {
            if (type == 'background') {
              paint['background-color'] = '#F3F4F6';
            } else if (type == 'fill-extrusion') {
              paint['fill-extrusion-color'] = '#E3E6EE';
              paint['fill-extrusion-opacity'] = 0.88;
            } else if (id.contains('water') && type == 'fill') {
              paint['fill-color'] = '#A6D4F7';
            } else if ((id.contains('park') || id.contains('green') || id.contains('wood') || id.contains('grass')) && type == 'fill') {
              paint['fill-color'] = '#CBE8C6';
            } else if ((id.contains('landuse') || id.contains('building')) && type == 'fill') {
              paint['fill-color'] = id.contains('building') ? '#E3E6EE' : '#ECEEF2';
            } else if (id.contains('waterway') && type == 'line') {
              paint['line-color'] = '#95C9F0';
            } else if ((id.contains('railway') || id.contains('transit')) && type == 'line') {
              if (paint.containsKey('line-color') && !id.contains('metro') && !id.contains('monorail')) {
                paint['line-color'] = '#A2ADBF';
              }
            } else if (isRoad && type == 'line' && paint.containsKey('line-color')) {
              if (id.contains('motorway')) {
                paint['line-color'] = isCasing ? '#D99A32' : '#FBD277';
              } else if (id.contains('highway') || id.contains('trunk') || id.contains('primary')) {
                paint['line-color'] = isCasing ? '#DBB65C' : '#FEE7AC';
              } else if (id.contains('secondary') || id.contains('tertiary')) {
                paint['line-color'] = isCasing ? '#CFD5DF' : '#FFFFFF';
              } else {
                paint['line-color'] = isCasing ? '#D8DDE6' : '#FFFFFF';
              }
            } else if (type == 'symbol' && paint.containsKey('text-color')) {
              paint['text-halo-color'] = 'rgba(255, 255, 255, 0.92)';
              paint['text-halo-width'] = 1.5;
              paint['text-halo-blur'] = 0.6;
            }
          }
        }

        Map<String, dynamic>? glowCasingLayer;

        // TARGET TRANSIT, METRO & RAILWAY LINES
        final bool isTransitLine = type == 'line' && (
          id.contains('transit') || sourceLayer.contains('transit') || 
          id.contains('metro') || sourceLayer.contains('metro') || 
          id.contains('subway') || sourceLayer.contains('subway') || 
          id.contains('rail') || sourceLayer.contains('rail') || 
          id.contains('train') || id.contains('light_rail') || 
          id.contains('monorail') || id.contains('tram')
        );

        if (isTransitLine && !id.endsWith('-glow-casing')) {
          layer['paint'] = layer['paint'] ?? <String, dynamic>{};
          layer['layout'] = layer['layout'] ?? <String, dynamic>{};
          
          // 1. THE LASER CORE (Ultra-Slim, Sharp & High-Contrast)
          layer['layout']['line-cap'] = 'round';
          layer['layout']['line-join'] = 'round';
          
          // Sleek, refined electronic micro-dashes
          layer['paint']['line-dasharray'] = [1.2, 1.5]; 
          
          // CRITICAL: Make the core line ultra-thin and razor-sharp
          layer['paint']['line-width'] = <String, dynamic>{
            "base": 1.2,
            "stops": [ 
              [10, 0.8],  // Razor thin at city level
              [14, 1.4],  // Sleek at street zoom
              [18, 2.2]   // Elegant at close-up
            ]
          };
          // Pure laser intensity in Dark Mode
          layer['paint']['line-opacity'] = useDark ? 0.95 : 0.90;

          // 2. THE AMBIENT HALO GLOW (Wide, Diffused & Soft)
          glowCasingLayer = json.decode(json.encode(layer)); // Deep copy
          glowCasingLayer!['id'] = '${layer['id']}-glow-casing';
          
          // Remove dashes from casing to create a continuous ambient light aura
          glowCasingLayer['paint'].remove('line-dasharray'); 
          
          // Make the halo 3x-4x wider than the laser core
          glowCasingLayer['paint']['line-width'] = <String, dynamic>{
            "base": 1.2,
            "stops": [ 
              [10, 2.8], 
              [14, 5.0], 
              [18, 8.5] 
            ]
          };
          
          // Lower opacity and high blur create a genuine "fire/laser glow" emission effect
          glowCasingLayer['paint']['line-opacity'] = useDark ? 0.22 : 0.12;
          glowCasingLayer['paint']['line-blur'] = 2.5; // High diffusion spreads the color softly onto roads
        }

        if (type == 'symbol') {
          if (!layer.containsKey('layout') || layer['layout'] is! Map) {
            layer['layout'] = <String, dynamic>{};
          }
          layer['layout']['icon-optional'] = true;
          layer['layout']['text-optional'] = true;
        }

        return glowCasingLayer != null ? [glowCasingLayer, layer] : [layer];
      }).toList();
    }

    final String finalStyle = json.encode(styleData);
    await prefs.setString(cacheKey, finalStyle);
    return finalStyle;
  }

  static Future<String> getOlaStyle(bool isSystemDark,
      {MapThemeType? themeType,
      bool showLabels = true,
      bool showPOIs = true}) async {
    if (themeType == MapThemeType.satellite) {
      const String satelliteStyle = '''
      {
        "version": 8,
        "sources": {
          "satellite-raster": {
            "type": "raster",
            "tiles": [
              "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
            ],
            "tileSize": 256
          }
        },
        "layers": [
          {
            "id": "satellite-base",
            "type": "raster",
            "source": "satellite-raster",
            "minzoom": 0,
            "maxzoom": 22
          }
        ]
      }
      ''';
      return kIsWeb ? "$_dataUriPrefix${Uri.encodeComponent(satelliteStyle)}" : satelliteStyle;
    }

    final bool useDark = themeType != null ? (themeType == MapThemeType.dark) : isSystemDark;
    final String styleName = useDark ? "default-dark-standard" : "default-light-standard";
    final String cacheKey = "ola_v400_appleplus_$styleName";

    final prefs = await SharedPreferences.getInstance();
    
    // 1. Get Base Style (raw JSON string)
    String rawJsonString = await _getBaseStyleSource(useDark, cacheKey, prefs);

    // 2. Mutate layers
    String mutatedJsonString = _mutateLayerVisibilities(rawJsonString, showLabels: showLabels, showPOIs: showPOIs);

    // 3. Return format
    return kIsWeb ? "$_dataUriPrefix${Uri.encodeComponent(mutatedJsonString)}" : mutatedJsonString;
  }
}
