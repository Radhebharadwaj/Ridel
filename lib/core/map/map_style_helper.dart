import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MapStyleHelper {
  static const String olaApiKey = "LXLK4nwQMwacpTZhol7QHc3RPet3tUOkb76reivs";
  static const Duration _cacheTTL = Duration(hours: 1);

  static Future<String> getOlaStyle(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();

    // 🚀 BUMPED TO V32: Restores ALL missing pins and fixes vectordata 404s!
    final String cacheKey = isDark ? "ola_style_dark_v32" : "ola_style_light_v32";
    final String timestampKey = "${cacheKey}_timestamp";

    final String? cachedStyle = prefs.getString(cacheKey);
    final int? cachedTimestamp = prefs.getInt(timestampKey);
    if (cachedStyle != null && cachedTimestamp != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(cachedTimestamp)) < _cacheTTL) {
      return cachedStyle;
    }

    final String styleName = isDark ? "default-dark-standard" : "default-light-standard";
    final String styleUrl = "https://api.olamaps.io/tiles/vector/v1/styles/$styleName/style.json?api_key=$olaApiKey";

    try {
      final response = await http.get(Uri.parse(styleUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        Map<String, dynamic> styleData = json.decode(response.body);

        _nukeCorruptedOlaLayers(styleData);          
        _secureAllUrls(styleData, olaApiKey);        
        _applyAppleMapsAesthetic(styleData);         // Safe declutter
        _cleanBrokenIcons(styleData);                // Safe icon filter
        _inject3DBuildings(styleData, isDark);       

        String finalStyle = json.encode(styleData);
        await prefs.setString(cacheKey, finalStyle);
        await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
        return finalStyle;
      }
    } catch (_) {}
    return cachedStyle ?? "{}";
  }

  static void _nukeCorruptedOlaLayers(Map<String, dynamic> styleData) {
    if (styleData['layers'] == null) return;
    styleData['layers'].removeWhere((layer) {
      String sourceLayer = layer['source-layer']?.toString() ?? '';
      String id = layer['id']?.toString() ?? '';
      return sourceLayer.contains('3d_model') || id.contains('3d_model');
    });
  }

  // 🛑 FIX: Explicitly set vectordata maxzoom to 12 to stop AJAX 404 errors
  static void _secureAllUrls(Map<String, dynamic> styleData, String apiKey) {
    if (styleData['sources'] != null) {
      Map<String, dynamic> sources = styleData['sources'];
      for (var key in sources.keys) {
        var source = sources[key];
        String sourceUrl = source['url']?.toString() ?? '';

        if (key == 'planet' || sourceUrl.contains('planet')) {
          source['tiles'] = ["https://api.olamaps.io/tiles/vector/v1/data/planet/{z}/{x}/{y}.pbf?api_key=$apiKey"];
          source.remove('url');
          source['maxzoom'] = 14; // Planet data is safe up to 14
        } else if (key == 'vectordata' || sourceUrl.contains('vectordata')) {
          source['tiles'] = ["https://api.olamaps.io/tiles/vector/v1/data/vectordata/{z}/{x}/{y}.pbf?api_key=$apiKey"];
          source.remove('url');
          source['maxzoom'] = 12; // 🛑 STRICT 12: Kills the Red 404 spam in console!
        } else if (sourceUrl.isNotEmpty) {
          source['url'] = _forceApiKey(sourceUrl, apiKey);
        }
      }
    }
    if (styleData['sprite'] != null) styleData['sprite'] = _forceApiKey(styleData['sprite'].toString(), apiKey);
    if (styleData['glyphs'] != null) styleData['glyphs'] = _forceApiKey(styleData['glyphs'].toString(), apiKey);
  }

  static String _forceApiKey(String originalUrl, String apiKey) {
    String cleanUrl = originalUrl.replaceAll(RegExp(r'[\?&]key=[^&]*'), ''); 
    cleanUrl = cleanUrl.replaceAll(RegExp(r'[\?&]api_key=[^&]*'), '');
    cleanUrl += (cleanUrl.contains("?") ? "&" : "?") + "api_key=$apiKey";
    return cleanUrl.replaceAll('%7B', '{').replaceAll('%7D', '}');
  }

  static void _applyAppleMapsAesthetic(Map<String, dynamic> styleData) {
    if (styleData['layers'] == null) return;
    for (var layer in styleData['layers']) {
      String id = layer['id']?.toString().toLowerCase() ?? '';
      String type = layer['type']?.toString().toLowerCase() ?? '';
      if (type == 'symbol' && layer['layout'] != null) {
        layer['layout']['icon-allow-overlap'] = false;
        layer['layout']['text-allow-overlap'] = false;
        if (id.contains('poi-level-1')) layer['minzoom'] = 13.0; 
        else if (id.contains('poi-level-2')) layer['minzoom'] = 14.5; 
        else if (id.contains('poi-level-3') || id.contains('poi-level-4')) layer['minzoom'] = 16.5; 
        else if (id.contains('poi')) layer['minzoom'] = 15.0;
      }
    }
  }

  // 🛑 THE ULTIMATE DEEP CLEANER: Har array aur map ke andar ghus kar "" (empty string) ko marega!
  static dynamic _deepCleanEmptyStrings(dynamic obj) {
    if (obj is String) {
      String trimmed = obj.trim();
      if (trimmed.isEmpty || trimmed == '""' || trimmed == "''" || 
          ['Arrow', 'national_highway', 'state_highway', 'hospitals', 'police', 'ola-mobility-fastcharger', 'ola-mbo'].any((e) => trimmed.contains(e))) {
        return 'empty-pixel'; // Replace corrupted/empty names with our invisible pixel
      }
      return obj;
    } else if (obj is List) {
      return obj.map((e) => _deepCleanEmptyStrings(e)).toList();
    } else if (obj is Map) {
      return obj.map((k, v) => MapEntry(k, _deepCleanEmptyStrings(v)));
    }
    return obj;
  }

  static void _cleanBrokenIcons(Map<String, dynamic> styleData) {
    if (styleData['layers'] == null) return;
    
    for (var layer in styleData['layers']) {
      if (layer['layout'] != null && layer['layout']['icon-image'] != null) {
        layer['layout']['icon-image'] = _deepCleanEmptyStrings(layer['layout']['icon-image']);
      }
    }
  }

  static void _inject3DBuildings(Map<String, dynamic> styleData, bool isDark) {
    if (styleData['layers'] == null) return;
    String? targetSource, targetSourceLayer;
    for (var layer in styleData['layers']) {
      String layerId = layer['id']?.toString().toLowerCase() ?? '';
      String sourceLayer = layer['source-layer']?.toString().toLowerCase() ?? '';
      if (layer['type'] == 'fill' && (layerId == 'building' || sourceLayer == 'building')) {
        targetSource = layer['source']; 
        targetSourceLayer = layer['source-layer'];
        break;
      }
    }
    if (targetSource != null && targetSourceLayer != null) {
      styleData['layers'].add({
        "id": "3d-buildings-premium", "source": targetSource, "source-layer": targetSourceLayer, 
        "type": "fill-extrusion", "minzoom": 14,
        "paint": {
          "fill-extrusion-color": isDark ? "#3A3A40" : "#E8E8E8",
          "fill-extrusion-height": ["to-number", ["coalesce", ["get", "height"], ["get", "render_height"], 15.0]],
          "fill-extrusion-base": ["to-number", ["coalesce", ["get", "min_height"], 0.0]],
          "fill-extrusion-opacity": 0.0, 
        }
      });
    }
  }
}