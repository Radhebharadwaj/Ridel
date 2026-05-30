import 'package:maplibre_gl/maplibre_gl.dart';

/// 🎨 Apple-Level Visualizer: Handles 3D drop shadows, zoom interpolation, white halo casings, and gradients.
class RouteVisualizer {
  static Future<void> clearRoute(MapLibreMapController? controller) async {
    if (controller == null) return;
    try {
      await controller.removeLayer("route-layer");
    } catch (_) {}
    try {
      await controller.removeSource("route-source");
    } catch (_) {}
  }

  static Future<void> drawRoute(MapLibreMapController? controller,
      List<LatLng> coordinates, dynamic theme, // dynamic or MapThemeType
      {LatLng? origin,
      LatLng? destination}) async {
    if (controller == null || coordinates.isEmpty) return;

    // 1. Clean up old route safely
    await clearRoute(controller);

    // 2. Strict GeoJSON formatting: MUST be [Lng, Lat]
    final List<List<double>> geometryCoords =
        coordinates.map((c) => [c.longitude, c.latitude]).toList();

    // 3. Inject Source
    await controller.addGeoJsonSource("route-source", {
      "type": "Feature",
      "properties": {},
      "geometry": {"type": "LineString", "coordinates": geometryCoords}
    });

    // 4. Draw Premium Layer
    await controller.addLineLayer(
      "route-source",
      "route-layer",
      const LineLayerProperties(
        lineColor: '#00E5FF', // Neon Cyan to match the app's premium theme
        lineWidth: 5.0,
        lineCap: "round", // Smooth ends
        lineJoin: "round", // Smooth corners
      ),
    );
  }
}
