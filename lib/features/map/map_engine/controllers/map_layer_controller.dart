import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:ridel/features/map/models/place_model.dart';

import 'map_mode_controller.dart';

class MapLayerController {
  MapLibreMapController? _map;
  MapLibreMapController get map =>
      _map ?? (throw StateError("Map accessed after dispose"));

  Set<String> availableLayers = {};
  final Map<String, bool> _layerVisibilityCache = {};

  List<String> _poiLayers = [];
  List<String> _transitLayers = [];
  List<String> _trafficLayers = [];
  List<String> _buildingLayers = [];
  List<String> _fadeLayers = [];

  static const String _pinSourceId = "apple-premium-pin-source";

  // Red Pulsing Dot layers
  static const String _redGlowLayerId = "apple-premium-red-glow";
  static const String _redStaticAuraLayerId = "apple-premium-red-static-aura";
  static const String _redBorderLayerId = "apple-premium-red-border";
  static const String _redCoreLayerId = "apple-premium-red-core";

  static const String _routeSourceId = "active-route-source";
  static const String _routeCasingLayerId = "active-route-casing";
  static const String _routeLineLayerId = "active-route-line";

  // Blue Pulsing Dot layers (For User Location)
  static const String _blueGlowLayerId = "apple-premium-pin-glow";
  static const String _blueBorderLayerId = "apple-premium-pin-border";
  static const String _blueCoreLayerId = "apple-premium-pin-core";

  bool _isDrawingRoute = false;

  MapLayerController(MapLibreMapController initMap) {
    _map = initMap;
  }

  void dispose() {
    availableLayers.clear();
    _layerVisibilityCache.clear();
    _poiLayers.clear();
    _transitLayers.clear();
    _trafficLayers.clear();
    _buildingLayers.clear();
    _fadeLayers.clear();

    _map = null;
  }

  Future<void> initLayerSystem() async {
    if (_map == null) return;
    try {
      final layers = await _map!.getLayerIds();
      if (layers.isNotEmpty) {
        availableLayers = layers.map((e) => e.toString()).toSet();
        for (var layer in availableLayers) {
          _layerVisibilityCache[layer] = true;
        }

        _poiLayers = availableLayers
            .where((l) => l.startsWith('poi') || l.contains('place'))
            .toList();
        _transitLayers = availableLayers
            .where((l) => l.contains('transit') || l.contains('railway'))
            .toList();
        _trafficLayers =
            availableLayers.where((l) => l.contains('traffic')).toList();
        _buildingLayers = availableLayers
            .where((l) => l == 'building' || l == 'buildings')
            .toList();
        _fadeLayers = availableLayers
            .where((l) =>
                l.contains('poi') ||
                (l.contains('label') && !l.contains('major')) ||
                l.contains('transit'))
            .toList();
      }
      await toggle3DVisibility(false);
    } catch (e) {
      debugPrint("Error loading style layers: $e");
    }
  }

  static Map<String, dynamic> _buildRouteGeoJson(
      List<List<double>> geoJsonCoordinates) {
    return {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {"type": "LineString", "coordinates": geoJsonCoordinates}
        }
      ]
    };
  }

  static Map<String, dynamic> _buildPointGeoJson(Map<String, dynamic> args) {
    final double lat = args['lat'];
    final double lng = args['lng'];
    return {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [lng, lat]
          }
        }
      ]
    };
  }

  Future<void> drawRoute(List<LatLng> points) async {
    if (_isDrawingRoute || _map == null) return;
    _isDrawingRoute = true;

    try {
      await removeRoute();

      if (points.isNotEmpty) {
        debugPrint(
            "🔍 MAP LAYER CONTROLLER AUDIT (1st Point before GeoJSON): Lat=${points.first.latitude}, Lng=${points.first.longitude}");
      }

      final geoJsonCoordinates = points.map((point) {
        return [point.longitude, point.latitude];
      }).toList();

      final geoJson =
          await Isolate.run(() => _buildRouteGeoJson(geoJsonCoordinates));

      if (_map == null) return;
      await _map!.addGeoJsonSource(_routeSourceId, geoJson);

      await _map!.addLineLayer(
        _routeSourceId,
        _routeCasingLayerId,
        const LineLayerProperties(
          lineColor: "#111111",
          lineWidth: 8.0,
          lineJoin: "round",
          lineCap: "round",
        ),
      );

      await _map!.addLineLayer(
        _routeSourceId,
        _routeLineLayerId,
        const LineLayerProperties(
          lineColor: "#00E5FF",
          lineWidth: 5.0,
          lineJoin: "round",
          lineCap: "round",
        ),
      );

      await _map!.animateCamera(CameraUpdate.newLatLngBounds(
          _calculateBounds(points),
          left: 50,
          right: 50,
          top: 100,
          bottom: 400));
    } catch (e) {
      debugPrint("Route draw failed: $e");
    } finally {
      _isDrawingRoute = false;
    }
  }

  Future<void> removeRoute() async {
    if (_map == null) return;
    try {
      if (layerExists(_routeLineLayerId)) {
        await _map!.removeLayer(_routeLineLayerId);
      }
      if (layerExists(_routeCasingLayerId)) {
        await _map!.removeLayer(_routeCasingLayerId);
      }
      await _map!.removeSource(_routeSourceId);
    } catch (_) {}
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
        southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  Future<void> _drawPremiumRedPin(LatLng target, PlaceModel? place) async {
    if (_map == null) return;
    Color pinColor = const Color(0xFFFF3B30);

    if (place != null &&
        place.theme.color.toARGB32() != 0xFFFF5252 &&
        place.theme.color.toARGB32() != 0 &&
        place.theme.color.toARGB32() != 0xFFFFFFFF) {
      pinColor = place.theme.color;
    }

    String hexColor =
        '#${pinColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    try {
      final geoJson = await Isolate.run(() => _buildPointGeoJson({
            'lat': target.latitude,
            'lng': target.longitude,
          }));

      if (_map == null) return;
      await _map!.addGeoJsonSource(_pinSourceId, geoJson);

      await _map!.addCircleLayer(
          _pinSourceId,
          _redGlowLayerId,
          CircleLayerProperties(
              circleColor: hexColor,
              circleOpacity: 0.2,
              circleRadius: 18.0,
              circlePitchAlignment: "map",
              circleStrokeWidth: 0));

      await _map!.addCircleLayer(
          _pinSourceId,
          _redStaticAuraLayerId,
          CircleLayerProperties(
              circleColor: hexColor,
              circleOpacity: 0.15,
              circleRadius: 14.0,
              circlePitchAlignment: "map",
              circleStrokeWidth: 0));

      await _map!.addCircleLayer(
          _pinSourceId,
          _redBorderLayerId,
          const CircleLayerProperties(
              circleColor: "#FFFFFF",
              circleOpacity: 1.0,
              circleRadius: 10.0,
              circlePitchAlignment: "map",
              circleStrokeWidth: 0));

      await _map!.addCircleLayer(
          _pinSourceId,
          _redCoreLayerId,
          CircleLayerProperties(
              circleColor: hexColor,
              circleOpacity: 1.0,
              circleRadius: 7.5,
              circlePitchAlignment: "map",
              circleStrokeWidth: 0));
    } catch (e) {
      debugPrint("⚠️ Red Pulse Drawing Failed: $e");
    }
  }

  Future<void> _drawBluePulseDot(LatLng target) async {
    if (_map == null) return;
    String hexColor = "#0A84FF";
    try {
      final geoJson = await Isolate.run(() => _buildPointGeoJson({
            'lat': target.latitude,
            'lng': target.longitude,
          }));

      if (_map == null) return;
      await _map!.addGeoJsonSource(_pinSourceId, geoJson);

      await _map!.addCircleLayer(
          _pinSourceId,
          _blueGlowLayerId,
          CircleLayerProperties(
              circleColor: hexColor,
              circleOpacity: 0.3,
              circleRadius: 25.0,
              circlePitchAlignment: "map",
              circleStrokeWidth: 0));

      await _map!.addCircleLayer(
          _pinSourceId,
          _blueBorderLayerId,
          const CircleLayerProperties(
              circleColor: "#FFFFFF",
              circleOpacity: 1.0,
              circleRadius: 10.0,
              circlePitchAlignment: "map",
              circleStrokeWidth: 0.5,
              circleStrokeColor: "#000000",
              circleStrokeOpacity: 0.15));

      await _map!.addCircleLayer(
          _pinSourceId,
          _blueCoreLayerId,
          CircleLayerProperties(
              circleColor: hexColor,
              circleOpacity: 1.0,
              circleRadius: 7.0,
              circlePitchAlignment: "map",
              circleStrokeWidth: 0));

      // The pulsing glow will be handled via a Flutter CustomPaint Overlay
      // in the widget tree to avoid method channel flooding.
    } catch (e) {
      debugPrint("⚠️ Blue Pulse Drawing Failed: $e");
    }
  }

  bool layerExists(String id) => availableLayers.contains(id);

  Future<void> setLayerVisibleSafe(String layerId, bool visible) async {
    if (_map == null ||
        !layerExists(layerId) ||
        _layerVisibilityCache[layerId] == visible) {
      return;
    }
    try {
      await _map!.setLayerVisibility(layerId, visible);
      _layerVisibilityCache[layerId] = visible;
    } catch (_) {}
  }

  Future<void> resetAllLayers() async {
    if (_map == null) return;
    for (var layer in _poiLayers) {
      try {
        await _map!.setFilter(layer, null);
      } catch (_) {}
    }
  }

  Future<void> applyCustomToggles(MapModeController mode) async {
    for (var layer in _poiLayers) {
      await setLayerVisibleSafe(layer, mode.showPOIs.value);
    }
    for (var layer in _transitLayers) {
      await setLayerVisibleSafe(layer, mode.showTransitLayer.value);
    }
    for (var layer in _trafficLayers) {
      await setLayerVisibleSafe(layer, mode.showTraffic.value);
    }
    await toggle3DVisibility(mode.currentMode.value == MapMode.city3d);
  }

  Future<void> toggle3DVisibility(bool show3D) async {
    if (layerExists("3d-buildings-premium")) {
      await setLayerVisibleSafe("3d-buildings-premium", show3D);
    }
    for (String layer in _buildingLayers) {
      await setLayerVisibleSafe(layer, !show3D);
    }
  }

  Future<void> updateBuildingExtrusion(double progress, bool isDark) async {
    if (_map == null || !layerExists("3d-buildings-premium")) return;
    String buildingColor = isDark ? "#3A3A40" : "#E8E8E8";
    try {
      await _map!.setLayerProperties(
          "3d-buildings-premium",
          FillExtrusionLayerProperties(
            fillExtrusionHeight: [
              "*",
              [
                "to-number",
                [
                  "coalesce",
                  ["get", "height"],
                  ["get", "render_height"],
                  25.0
                ]
              ],
              progress
            ],
            fillExtrusionOpacity: progress > 0.05 ? 0.95 : 0.0,
            fillExtrusionColor: buildingColor,
          ));
    } catch (_) {}
  }

  Future<void> removeSearchPin() async {
    if (_map == null) return;
    try {
      await _map!.removeLayer(_blueCoreLayerId);
      await _map!.removeLayer(_blueBorderLayerId);
      await _map!.removeLayer(_blueGlowLayerId);
      await _map!.removeLayer(_redCoreLayerId);
      await _map!.removeLayer(_redBorderLayerId);
      await _map!.removeLayer(_redStaticAuraLayerId);
      await _map!.removeLayer(_redGlowLayerId);
      await _map!.removeSource(_pinSourceId);
    } catch (_) {}

    try {
      await _restoreContextualFocus();
    } catch (_) {}
  }

  Future<void> showSearchPin(LatLng target, {PlaceModel? place}) async {
    await removeSearchPin();
    await fadePOIsTemporarily();

    bool isUserLocation = place != null &&
        (place.name == "Current Location" ||
            place.name == "My Location" ||
            place.name == "Locating...");

    if (isUserLocation) {
      await _drawBluePulseDot(target);
    } else {
      await _drawPremiumRedPin(target, place);
    }
  }

  Future<void> fadePOIsTemporarily() async {
    if (_map == null) return;
    for (var layer in _fadeLayers) {
      try {
        await _map!.setLayerProperties(layer,
            const SymbolLayerProperties(iconOpacity: 0.3, textOpacity: 0.3));
      } catch (_) {}
    }
  }

  Future<void> _restoreContextualFocus() async {
    if (_map == null) return;
    for (var layer in _fadeLayers) {
      try {
        await _map!.setLayerProperties(layer,
            const SymbolLayerProperties(iconOpacity: 1.0, textOpacity: 1.0));
      } catch (_) {}
    }
  }

  Future<void> filterNearbyCategory(List<String> targetClasses) async {
    if (_map == null) return;
    if (targetClasses.isEmpty) {
      for (var layer in _poiLayers) {
        try {
          await _map!.setFilter(layer, null);
        } catch (_) {}
      }
      return;
    }
    List<dynamic> filterExpression = ['any'];
    for (var category in targetClasses) {
      filterExpression.add([
        '==',
        ['get', 'class'],
        category
      ]);
    }
    for (var layer in _poiLayers) {
      try {
        await _map!.setFilter(layer, filterExpression);
      } catch (e) {
        debugPrint("Filter failed on layer $layer: $e");
      }
    }
  }
}
