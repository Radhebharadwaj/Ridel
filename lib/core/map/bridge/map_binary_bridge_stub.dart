import 'dart:typed_data';
import 'package:maplibre_gl/maplibre_gl.dart';

class MapBinaryBridge {
  static bool captureMapInstance() => false;

  static bool get isReady => false;

  static Float64List latLngToBuffer(List<LatLng> points) {
    return Float64List(0);
  }

  static bool setRouteFromBuffer({
    required List<LatLng> points,
    required String sourceId,
    List<String>? congestion,
  }) {
    return false;
  }

  static bool setSimpleRouteFromBuffer({
    required List<LatLng> points,
    required String sourceId,
    int routeIndex = 0,
  }) {
    return false;
  }

  static void updatePuck(double lng, double lat, double bearing) {}
}
