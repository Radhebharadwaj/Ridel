import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MapStyleInterceptor {
  static Future<String> getCuredStyle(String styleUrl) async {
    try {
      Map<String, dynamic>? style;

      if (styleUrl.startsWith('data:application/json')) {
        final commaIdx = styleUrl.indexOf(',');
        if (commaIdx != -1) {
          final jsonStr = Uri.decodeComponent(styleUrl.substring(commaIdx + 1));
          style = jsonDecode(jsonStr);
        }
      } else if (styleUrl.trim().startsWith('{')) {
        style = jsonDecode(styleUrl);
      } else if (styleUrl.startsWith('http://') || styleUrl.startsWith('https://')) {
        final response = await http.get(Uri.parse(styleUrl)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          style = jsonDecode(response.body);
        }
      }

      if (style != null) {
        // 🚀 1. Destroy the root sprite sheet
        style.remove('sprite'); 

        if (style['layers'] != null && style['layers'] is List) {
          List<dynamic> layers = style['layers'];

          for (var layer in layers) {
            if (layer is Map) {
              // 🚀 2. Strip ALL layout image requests
              if (layer['layout'] != null && layer['layout'] is Map) {
                layer['layout'].remove('icon-image');
              }

              // 🚀 3. Strip ALL paint pattern requests
              if (layer['paint'] != null && layer['paint'] is Map) {
                layer['paint'].remove('line-pattern');
                layer['paint'].remove('fill-pattern');
                layer['paint'].remove('fill-extrusion-pattern');
                layer['paint'].remove('background-pattern');
              }
            }
          }

          // 🚀 4. Amputate known defective layers
          layers.removeWhere((layer) {
            if (layer is! Map) return false;
            final id = (layer['id'] ?? '').toString().toLowerCase();
            return id.contains('transit_rail') || 
                   id.contains('hatching') || 
                   (id.contains('glow_casing') && !id.endsWith('-glow-casing'));
          });
        }

        final curedStr = jsonEncode(style);
        return kIsWeb ? 'data:application/json;charset=utf-8,${Uri.encodeComponent(curedStr)}' : curedStr;
      }
    } catch (e) {
      debugPrint("🛡️ Style Interceptor Notice: $e");
    }
    return styleUrl; // Fallback to raw URL if parsing fails
  }
}
