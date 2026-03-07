import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math'; 
import 'map_mode_controller.dart'; 

class MapLayerController {
  final MapLibreMapController map;
  Set<String> availableLayers = {};
  final Map<String, bool> _layerVisibilityCache = {};

  // 🚀 IDs for Ground Glow Layers
  static const String _pinSourceId = "premium-search-pin-source";
  static const String _pinCoreLayerId = "premium-search-pin-core";
  static const String _pinGlowLayerId = "premium-search-pin-glow";
  
  // 🚀 IDs for Vertical Standing Pin
  static const String _verticalPinImageId = "premium-neon-classic-pin";
  Symbol? _activeSearchPin;
  bool _isImageAdded = false;

  Timer? _hoverTimer;
  double _hoverTime = 0.0;
  
  // Cache to keep image alive in memory
  Uint8List? _cachedPinIcon;

  MapLayerController(this.map);

  Future<void> initLayerSystem() async {
    try {
      final layers = await map.getLayerIds();
      if (layers != null) {
        availableLayers = layers.map((e) => e.toString()).toSet();
        for (var layer in availableLayers) {
          _layerVisibilityCache[layer] = true; 
        }
      }
      await toggle3DVisibility(false); 
      await _ensurePinImage(); // Load the image early
    } catch (e) {
      debugPrint("Error loading style layers: $e");
    }
  }

  // =========================================================================
  // 🚀 FIX 1: THE CLEAN & SHARP CLASSIC NEON PIN (No messy outside glow)
  // =========================================================================
  Future<void> _ensurePinImage() async {
    if (_isImageAdded) return;
    try {
      _cachedPinIcon ??= await _createCrispNeonPin();
      await map.addImage(_verticalPinImageId, _cachedPinIcon!);
      _isImageAdded = true;
    } catch (e) {
      debugPrint("Failed to load custom pin image: $e");
    }
  }

  // Draws a mathematically perfect, classic location pin (Crisp, No Shadows)
  Future<Uint8List> _createCrispNeonPin() async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const size = Size(100, 100); 

    // 1. Solid Neon Cyan Fill
    final paintFill = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;

    // Classic Inverted-Drop Shape
    final path = Path();
    path.moveTo(50, 100); // Bottom sharp tip
    path.cubicTo(50, 65, 15, 60, 15, 35); // Left elegant curve
    path.arcToPoint(const Offset(85, 35), radius: const Radius.circular(35)); // Top round
    path.cubicTo(85, 60, 50, 65, 50, 100); // Right elegant curve

    canvas.drawPath(path, paintFill);

    final dotPaint = Paint()
      ..color = Colors.transparent
      ..blendMode = BlendMode.clear; 
    canvas.drawCircle(const Offset(50, 35), 14, dotPaint);

    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  bool layerExists(String id) => availableLayers.contains(id);

  Future<void> setLayerVisibleSafe(String layerId, bool visible) async {
    if (!layerExists(layerId) || _layerVisibilityCache[layerId] == visible) return;
    try {
      await map.setLayerVisibility(layerId, visible);
      _layerVisibilityCache[layerId] = visible;
    } catch (_) {}
  }

  Future<void> resetAllLayers() async {
    await applyModePreset(MapMode.explore);
  }

  Future<void> applyModePreset(MapMode mode) async {
    final poiLayers = availableLayers.where((l) => l.startsWith('poi') || l.contains('place')).toList();
    final transitLayers = availableLayers.where((l) => l.contains('transit') || l.contains('railway')).toList();

    dynamic poiFilter;
    dynamic transitFilter;
    bool showTraffic = false;

    if (mode == MapMode.explore) {
      poiFilter = null; 
      transitFilter = null; 
      showTraffic = false;
    } else if (mode == MapMode.driving) {
      poiFilter = ['any', ['==', ['get', 'class'], 'fuel'], ['==', ['get', 'class'], 'parking']];
      transitFilter = ['==', ['get', 'class'], 'none']; 
      showTraffic = true;
    } else if (mode == MapMode.transit) {
      poiFilter = ['any', ['==', ['get', 'class'], 'transit'], ['==', ['get', 'class'], 'railway']];
      transitFilter = null; 
      showTraffic = false;
    }

    for (var layer in poiLayers) {
      try { await map.setFilter(layer, poiFilter); } catch (_) {}
    }
    for (var layer in transitLayers) {
      try { await map.setFilter(layer, transitFilter); } catch (_) {}
    }
    for (var layer in availableLayers.where((l) => l.contains('traffic'))) {
      await setLayerVisibleSafe(layer, showTraffic);
    }
  }

  Future<void> toggle3DVisibility(bool show3D) async {
    if (layerExists("3d-buildings-premium")) {
      await setLayerVisibleSafe("3d-buildings-premium", show3D);
    }
    for (String layer in availableLayers.where((l) => l == 'building' || l == 'buildings')) {
      await setLayerVisibleSafe(layer, !show3D); 
    }
  }

  Future<void> updateBuildingExtrusion(double progress, bool isDark) async {
    if (!layerExists("3d-buildings-premium")) return;
    String buildingColor = isDark ? "#3A3A40" : "#E8E8E8"; 
    
    try {
      await map.setLayerProperties("3d-buildings-premium", FillExtrusionLayerProperties(
        fillExtrusionHeight: ["*", ["to-number", ["coalesce", ["get", "height"], ["get", "render_height"], 25.0]], progress],
        fillExtrusionOpacity: progress > 0.05 ? 0.95 : 0.0, 
        fillExtrusionColor: buildingColor, 
      ));
    } catch (_) {}
  }

  // =========================================================================
  // 🚀 SMALLER PIN + DIAMOND GLOW + GENTLE HOVER
  // =========================================================================

  Future<void> removeSearchPin() async {
    _stopHoverAnimation();
    try {
      if (_activeSearchPin != null) {
        await map.removeSymbol(_activeSearchPin!);
        _activeSearchPin = null;
      }
      await map.removeLayer(_pinGlowLayerId);
      await map.removeLayer(_pinCoreLayerId);
      await map.removeSource(_pinSourceId);
      
      _restoreContextualFocus(); 
    } catch (_) {}
  }

  Future<void> showSearchPin(LatLng target) async {
    await removeSearchPin(); 
    await fadePOIsTemporarily(); 
    await _ensurePinImage(); 

    try {
      final geoJson = {"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [target.longitude, target.latitude]}}]};
      await map.addGeoJsonSource(_pinSourceId, geoJson);

      // 1. THE "DIAMOND" GROUND GLOW (Cyan Aura)
      await map.addCircleLayer(_pinSourceId, _pinGlowLayerId, const CircleLayerProperties(
        circleColor: "#00E5FF", circleOpacity: 0.25, circleRadius: 18.0, circleBlur: 0.6, circlePitchAlignment: "map"
      ));

      // 2. THE GROUND CORE (White dot with neon border)
      await map.addCircleLayer(_pinSourceId, _pinCoreLayerId, const CircleLayerProperties(
        circleColor: "#FFFFFF", circleRadius: 5.0, circleStrokeWidth: 2.0, circleStrokeColor: "#00E5FF", circlePitchAlignment: "map"
      ));

      // 3. THE VERTICAL PIN
      _activeSearchPin = await map.addSymbol(
        SymbolOptions(
          geometry: target,
          iconImage: _isImageAdded ? _verticalPinImageId : 'default_poi', 
          iconAnchor: "bottom", 
          iconSize: _isImageAdded ? 0.70 : 1.5, 
          iconOffset: const Offset(0, -12), 
        )
      );

      // 3. START GENTLE HOVER
      _startHoverAnimation();

    } catch (e) {
      debugPrint("⚠️ Premium Pin Drawing Failed: $e");
    }
  }

  // 🚀 FIX 3: VERY GENTLE FLOATING ANIMATION
  void _startHoverAnimation() {
    _stopHoverAnimation();
    if (_activeSearchPin == null) return;

    _hoverTime = 0.0;
    _hoverTimer = Timer.periodic(const Duration(milliseconds: 32), (timer) async {
      _hoverTime += 0.15; 
      
      // Halka sa upar niche float karega (-8 aur -12 pixels ke beech)
      double yOffset = -10.0 + (sin(_hoverTime) * 3.0); 

      try {
        await map.updateSymbol(_activeSearchPin!, SymbolOptions(
          iconOffset: Offset(0.0, yOffset)
        ));
      } catch (_) {
        _stopHoverAnimation(); 
      }
    });
  }

  void _stopHoverAnimation() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
  }

  Future<void> fadePOIsTemporarily() async {
    final fadeLayers = availableLayers.where((l) => l.contains('poi') || (l.contains('label') && !l.contains('major')) || l.contains('transit')).toList();
    for (var layer in fadeLayers) {
      try { await map.setLayerProperties(layer, const SymbolLayerProperties(iconOpacity: 0.3, textOpacity: 0.3)); } catch (_) {}
    }
  }

  Future<void> _restoreContextualFocus() async {
    final fadeLayers = availableLayers.where((l) => l.contains('poi') || l.contains('label') || l.contains('transit')).toList();
    for (var layer in fadeLayers) {
      try { await map.setLayerProperties(layer, const SymbolLayerProperties(iconOpacity: 1.0, textOpacity: 1.0)); } catch (_) {}
    }
  }
}