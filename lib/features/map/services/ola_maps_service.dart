import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:ridel/core/config/app_config.dart';

class OlaMapsService {
  Future<String?> fetchCityFromOla(double lat, double lng) async {
    try {
      final apiKey = AppConfig.olaMapsKey;
      if (apiKey.isEmpty) {
        debugPrint("Ola Maps API Key is missing");
        return null;
      }
      
      final url = Uri.parse(
          'https://api.olamaps.io/places/v1/reverse-geocode?latlng=$lat,$lng&api_key=$apiKey');

      final response = await http.get(url, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8)); // 🚀 TIMEOUT FIX

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          
          if (result['address_components'] != null) {
            final components = result['address_components'] as List;
            
            // Priority 1: Locality
            for (var comp in components) {
              final types = comp['types'] as List;
              if (types.contains('locality') || 
                  types.contains('city')) {
                return comp['short_name'] ?? comp['long_name'];
              }
            }
            
            // Priority 2: Sub-locality or neighborhood
            for (var comp in components) {
              final types = comp['types'] as List;
              if (types.contains('sub_locality') || 
                  types.contains('neighborhood') ||
                  types.contains('sub_locality_level_1') ||
                  types.contains('sub_locality_level_2')) {
                return comp['short_name'] ?? comp['long_name'];
              }
            }
          }
          
          // Priority 3: Fallback extracting city from formatted_address
          final formatted = result['formatted_address'] as String?;
          if (formatted != null && formatted.isNotEmpty) {
             final parts = formatted.split(',');
             if (parts.isNotEmpty) {
                return parts[0].trim();
             }
          }
          
          return result['name'];
        }
      } else {
        // Suppress API body logging to prevent accidental key leaks
      }
    } catch (e) {
      // Suppress exception logging
    }
    return null;
  }
}
