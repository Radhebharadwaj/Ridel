import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:math';

class MapNavigationController {
  MapLibreMapController? map; // Initialize later from Engine
  List<LatLng>? _currentRoute;
  String? _routeId;
  DateTime? _routeTimestamp;
  
  static const String routeSourceId = "premium-route-source";
  static const String routeLayerId = "premium-route-layer";
  static const String routeCasingLayerId = "premium-route-casing";

  // 🔗 Call this from MapEngine to link the map controller
  void init(MapLibreMapController controller) {
    map = controller;
  }

  Future<String?> plotRoute({
    required LatLng start,
    required LatLng end,
    String provider = 'osrm', 
    String mode = 'driving', 
  }) async {
    if (map == null) return null;

    // 🚀 IN FUTURE: Call your RoutingService here. 
    // For now, drawing a dummy straight line path for visual test
    _currentRoute = [start, end]; 
    _routeId = "route_${DateTime.now().millisecondsSinceEpoch}";
    
    await _drawRouteOnMap(_currentRoute!);
    return _routeId;
  }

  // 🎨 Draws a premium glowing line on the map
  Future<void> _drawRouteOnMap(List<LatLng> points) async {
    if (map == null) return;
    
    try {
      // 1. Convert points to GeoJSON LineString
      final geoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": points.map((p) => [p.longitude, p.latitude]).toList(),
            }
          }
        ]
      };

      // 2. Remove old route if exists
      await clearRoute();

      // 3. Add Data Source
      await map!.addGeoJsonSource(routeSourceId, geoJson);

      // 4. Add Outer Glow / Casing Layer (Darker Blue)
      await map!.addLineLayer(routeSourceId, routeCasingLayerId, LineLayerProperties(
        lineColor: "#0055FF",
        lineWidth: ["interpolate", ["linear"], ["zoom"], 10, 4.0, 18, 12.0],
        lineCap: "round",
        lineJoin: "round",
      ));

      // 5. Add Inner Core Layer (Bright Cyan)
      await map!.addLineLayer(routeSourceId, routeLayerId, LineLayerProperties(
        lineColor: "#00E5FF",
        lineWidth: ["interpolate", ["linear"], ["zoom"], 10, 2.0, 18, 6.0],
        lineCap: "round",
        lineJoin: "round",
      ));

    } catch (e) {
      debugPrint("⚠️ Route drawing failed: $e");
    }
  }

  Future<void> clearRoute() async {
    _currentRoute = null;
    if (map == null) return;
    
    try {
      if (await map!.getLayerIds() != null) {
        await map!.removeLayer(routeLayerId);
        await map!.removeLayer(routeCasingLayerId);
        await map!.removeSource(routeSourceId);
      }
    } catch (_) {}
  }

  double? get routeDistanceKm {
    if (_currentRoute == null || _currentRoute!.length < 2) return null;
    double total = 0;
    for (int i = 0; i < _currentRoute!.length - 1; i++) {
      total += _haversineDistance(_currentRoute![i].latitude, _currentRoute![i].longitude, _currentRoute![i+1].latitude, _currentRoute![i+1].longitude);
    }
    return total;
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; 
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
    return R * (2 * atan2(sqrt(a), sqrt(1 - a)));
  }
}