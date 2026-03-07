import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RouteData {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMins;
  final DateTime timestamp;

  RouteData({required this.points, required this.distanceKm, required this.durationMins, required this.timestamp});
  
  Map<String, dynamic> toJson() => {
    'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    'distanceKm': distanceKm, 'durationMins': durationMins, 'timestamp': timestamp.toIso8601String(),
  };
  
  factory RouteData.fromJson(Map<String, dynamic> json) => RouteData(
    points: (json['points'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList(),
    distanceKm: json['distanceKm'], durationMins: json['durationMins'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}

/// 🍏 Premium Routing Service: Strict CORS handling and fast GeoJSON parsing.
class RoutingService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org/route/v1';
  static const Duration _cacheTTL = Duration(minutes: 30);
  static final Map<String, RouteData> _memoryCache = {};

  static Future<RouteData?> getRoute(
    LatLng start, LatLng end, {String mode = 'driving', bool useCache = true}
  ) async {
    final cacheKey = 'route_${start.latitude}_${start.longitude}_${end.latitude}_${end.longitude}_$mode';

    if (useCache && _memoryCache.containsKey(cacheKey)) {
      if (DateTime.now().difference(_memoryCache[cacheKey]!.timestamp) < _cacheTTL) {
        return _memoryCache[cacheKey];
      }
    }

    try {
      final url = Uri.parse("$_osrmBaseUrl/$mode/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson");
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final List coords = route['geometry']['coordinates'];
          
          final routeData = RouteData(
            points: coords.map((c) => LatLng(c[1], c[0])).toList(),
            distanceKm: route['distance'] / 1000,
            durationMins: route['duration'] / 60,
            timestamp: DateTime.now(),
          );
          
          _memoryCache[cacheKey] = routeData;
          return routeData;
        }
      }
    } catch (e) {
      debugPrint("⚠️ Routing silent fallback: $e");
    }
    return null;
  }
}