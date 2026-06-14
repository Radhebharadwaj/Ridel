import 'package:maplibre_gl/maplibre_gl.dart';

/// 🎨 Apple-Level Visualizer: Handles 3D drop shadows, zoom interpolation, white halo casings, and gradients.
class RouteVisualizer {
  // ═══════════════════════════════════════════════════════════════════════════
  // LAYER IDs — Strict ordering for the visual stack
  // ═══════════════════════════════════════════════════════════════════════════
  static const String _sourceId = 'route-source';
  static const String _shadowLayerId = 'route-shadow';
  static const String _casingLayerId = 'route-casing';
  static const String _coreLayerId = 'route-layer';
  static const String _glowLayerId = 'route-glow';

  static String _safeColor(String? value, [String fallback = '#000000']) =>
      (value?.isNotEmpty == true ? value! : fallback);

  static double _safeDouble(double? value, double fallback) =>
      value != null && value > 0 ? value : fallback;

  /// Clears all route layers and the source from the map.
  static Future<void> clearRoute(MapLibreMapController? controller) async {
    if (controller == null) return;

    // Remove layers in reverse z-order (top → bottom)
    for (final layerId in [
      _glowLayerId,
      _coreLayerId,
      _casingLayerId,
      _shadowLayerId,
    ]) {
      try {
        await controller.removeLayer(layerId);
      } catch (_) {}
    }

    try {
      await controller.removeSource(_sourceId);
    } catch (_) {}
  }

  /// Draws a premium multi-layer route polyline.
  ///
  /// Visual Stack (bottom → top):
  /// 1. **Shadow** — Dark translucent wide line for depth
  /// 2. **Casing** — White/dark border for contrast against map tiles
  /// 3. **Core** — Neon cyan primary route line
  /// 4. **Glow** — Translucent wide overlay for soft neon bloom
  static Future<void> drawRoute(
    MapLibreMapController? controller,
    List<LatLng> coordinates,
    dynamic theme, {
    LatLng? origin,
    LatLng? destination,
  }) async {
    if (controller == null || coordinates.isEmpty) return;

    // 1. Clean up old route safely
    await clearRoute(controller);

    // 2. Strict GeoJSON formatting: MUST be [Lng, Lat]
    final List<List<double>> geometryCoords =
        coordinates.map((c) => [c.longitude, c.latitude]).toList();

    final Map<String, dynamic> geoJsonData = {
      "type": "Feature",
      "properties": {},
      "geometry": {"type": "LineString", "coordinates": geometryCoords}
    };

    // 3. Inject GeoJSON Source
    await controller.addGeoJsonSource(_sourceId, geoJsonData);

    // 4. Determine theme-aware colors
    final bool isDark = theme == true ||
        (theme != null && theme.toString().toLowerCase().contains('dark'));

    final String casingColor = isDark ? '#FFFFFF' : '#000000';
    final double casingOpacity = isDark ? 0.25 : 0.12;

    // ──────────────────────────────────────────────────────────────────────
    // LAYER 1: Shadow — Adds depth and lifts the route off the map
    // ──────────────────────────────────────────────────────────────────────
    await controller.addLineLayer(
      _sourceId,
      _shadowLayerId,
      LineLayerProperties(
        lineColor: _safeColor('#000000'),
        lineWidth: _safeDouble(12.0, 8.0),
        lineOpacity: _safeDouble(isDark ? 0.35 : 0.15, 0.15),
        lineCap: 'round',
        lineJoin: 'round',
        lineBlur: _safeDouble(8.0, 4.0), // Soft shadow blur
        lineTranslate: [0, 3], // Offset downwards for 3D effect
      ),
    );

    // ──────────────────────────────────────────────────────────────────────
    // LAYER 2: Casing — White/dark border for contrast
    // ──────────────────────────────────────────────────────────────────────
    await controller.addLineLayer(
      _sourceId,
      _casingLayerId,
      LineLayerProperties(
        lineColor: _safeColor(casingColor),
        lineWidth: _safeDouble(8.0, 5.0),
        lineOpacity: _safeDouble(casingOpacity, 0.15),
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // ──────────────────────────────────────────────────────────────────────
    // LAYER 3: Core — The primary neon cyan route line
    // ──────────────────────────────────────────────────────────────────────
    await controller.addLineLayer(
      _sourceId,
      _coreLayerId,
      LineLayerProperties(
        lineColor: _safeColor('#00E5FF'), // Ridel Neon Cyan
        lineWidth: _safeDouble(5.0, 5.0),
        lineOpacity: _safeDouble(1.0, 1.0),
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );

    // ──────────────────────────────────────────────────────────────────────
    // LAYER 4: Glow — Soft neon bloom effect
    // ──────────────────────────────────────────────────────────────────────
    await controller.addLineLayer(
      _sourceId,
      _glowLayerId,
      LineLayerProperties(
        lineColor: _safeColor('#00E5FF'),
        lineWidth: _safeDouble(14.0, 10.0),
        lineOpacity: _safeDouble(0.12, 0.12),
        lineCap: 'round',
        lineJoin: 'round',
        lineBlur: _safeDouble(6.0, 4.0),
      ),
    );
  }

  /// Dynamically updates the route source without redrawing the layers.
  static Future<void> updateRouteSource(
    MapLibreMapController? controller,
    List<LatLng> coordinates,
  ) async {
    if (controller == null || coordinates.isEmpty) return;

    final List<List<double>> geometryCoords =
        coordinates.map((c) => [c.longitude, c.latitude]).toList();

    final Map<String, dynamic> geoJsonData = {
      "type": "Feature",
      "properties": {},
      "geometry": {"type": "LineString", "coordinates": geometryCoords}
    };

    try {
      await controller.setGeoJsonSource(_sourceId, geoJsonData);
    } catch (_) {}
  }
}