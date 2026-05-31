import 'dart:async';
import 'dart:convert';

import 'dart:math' as math;
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🚀 1. The Clean Data Model
class RouteResult {
  final List<LatLng> coordinates;
  final Map<String, dynamic> geoJson;
  final double distanceKm;
  final int durationMins;
  final List<Map<String, dynamic>> steps;
  final String firstInstruction;
  final DateTime fetchedAt;

  RouteResult({
    required this.coordinates,
    required this.geoJson,
    required this.distanceKm,
    required this.durationMins,
    required this.steps,
    required this.firstInstruction,
    required this.fetchedAt,
  });

  // Serialization for Offline Fallback
  Map<String, dynamic> toJson() => {
        'coordinates':
            coordinates.map((c) => [c.latitude, c.longitude]).toList(),
        'geoJson': geoJson,
        'distanceKm': distanceKm,
        'durationMins': durationMins,
        'steps': steps,
        'firstInstruction': firstInstruction,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    return RouteResult(
      coordinates:
          (json['coordinates'] as List).map((c) => LatLng(c[0], c[1])).toList(),
      geoJson: json['geoJson'],
      distanceKm: json['distanceKm'],
      durationMins: json['durationMins'],
      steps: List<Map<String, dynamic>>.from(json['steps']),
      firstInstruction: json['firstInstruction'],
      fetchedAt: DateTime.parse(json['fetchedAt']),
    );
  }
}

/// 🧠 The Ultimate Routing Brain
class RouteEngineService {
  static const String _baseUrl = 'https://api.olamaps.io/routing/v1/directions';

  final http.Client _client = http.Client();
  late final String _apiKey;

  final LinkedHashMap<String, RouteResult> _lruCache =
      LinkedHashMap<String, RouteResult>();
  static const int _maxCacheSize = 15;
  static const Duration _cacheTtl = Duration(minutes: 15);

  final Map<String, Future<RouteResult?>> _inFlightRequests = {};

  RouteEngineService() {
    _apiKey = dotenv.env['OLA_MAPS_API_KEY'] ?? '';
  }

  Future<RouteResult?> getRoute(LatLng origin, LatLng destination,
      {String mode = "driving"}) async {
    // 🚀 FIX: Cache precision set to 4 decimal places (~11 meters tolerance)
    final cacheKey =
        "${mode}_${origin.latitude.toStringAsFixed(4)}_${origin.longitude.toStringAsFixed(4)}_${destination.latitude.toStringAsFixed(4)}_${destination.longitude.toStringAsFixed(4)}";

    // 1. RAM Cache Check
    if (_lruCache.containsKey(cacheKey)) {
      final cachedRoute = _lruCache.remove(cacheKey)!;
      if (DateTime.now().difference(cachedRoute.fetchedAt) < _cacheTtl) {
        _lruCache[cacheKey] = cachedRoute;
        debugPrint("⚡ Route Engine: Instant RAM Cache Hit!");
        return cachedRoute;
      }
    }

    // 2. Request Deduplication Check
    if (_inFlightRequests.containsKey(cacheKey)) {
      return await _inFlightRequests[cacheKey];
    }

    // 3. Network Call
    final futureReq = _fetchWithRetry(origin, destination, mode, cacheKey);
    _inFlightRequests[cacheKey] = futureReq;

    try {
      final result = await futureReq;
      if (result != null) {
        _saveToCache(cacheKey, result);
        _persistToDisk(cacheKey, result); // Save for offline
      } else {
        // 🚀 FIX: Fallback to Disk Cache if Network Fails
        return await _loadFromDisk(cacheKey);
      }
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  Future<RouteResult?> _fetchWithRetry(
      LatLng origin, LatLng destination, String mode, String cacheKey) async {
    final String olaApiUrl =
        '$_baseUrl?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=$mode&steps=true&overview=full&api_key=$_apiKey';

    final Uri url = Uri.parse(olaApiUrl);

    int attempts = 0;
    while (attempts < 2) {
      try {
        attempts++;
        // 🚀 FIX: Added GZIP header for reduced bandwidth
        final response = await _client.get(url, headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip'
        }).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final Map<String, dynamic>? primitiveData =
              _processHeavyRouteSync(response.body);

          if (primitiveData != null) {
            final List<List<double>> rawCoords = primitiveData['coords'];
            final coords = rawCoords.map((c) => LatLng(c[0], c[1])).toList();

            return RouteResult(
              coordinates: coords,
              geoJson: primitiveData['geoJson'],
              distanceKm: primitiveData['distanceKm'],
              durationMins: primitiveData['durationMins'],
              steps: primitiveData['steps'],
              firstInstruction: primitiveData['firstInstruction'],
              fetchedAt: DateTime.now(),
            );
          }
        }
      } catch (e) {
        debugPrint("⚠️ Route API Attempt $attempts failed: $e");
        if (attempts == 1) {
          // 🚀 FIX: Added 1 Second Delay before retry to prevent server ban
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    return null;
  }

  void _saveToCache(String key, RouteResult result) {
    if (_lruCache.length >= _maxCacheSize) {
      _lruCache.remove(_lruCache.keys.first);
    }
    _lruCache[key] = result;
  }

  // 🚀 FIX: Persistent Offline Cache Logic
  Future<void> _persistToDisk(String key, RouteResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_route_$key', json.encode(result.toJson()));
    } catch (_) {}
  }

  Future<RouteResult?> _loadFromDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('offline_route_$key');
      if (data != null) {
        debugPrint("📶 Route Engine: Loaded from Offline Disk Cache.");
        return RouteResult.fromJson(json.decode(data));
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _client.close();
    _lruCache.clear();
    _inFlightRequests.clear();
  }

  // ====================================================================
  // 🧠 THE ISOLATE CORE
  // ====================================================================

  static Map<String, dynamic>? _processHeavyRouteSync(String responseBody) {
    try {
      final data = json.decode(responseBody);
      if (data['routes'] == null || data['routes'].isEmpty) return null;
      final route = data['routes'][0];
      if (route['legs'] == null || route['legs'].isEmpty) return null;
      final leg = route['legs'][0];

      String encodedPolyline = "";
      if (route['overview_polyline'] is String) {
        encodedPolyline = route['overview_polyline'];
      } else if (route['overview_polyline'] is Map &&
          route['overview_polyline']['points'] != null) {
        encodedPolyline = route['overview_polyline']['points'];
      } else if (route['geometry'] is String) {
        encodedPolyline = route['geometry'];
      }
      if (encodedPolyline.isEmpty) return null;

      List<List<double>> rawCoords = _decodePolylinePrimitives(encodedPolyline);
      rawCoords = _simplifyPolyline(rawCoords, 0.00005);

      final geoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": rawCoords.map((c) => [c[1], c[0]]).toList()
            },
            "properties": {}
          }
        ]
      };

      final rawSteps = leg['steps'] as List<dynamic>? ?? [];
      final safeSteps = rawSteps.map((s) => s as Map<String, dynamic>).toList();
      String instruction = "Head to destination";
      if (safeSteps.isNotEmpty &&
          safeSteps.first['html_instructions'] != null) {
        instruction = safeSteps.first['html_instructions']
            .toString()
            .replaceAll(RegExp(r'<[^>]*>'), '');
      }

      return {
        'coords': rawCoords,
        'geoJson': geoJson,
        'distanceKm': leg['distance'] / 1000,
        'durationMins': (leg['duration'] / 60).ceil(),
        'steps': safeSteps,
        'firstInstruction': instruction,
      };
    } catch (e) {
      debugPrint("Isolate Decoding Error: $e");
      return null;
    }
  }

  static List<List<double>> _decodePolylinePrimitives(String polyline) {
    List<List<double>> coords = [];
    int index = 0, len = polyline.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b;
      int result = 0, multiplier = 1;

      do {
        if (index >= len) break;
        b = polyline.codeUnitAt(index++) - 63;
        result += (b & 0x1f) * multiplier;
        multiplier *= 32;
      } while (b >= 0x20 && index < len);

      int dlat = (result & 1) != 0 ? -((result ~/ 2) + 1) : (result ~/ 2);
      lat += dlat;

      result = 0;
      multiplier = 1;

      do {
        if (index >= len) break;
        b = polyline.codeUnitAt(index++) - 63;
        result += (b & 0x1f) * multiplier;
        multiplier *= 32;
      } while (b >= 0x20 && index < len);

      int dlng = (result & 1) != 0 ? -((result ~/ 2) + 1) : (result ~/ 2);
      lng += dlng;

      double finalLat = lat / 100000.0;
      double finalLng = lng / 100000.0;

      if (finalLat >= -90.0 &&
          finalLat <= 90.0 &&
          finalLng >= -180.0 &&
          finalLng <= 180.0) {
        coords.add([finalLat, finalLng]);
      }
    }
    return coords;
  }

  // 🚀 FIX: Proper Iterative-style Douglas-Peucker (No Stack Overflow risk)
  // 🚀 FIX: Corrected Math Formula for latitude/longitude
  static List<List<double>> _simplifyPolyline(
      List<List<double>> points, double tolerance) {
    if (points.length < 3) return points;

    List<int> markers = List.filled(points.length, 0);
    markers[0] = 1;
    markers[points.length - 1] = 1;

    List<List<int>> stack = [];
    stack.add([0, points.length - 1]);

    while (stack.isNotEmpty) {
      List<int> range = stack.removeLast();
      int first = range[0];
      int last = range[1];

      double maxDist = 0;
      int index = 0;

      for (int i = first + 1; i < last; i++) {
        double dist =
            _perpendicularDistance(points[i], points[first], points[last]);
        if (dist > maxDist) {
          maxDist = dist;
          index = i;
        }
      }

      if (maxDist > tolerance) {
        markers[index] = 1;
        stack.add([first, index]);
        stack.add([index, last]);
      }
    }

    List<List<double>> simplified = [];
    for (int i = 0; i < points.length; i++) {
      if (markers[i] == 1) simplified.add(points[i]);
    }
    return simplified;
  }

  // 🚀 FIX: Correct mathematical calculation for Lat/Lng pairs
  static double _perpendicularDistance(
      List<double> pt, List<double> lineStart, List<double> lineEnd) {
    double dx = lineEnd[1] - lineStart[1]; // Longitude diff
    double dy = lineEnd[0] - lineStart[0]; // Latitude diff

    if (dx == 0 && dy == 0) {
      return math.sqrt(math.pow(pt[0] - lineStart[0], 2) +
          math.pow(pt[1] - lineStart[1], 2));
    }

    double numerator =
        (dx * (lineStart[0] - pt[0]) - dy * (lineStart[1] - pt[1])).abs();
    return numerator / math.sqrt(dx * dx + dy * dy);
  }
}

// Helper function to decode standard polyline strings
List<LatLng> decodePolyline(String encoded) {
  List<LatLng> points = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return points;
}
