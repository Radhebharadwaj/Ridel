import 'dart:async';
import 'package:maplibre_gl/maplibre_gl.dart';

class RouteWorkerBridge {
  static void initialize() {}

  static Future<Map<String, dynamic>> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required String mode,
    required String apiKey,
    List<LatLng>? waypoints,
  }) {
    return Future.error(Exception("Web Worker route calculation is not supported on this platform."));
  }

  static void dispose() {}
}
