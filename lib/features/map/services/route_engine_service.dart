import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:collection';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:ridel/core/config/app_config.dart';

class RouteResult {
  final List<List<LatLng>> allRoutesCoordinates;
  final double distanceKm;
  final int durationMins;
  final List<double> allDurationSeconds;
  final List<Map<String, dynamic>> steps;
  final String firstInstruction;
  final DateTime fetchedAt;
  final List<dynamic> trafficGradientStops;
  final List<String>? congestion;

  // Backward-compatibility getters
  List<LatLng> get coordinates =>
      allRoutesCoordinates.isNotEmpty ? allRoutesCoordinates.first : [];
  List<List<LatLng>> get alternativeRoutes =>
      allRoutesCoordinates.length > 1 ? allRoutesCoordinates.sublist(1) : [];

  RouteResult({
    required this.allRoutesCoordinates,
    required this.distanceKm,
    required this.durationMins,
    this.allDurationSeconds = const [],
    required this.steps,
    required this.firstInstruction,
    required this.fetchedAt,
    this.trafficGradientStops = const [
      'interpolate',
      ['linear'],
      ['line-progress'],
      0.0,
      '#0A84FF',
      1.0,
      '#0A84FF'
    ],
    this.congestion,
  });

  // Serialization for Offline Fallback
  Map<String, dynamic> toJson() => {
        'allRoutesCoordinates': allRoutesCoordinates
            .map(
                (route) => route.map((c) => [c.latitude, c.longitude]).toList())
            .toList(),
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
              .map((route) =>
                  (route as List).map((c) => LatLng(c[0], c[1])).toList())
              .toList()
          : [],
      distanceKm: json['distanceKm'],
      durationMins: json['durationMins'],
      allDurationSeconds: json['allDurationSeconds'] != null
          ? List<double>.from(json['allDurationSeconds'])
          : [],
      steps: List<Map<String, dynamic>>.from(json['steps']),
      firstInstruction: json['firstInstruction'],
      fetchedAt: DateTime.parse(json['fetchedAt']),
      trafficGradientStops: json['trafficGradientStops'] ??
          [
            'interpolate',
            ['linear'],
            ['line-progress'],
            0.0,
            '#0A84FF',
            1.0,
            '#0A84FF'
          ],
      congestion: json['congestion'] != null
          ? List<String>.from(json['congestion'])
          : null,
    );
  }
}

int safeIntFromJson(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double safeDoubleFromJson(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

/// 🧠 The Ultimate Routing Brain
class RouteEngineService {
  // 🚀 FIX: Bypassed dead Cloudflare worker, now using Direct Ola Maps API
  static const String _baseUrl = 'https://api.olamaps.io/routing/v1/directions';

  final http.Client _client = http.Client();

  final LinkedHashMap<String, RouteResult> _lruCache =
      LinkedHashMap<String, RouteResult>();
  static const int _maxCacheSize = 3;
  static const Duration _cacheTtl = Duration(minutes: 15);

  final Map<String, Future<RouteResult?>> _inFlightRequests = {};

  RouteEngineService();

  Future<RouteResult?> getRoute(LatLng origin, LatLng destination,
      {String mode = "driving", List<LatLng>? waypoints}) async {
    // 🚀 FIX: Cache precision set to 4 decimal places (~11 meters tolerance)
    String wpKey = "";
    if (waypoints != null && waypoints.isNotEmpty) {
      wpKey = "_${waypoints.map((w) => "${w.latitude.toStringAsFixed(4)}_${w.longitude.toStringAsFixed(4)}").join('_')}";
    }
    
    final cacheKey =
        "${mode}_${origin.latitude.toStringAsFixed(4)}_${origin.longitude.toStringAsFixed(4)}_${destination.latitude.toStringAsFixed(4)}_${destination.longitude.toStringAsFixed(4)}$wpKey";

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
    final futureReq = _fetchWaterfallRoute(origin, destination, mode, cacheKey, waypoints: waypoints);
    _inFlightRequests[cacheKey] = futureReq;

    try {
      final result = await futureReq;
      if (result != null) {
        _saveToCache(cacheKey, result);
        _persistToDisk(cacheKey, result); // Save for offline (non-blocking)
        return result;
      }
    } catch (e) {
      debugPrint("🌐 Network/API Failed, relying on Offline Disk Cache: $e");
    } finally {
      _inFlightRequests.remove(cacheKey);
    }

    // 🚀 FIX: Fallback executes if result was null OR if a network exception was thrown
    return await _loadFromDisk(cacheKey);
  }

  RouteResult _sanitizeRouteResult(RouteResult result, String mode) {
    double distKm = result.distanceKm;
    int currentMins = result.durationMins;

    // Extract current seconds safely
    double currentSecs = result.allDurationSeconds.isNotEmpty
        ? result.allDurationSeconds[0]
        : (currentMins * 60.0);

    // 🧠 HEURISTIC FALLBACK: Average human walks at 5 km/h (12 mins per km)
    if (mode == 'walk' || mode == 'walking') {
      // ALWAYS calculate our own walking time (average 12 mins per km)
      int expectedWalkMins = (distKm * 12).round();
      currentMins = expectedWalkMins;
      currentSecs = expectedWalkMins * 60.0;
      debugPrint(
          "🚶‍♂️ Walk Mode: Ignoring API time. Forcing calculated time: $currentMins mins for $distKm km");
    }

    // 🚨 STRICT SYNC: Ensure both minutes and seconds arrays represent the EXACT same value
    // This fixes the UI mismatch between the Map Pill and the Bottom Sheet.
    List<double> syncedDurations = result.allDurationSeconds.isNotEmpty
        ? List<double>.from(result.allDurationSeconds)
        : [currentSecs];
    syncedDurations[0] = currentSecs;

    return RouteResult(
      allRoutesCoordinates: result.allRoutesCoordinates,
      allDurationSeconds: syncedDurations,
      distanceKm: distKm,
      durationMins: currentMins, // Strictly synced with allDurationSeconds[0]
      steps: result.steps,
      firstInstruction: result.firstInstruction,
      fetchedAt: result.fetchedAt,
      trafficGradientStops: result.trafficGradientStops,
      congestion: result.congestion,
    );
  }

  Future<RouteResult?> _fetchWaterfallRoute(LatLng origin, LatLng destination, String mode, String cacheKey, {List<LatLng>? waypoints}) async {
    if (mode == 'walk' || mode == 'walking') {
      return getWaterfallWalkRoute(origin, destination, waypoints: waypoints);
    } else {
      debugPrint("🚗 Trying Direct Ola Maps ($mode) API...");
      final route = await _getOlaRoute(origin, destination, mode, waypoints: waypoints);
      if (route != null) return _sanitizeRouteResult(route, mode);
      throw Exception("Ola API returned null.");
    }
  }

  Future<RouteResult?> getWaterfallWalkRoute(LatLng origin, LatLng destination, {List<LatLng>? waypoints}) async {
    debugPrint("🚶‍♂️ Trying Direct Ola Maps (Walking) API...");
    final route = await _getOlaRoute(origin, destination, 'walking', waypoints: waypoints);
    if (route != null) return _sanitizeRouteResult(route, 'walking');
    throw Exception("Ola API returned null.");
  }

  Future<RouteResult?> _getOlaRoute(
      LatLng origin, LatLng destination, String mode, {List<LatLng>? waypoints}) async {
    String apiMode = 'driving';
    if (mode == 'walk' || mode == 'walking' || mode == 'pedestrian') {
      apiMode = 'walking';
    } else if (mode == 'bike' || mode == 'twowheeler') {
      apiMode = 'bike';
    } else if (mode == 'heavy' || mode == 'auto') {
      apiMode = 'auto';
    } else {
      apiMode = 'driving';
    }

    // 🚀 FIX: Directly appending the API Key from AppConfig
    final apiKey = AppConfig.olaMapsKey;
    String waypointsParam = "";
    if (waypoints != null && waypoints.isNotEmpty) {
      waypointsParam = "&waypoints=${waypoints.map((wp) => "${wp.latitude},${wp.longitude}").join('|')}";
    }

    final String olaApiUrl =
        '$_baseUrl?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}$waypointsParam&api_key=$apiKey&mode=$apiMode&alternatives=true&steps=true&traffic_metadata=true&overview=full';

    int attempts = 0;
    while (attempts < 2) {
      try {
        attempts++;
        final response = await _client.post(Uri.parse(olaApiUrl), headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip'
        }).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 || response.statusCode == 201) {
          developer.log(response.body, name: 'OLA_ROUTING_JSON');
          final Map<String, dynamic>? primitiveData =
              await compute(_processHeavyRouteSync, response.body);

          if (primitiveData != null) {
            final List<List<List<double>>> rawAll = primitiveData['allRoutes'];
            final List<List<LatLng>> allRoutesCoordinates = rawAll
                .map((route) => route.map((c) => LatLng(c[0], c[1])).toList())
                .toList();

            return RouteResult(
              allRoutesCoordinates: allRoutesCoordinates,
              distanceKm: safeDoubleFromJson(primitiveData['distanceKm']),
              durationMins: safeIntFromJson(primitiveData['durationMins']),
              allDurationSeconds: List<double>.from(
                  primitiveData['allDurationSeconds'] ??
                      [
                        (safeIntFromJson(primitiveData['durationMins']) * 60)
                            .toDouble()
                      ]),
              steps: primitiveData['steps'],
              firstInstruction: primitiveData['firstInstruction'],
              fetchedAt: DateTime.now(),
              trafficGradientStops: primitiveData['gradientStops'] ??
                  [
                    'interpolate',
                    ['linear'],
                    ['line-progress'],
                    0.0,
                    '#0A84FF',
                    1.0,
                    '#0A84FF'
                  ],
              congestion: primitiveData['congestion'],
            );
          }
        } else {
          throw Exception("Ola API HTTP ${response.statusCode}");
        }
      } catch (e) {
        if (attempts == 2) {
          // Suppressed logging to prevent accidental key leaks
          return null; // 🚀 FIX: Return null instead of rethrowing to allow offline fallback
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  void _saveToCache(String key, RouteResult result) {
    // 🚀 CRITICAL LRU FIX: Remove the key first to force it to the end of the insertion order
    _lruCache.remove(key); 
    _lruCache[key] = result;

    if (_lruCache.length > _maxCacheSize) {
      _lruCache.remove(_lruCache.keys.first);
    }
  }

  // 🚀 FIX: Persistent Offline Cache Logic
  Future<void> _persistToDisk(String key, RouteResult result) async {
    try {
      // 🚀 CRITICAL UI FIX: Yield to the event loop for 200ms so the map can animate
      // the route drawing smoothly before we freeze the thread with heavy JSON encoding.
      await Future.delayed(const Duration(milliseconds: 200));

      final jsonStr = json.encode(result.toJson());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_route_$key', jsonStr);
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

    List<String>? congestionList;
    try {
      congestionList = [];
      bool foundAnyTraffic = false;

      final legs = route['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        final steps = legs[0]['steps'] as List?;

        if (steps != null && steps.isNotEmpty) {
          // 🚨 X-RAY DEBUG: Print the exact keys and data Ola is sending for the first maneuver
          debugPrint("🔍 X-RAY STEP JSON: ${steps[0].toString()}");

          for (var step in steps) {
            String segmentTraffic = "low"; // Default fallback

            // Dig into step-level travel advisory
            if (step['travel_advisory'] != null &&
                step['travel_advisory']['congestion'] != null) {
              segmentTraffic = step['travel_advisory']['congestion']
                  .toString()
                  .toLowerCase();
              foundAnyTraffic = true;
            }

            // Map this traffic value. (Since we decoded the high-res polyline,
            // we temporarily push this to a list. A full implementation would interpolate
            // this across the step's coordinate length).
            congestionList.add(segmentTraffic);
          }
        }
      }

      if (foundAnyTraffic) {
        debugPrint(
            "🟢 DEEP TRAFFIC SCAN: Found congestion data in steps! (${congestionList.length} segments)");
      } else {
        debugPrint(
            "🟡 DEEP TRAFFIC SCAN: No congestion data found in any steps (Likely no traffic at this hour).");
        congestionList = null; // Let the UI default to solid blue
      }
    } catch (e) {
      debugPrint("💥 DEEP TRAFFIC SCAN CRASH: $e");
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

    List<List<double>> rawCoords = [];
    if (encodedPolyline.isNotEmpty) {
      PolylinePoints polylinePoints = PolylinePoints();
      List<PointLatLng> result = polylinePoints.decodePolyline(encodedPolyline);
      rawCoords = result.map((p) => [p.latitude, p.longitude]).toList();
      
      // 🚀 Optimize: Douglas-Peucker Simplification
      // ~0.0001 is roughly 10 meters tolerance.
      rawCoords = _simplifyPath(rawCoords, 0.0001);
    }

    if (rawCoords.isEmpty) return null;

    final rawSteps = leg['steps'] as List<dynamic>? ?? [];
    final safeSteps = rawSteps.map((s) => s as Map<String, dynamic>).toList();
    String instruction = "Head to destination";
    if (safeSteps.isNotEmpty && safeSteps.first['html_instructions'] != null) {
      instruction = safeSteps.first['html_instructions']
          .toString()
          .replaceAll(RegExp(r'<[^>]*>'), '');
    }

    // Process traffic speed
    List<dynamic> gradientStops = [
      'interpolate',
      ['linear'],
      ['line-progress']
    ];
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
      'distanceKm': leg['distance'] / 1000,
      'durationMins': (leg['duration'] / 60).ceil(),
      'durationSeconds': (leg['duration'] as num).toDouble(),
      'steps': safeSteps,
      'firstInstruction': instruction,
      'gradientStops': gradientStops,
      'congestion': congestionList,
    };
  }

  static List<List<double>> _simplifyPath(List<List<double>> points, double tolerance) {
    if (points.length <= 2) return points;

    double maxDistance = 0.0;
    int index = 0;

    for (int i = 1; i < points.length - 1; i++) {
      double distance = _perpendicularDistance(points[i], points[0], points[points.length - 1]);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }

    if (maxDistance > tolerance) {
      List<List<double>> left = _simplifyPath(points.sublist(0, index + 1), tolerance);
      List<List<double>> right = _simplifyPath(points.sublist(index), tolerance);

      List<List<double>> result = [];
      result.addAll(left.sublist(0, left.length - 1));
      result.addAll(right);
      return result;
    } else {
      return [points[0], points[points.length - 1]];
    }
  }

  static double _perpendicularDistance(List<double> p, List<double> p1, List<double> p2) {
    double x = p[0];
    double y = p[1];
    double x1 = p1[0];
    double y1 = p1[1];
    double x2 = p2[0];
    double y2 = p2[1];

    double area = (0.5 * (x1 * y2 + y1 * x + x2 * y - x2 * y1 - x * y2 - x1 * y)).abs();
    double bottom = math.sqrt(math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2));

    if (bottom == 0) return 0.0;
    return area / bottom * 2.0;
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
