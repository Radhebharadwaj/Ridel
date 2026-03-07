// lib/features/map/services/open_map_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/place_model.dart';

class OpenMapService {
  static const Duration _timeout = Duration(seconds: 4);

  Future<List<PlaceModel>> searchPlaces(String query) async {
    // Nominatim API (Free & Open Source)
    final url = Uri.parse("https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=5");
    
    try {
      final response = await http.get(url, headers: {
        'User-Agent': 'RidelApp/1.0', // Required by OpenStreetMap policies
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        
        return data.map((item) {
          return PlaceModel(
            placeId: item['place_id'].toString(),
            name: item['name'] ?? item['display_name'].split(',')[0],
            address: item['display_name'] ?? '',
            latitude: double.tryParse(item['lat'].toString()) ?? 0.0,
            longitude: double.tryParse(item['lon'].toString()) ?? 0.0,
            category: item['type'] ?? item['class'] ?? 'unknown',
          );
        }).toList();
      }
    } catch (e) {
      if (kDebugMode) print("⚠️ OpenMap search failed: $e");
    }
    return [];
  }
}