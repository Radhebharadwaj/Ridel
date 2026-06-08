import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart'; 
import 'package:ridel/features/map/models/place_model.dart';

class PlaceService {
  static const Duration _timeout = Duration(seconds: 4);

  // ==========================================================
  // 1. PREMIUM SEARCH (Forward Geocoding via Ola Maps)
  // ==========================================================
  Future<List<PlaceModel>> searchPremiumPlaces(String query, {LatLng? userLocation}) async {
    String urlStr = "https://ridel.ridel.workers.dev/api/maps/places/v1/autocomplete?input=${Uri.encodeComponent(query)}";
    
    final url = Uri.parse(urlStr);
    
    try {
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['predictions'] != null) {
          final List predictions = data['predictions'];
          
          return predictions.map((item) {
            final geo = item['geometry']?['location'];
            final lat = (geo != null ? (geo['lat'] ?? geo['latitude']) : null) ?? 0.0;
            final lng = (geo != null ? (geo['lng'] ?? geo['longitude']) : null) ?? 0.0;
            
            String category = 'unknown';
            if (item['types'] != null && item['types'].isNotEmpty) {
              category = item['types'][0];
            }

            return PlaceModel(
              placeId: item['place_id'] ?? item['reference'] ?? '',
              name: item['structured_formatting']?['main_text'] ?? item['description'].split(',')[0],
              address: item['description'] ?? '',
              latitude: (lat as num).toDouble(),
              longitude: (lng as num).toDouble(),
              categories: [category],
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
  // 3. PLACE DETAILS (Get exact coordinates via Place ID)
  // ==========================================================
  static Future<LatLng?> getPlaceDetails(String placeId) async {
    final url = Uri.parse("https://ridel.ridel.workers.dev/api/maps/places/v1/details?place_id=$placeId");
    try {
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geo = data['result']?['geometry']?['location'];
        if (geo != null) {
          final lat = (geo['lat'] as num?)?.toDouble() ?? (geo['latitude'] as num?)?.toDouble() ?? 0.0;
          final lng = (geo['lng'] as num?)?.toDouble() ?? (geo['longitude'] as num?)?.toDouble() ?? 0.0;
          if (lat != 0.0 && lng != 0.0) {
            return LatLng(lat, lng);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print("⚠️ Place Details API failed: $e");
    }
    return null;
  }

}