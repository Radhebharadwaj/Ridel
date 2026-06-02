import 'dart:async';
import 'dart:convert';

import 'dart:math' as math;
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RouteResult {
  final List<List<LatLng>> allRoutesCoordinates;
  final Map<String, dynamic> geoJson;
  final double distanceKm;
  final int durationMins;
  final List<double> allDurationSeconds;
  final List<Map<String, dynamic>> steps;
  final String firstInstruction;
  final DateTime fetchedAt;
  final List<dynamic> trafficGradientStops;
  final List<String>? congestion;

  // Backward-compatibility getters
  List<LatLng> get coordinates => allRoutesCoordinates.isNotEmpty ? allRoutesCoordinates.first : [];
  List<List<LatLng>> get alternativeRoutes => allRoutesCoordinates.length > 1 ? allRoutesCoordinates.sublist(1) : [];

  RouteResult({
    required this.allRoutesCoordinates,
    required this.geoJson,
    required this.distanceKm,
    required this.durationMins,
    this.allDurationSeconds = const [],
    required this.steps,
    required this.firstInstruction,
    required this.fetchedAt,
    this.trafficGradientStops = const ['interpolate', ['linear'], ['line-progress'], 0.0, '#0A84FF', 1.0, '#0A84FF'],
    this.congestion,
  });

  // Serialization for Offline Fallback
  Map<String, dynamic> toJson() => {
        'allRoutesCoordinates':
            allRoutesCoordinates.map((route) => route.map((c) => [c.latitude, c.longitude]).toList()).toList(),
        'geoJson': geoJson,
        'distanceKm': distanceKm,
        'durationMins': durationMins,
        'allDurationSeconds': allDurationSeconds,
        'steps': steps,
        'firstInstruction': firstInstruction,
        'fetchedAt': fetchedAt.toIso8601String(),
        'trafficGradientStops': trafficGradientStops,
        'congestion': congestion,
      };

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    return RouteResult(
      allRoutesCoordinates: json['allRoutesCoordinates'] != null
          ? (json['allRoutesCoordinates'] as List)
              .map((route) => (route as List).map((c) => LatLng(c[0], c[1])).toList())
              .toList()
          : [],
      geoJson: json['geoJson'],
      distanceKm: json['distanceKm'],
      durationMins: json['durationMins'],
      allDurationSeconds: json['allDurationSeconds'] != null ? List<double>.from(json['allDurationSeconds']) : [],
      steps: List<Map<String, dynamic>>.from(json['steps']),
      firstInstruction: json['firstInstruction'],
      fetchedAt: DateTime.parse(json['fetchedAt']),
      trafficGradientStops: json['trafficGradientStops'] ?? ['interpolate', ['linear'], ['line-progress'], 0.0, '#0A84FF', 1.0, '#0A84FF'],
      congestion: json['congestion'] != null ? List<String>.from(json['congestion']) : null,
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

  Future<RouteResult?> getWaterfallWalkRoute(LatLng origin, LatLng destination) async {
    // 🥇 TIER 1: Ola Maps (Walking) - Best for short local distances
    try {
      debugPrint("🚶‍♂️ Trying Ola Maps (Walking) API...");
      final route = await getRoute(origin, destination, mode: 'walking');
      if (route != null) return route;
      throw Exception("Ola Walking returned null");
    } catch (e) {
      debugPrint("⚠️ Ola Walking failed (maybe distance too long): $e");
    }

    // 🥈 TIER 2: Mapbox (Walking) - The Premium Fallback
    try {
      debugPrint("🦊 Ola failed. Trying Mapbox API...");
      return await _fetchMapboxWalkRoute(origin, destination); 
    } catch (e) {
      debugPrint("⚠️ Mapbox failed: $e");
    }

    // 🥉 TIER 3: OSRM Public - The Free Backup
    try {
      debugPrint("🆓 Mapbox failed. Trying Public OSRM API...");
      // return await _fetchOSRMRoute(origin, destination);
      throw Exception("OSRM not implemented yet");
    } catch (e) {
      debugPrint("⚠️ OSRM Public failed: $e");
    }

    // 🚨 TIER 4: Ola Maps (Driving) - Ultimate Fallback
    try {
      debugPrint("🚗 All walking APIs failed! Falling back to Ola Maps Driving Route.");
      return await getRoute(origin, destination, mode: 'driving');
    } catch (e) {
      debugPrint("❌ CRITICAL: ALL ROUTING TIERS FAILED.");
      return null;
    }
  }

  Future<RouteResult?> _fetchMapboxWalkRoute(LatLng origin, LatLng destination) async {
    final mapboxKey = dotenv.env['MAPBOX_API_KEY'] ?? '';
    if (mapboxKey.isEmpty || mapboxKey == 'YOUR_KEY_HERE') {
      throw Exception("Mapbox key is missing or placeholder. Skipping to next tier.");
    }

    // Logic for mapbox would go here, throwing exception for now since not implemented yet.
    throw Exception("Mapbox API call not implemented.");
  }

  Future<RouteResult?> _fetchWithRetry(
      LatLng origin, LatLng destination, String mode, String cacheKey) async {
    // 🚀 DYNAMIC API PROFILE MAPPING
    String apiMode = 'driving';
    if (mode == 'walk' || mode == 'walking' || mode == 'pedestrian') {
      apiMode = 'walking';
    } else if (mode == 'bike' || mode == 'twowheeler') {
      apiMode = 'bike';
    } else if (mode == 'heavy' || mode == 'auto') {
      apiMode = 'auto'; // Ola's default fallback for heavy/auto
    } else {
      apiMode = 'driving';
    }

    final String olaApiUrl =
        '$_baseUrl?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=$apiMode&alternatives=true&steps=true&overview=full&annotations=congestion&api_key=$_apiKey';

    debugPrint("🚀 OLA API EXACT URL: $olaApiUrl");

    final Uri url = Uri.parse(olaApiUrl);

    int attempts = 0;
    while (attempts < 2) {
      try {
        attempts++;
        // 🚀 FIX: Added GZIP header for reduced bandwidth
        // 🚨 CRITICAL FIX: Change GET to POST
        final response = await _client.post(url, headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip'
        }).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final Map<String, dynamic>? primitiveData =
              _processHeavyRouteSync(response.body);

          if (primitiveData != null) {
            final List<List<List<double>>> rawAll = primitiveData['allRoutes'];
            final List<List<LatLng>> allRoutesCoordinates = rawAll.map((route) => route.map((c) => LatLng(c[0], c[1])).toList()).toList();

            return RouteResult(
              allRoutesCoordinates: allRoutesCoordinates,
              geoJson: primitiveData['geoJson'],
              distanceKm: primitiveData['distanceKm'],
              durationMins: primitiveData['durationMins'],
              allDurationSeconds: List<double>.from(primitiveData['allDurationSeconds'] ?? [(primitiveData['durationMins'] * 60).toDouble()]),
              steps: primitiveData['steps'],
              firstInstruction: primitiveData['firstInstruction'],
              fetchedAt: DateTime.now(),
              trafficGradientStops: primitiveData['gradientStops'] ?? ['interpolate', ['linear'], ['line-progress'], 0.0, '#0A84FF', 1.0, '#0A84FF'],
              congestion: primitiveData['congestion'],
            );
          }
        } else {
           debugPrint("❌ OLA API ERROR: ${response.statusCode} - ${response.body}");
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
      
      final primary = _parseRouteObject(data['routes'][0]);
      if (primary == null) return null;
      
      List<List<List<double>>> allRoutes = [primary['coords']];
      List<double> allDurationSeconds = [primary['durationSeconds']];
      for (int i = 1; i < data['routes'].length; i++) {
        final alt = _parseRouteObject(data['routes'][i]);
        if (alt != null) {
          allRoutes.add(alt['coords']);
          allDurationSeconds.add(alt['durationSeconds']);
        }
      }
      
      primary['allRoutes'] = allRoutes;
      primary['allDurationSeconds'] = allDurationSeconds;
      return primary;
    } catch (e) {
      debugPrint("Isolate Decoding Error: $e");
      return null;
    }
  }

  static Map<String, dynamic>? _parseRouteObject(dynamic route) {
    if (route['legs'] == null || route['legs'].isEmpty) return null;
    final leg = route['legs'][0];

    List<String>? congestionData;
    if (leg['annotation'] != null && leg['annotation']['congestion'] != null) {
      congestionData = List<String>.from(leg['annotation']['congestion']);
    }

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

    // Process traffic speed
    List<dynamic> gradientStops = ['interpolate', ['linear'], ['line-progress']];
    double currentDist = 0.0;
    double totalDist = (leg['distance'] as num?)?.toDouble() ?? 1.0;
    double lastProgress = -1.0;
    
    for (var step in safeSteps) {
      double stepDist = (step['distance'] as num?)?.toDouble() ?? 0.0;
      double progress = currentDist / totalDist;
      if (progress > 1.0) progress = 1.0;
      
      if (progress <= lastProgress) {
        progress = lastProgress + 0.00001; // ensure strictly increasing
      }
      lastProgress = progress;
      
      String color = '#0A84FF'; // default Apple Blue / Free flow
      if (step['traffic_speed'] != null) {
        final speed = step['traffic_speed'];
        if (speed == 1 || speed == 'jam') {
          color = '#FF3B30';
        } else if (speed == 2 || speed == 'sluggish') {
          color = '#FFD600';
        } else if (speed == 3 || speed == 'free') {
          color = '#0A84FF';
        }
      }
      
      gradientStops.add(progress);
      gradientStops.add(color);
      currentDist += stepDist;
    }

    if (gradientStops.length <= 3) {
      gradientStops.addAll([0.0, '#0A84FF', 1.0, '#0A84FF']);
    } else {
      double endProgress = 1.0;
      if (endProgress <= lastProgress) endProgress = lastProgress + 0.00001;
      gradientStops.add(endProgress);
      gradientStops.add(gradientStops[gradientStops.length - 2]); 
    }

    return {
      'coords': rawCoords,
      'geoJson': geoJson,
      'distanceKm': leg['distance'] / 1000,
      'durationMins': (leg['duration'] / 60).ceil(),
      'durationSeconds': (leg['duration'] as num).toDouble(),
      'steps': safeSteps,
      'firstInstruction': instruction,
      'gradientStops': gradientStops,
      'congestion': congestionData,
    };
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
