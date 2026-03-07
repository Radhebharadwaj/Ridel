import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart'; 
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/features/map/models/place_model.dart';

class PlaceService {
  static const Duration _timeout = Duration(seconds: 4);

  // ==========================================================
  // 1. PREMIUM SEARCH (Forward Geocoding via Ola Maps)
  // ==========================================================
  Future<List<PlaceModel>> searchPremiumPlaces(String query) async {
    final url = Uri.parse("https://api.olamaps.io/places/v1/autocomplete?input=${Uri.encodeComponent(query)}&api_key=${MapStyleHelper.olaApiKey}");
    
    try {
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['predictions'] != null) {
          final List predictions = data['predictions'];
          
          return predictions.map((item) {
            final geo = item['geometry']?['location'];
            final lat = geo != null ? geo['lat'] : 0.0;
            final lng = geo != null ? geo['lng'] : 0.0;
            
            String category = 'unknown';
            if (item['types'] != null && item['types'].isNotEmpty) {
              category = item['types'][0];
            }

            return PlaceModel(
              placeId: item['place_id'] ?? item['reference'] ?? '',
              name: item['structured_formatting']?['main_text'] ?? item['description'].split(',')[0],
              address: item['description'] ?? '',
              latitude: lat.toDouble(),
              longitude: lng.toDouble(),
              category: category,
            );
          }).toList();
        }
      }
    } catch (e) {
      if (kDebugMode) print("⚠️ Premium Ola search failed: $e");
    }
    return [];
  }

  // ==========================================================
  // 2. GET COORDINATES (Wrapper for Ola Maps Search)
  // ==========================================================
  static Future<LatLng?> getCoordinates(String query) async {
    final service = PlaceService();
    final results = await service.searchPremiumPlaces(query);
    
    if (results.isNotEmpty) {
      return LatLng(results.first.latitude, results.first.longitude);
    }
    return null;
  }

  // ==========================================================
  // 3. REVERSE GEOCODING (Lat/Lng to City Name via OSM Free)
  // ==========================================================
  static Future<String?> getCityFromCoordinates(double lat, double lon) async {
    try {
      final url = Uri.parse("https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json");
      
      final response = await http.get(url, headers: {
        'User-Agent': 'Ridel_App_v1.0' 
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['address'] != null) {
          final address = data['address'];
          
          // Accuracy Fallback
          final String? cityName = address['city'] ?? 
                                   address['town'] ?? 
                                   address['village'] ?? 
                                   address['state_district'] ?? 
                                   address['county'];
                                   
          return cityName;
        }
      }
    } catch (e) {
      print("⚠️ Reverse Geocode Error: $e");
    }
    return null;
  }
}