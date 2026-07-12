import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MapStyleInterceptor {
  static Future<String> getCuredStyle(String styleUrl) async {
    try {
      final response = await http.get(Uri.parse(styleUrl));
      if (response.statusCode == 200) {
        Map<String, dynamic> style = jsonDecode(response.body);
        
        // 🚀 1. Destroy the root sprite sheet
        style.remove('sprite'); 
        
        if (style['layers'] != null) {
          List<dynamic> layers = style['layers'];
          
          for (var layer in layers) {
            // 🚀 2. Strip ALL layout image requests
            if (layer['layout'] != null) {
              layer['layout'].remove('icon-image');
            }
            
            // 🚀 3. Strip ALL paint pattern requests (The true cause of the crash)
            if (layer['paint'] != null) {
              layer['paint'].remove('line-pattern');
              layer['paint'].remove('fill-pattern');
              layer['paint'].remove('fill-extrusion-pattern');
              layer['paint'].remove('background-pattern');
            }
          }
          
          // 🚀 4. Amputate known defective layers
          layers.removeWhere((layer) {
            final id = layer['id'].toString().toLowerCase();
            return id.contains('transit_rail') || 
                   id.contains('hatching') || 
                   id.contains('glow_casing');
          });
        }
        
        return jsonEncode(style);
      }
    } catch (e) {
      debugPrint("🛡️ Style Interceptor Failed: Using fallback.");
    }
    return styleUrl; // Fallback to raw URL if network fails
  }
}
