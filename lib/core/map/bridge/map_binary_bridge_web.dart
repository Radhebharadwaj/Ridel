// Ridel HPC Binary Bridge - Dart Side
//
// Zero-copy binary data pipeline for MapLibre route injection.
// Converts Dart coordinate lists to Float64List and passes them
// directly to the JS bridge via dart:js_interop, bypassing JSON.

import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

// ══════════════════════════════════════════════════════════════
// JS INTEROP BINDINGS
// ══════════════════════════════════════════════════════════════

@JS('window.__ridel_captureMap')
external JSBoolean? _jsCaptureMap(JSString elementId);

@JS('window.__ridel_setRouteFromBuffer')
external JSBoolean? _jsSetRouteFromBuffer(
  JSFloat64Array coordBuffer,
  JSNumber pointCount,
  JSString sourceId,
  JSString? congestionJson,
);

@JS('window.__ridel_setSimpleRouteFromBuffer')
external JSBoolean? _jsSetSimpleRouteFromBuffer(
  JSFloat64Array coordBuffer,
  JSNumber pointCount,
  JSString sourceId,
  JSNumber routeIndex,
);

@JS('window.__ridel_updatePuck')
external void _jsUpdatePuck(
  JSNumber lng,
  JSNumber lat,
  JSNumber bearing,
);

// ══════════════════════════════════════════════════════════════
// PUBLIC API
// ══════════════════════════════════════════════════════════════

class MapBinaryBridge {
  static bool _isCaptured = false;

  /// Must be called once after MapLibre's onMapCreated fires.
  /// Captures the MapLibre JS map instance for direct access.
  static bool captureMapInstance() {
    if (!kIsWeb) return false;
    try {
      final result = _jsCaptureMap('map'.toJS);
      _isCaptured = result?.toDart ?? false;
      return _isCaptured;
    } catch (e) {
      debugPrint('[RIDEL-HPC] captureMapInstance error: $e');
      return false;
    }
  }

  /// Whether the bridge has captured a valid MapLibre instance.
  static bool get isReady => _isCaptured;

  /// Converts a List<LatLng> to a flat Float64List in [lng, lat] GeoJSON order.
  /// This buffer is transferred to JS as a zero-copy Float64Array.
  static Float64List latLngToBuffer(List<LatLng> points) {
    final buffer = Float64List(points.length * 2);
    for (int i = 0; i < points.length; i++) {
      buffer[i * 2] = points[i].longitude; // GeoJSON uses [lng, lat]
      buffer[i * 2 + 1] = points[i].latitude;
    }
    return buffer;
  }

  /// Injects a route with congestion data into MapLibre via binary buffer.
  /// Falls back to returning false if the bridge isn't captured.
  static bool setRouteFromBuffer({
    required List<LatLng> points,
    required String sourceId,
    List<String>? congestion,
  }) {
    if (!kIsWeb || !_isCaptured) return false;
    try {
      final buffer = latLngToBuffer(points);
      final congestionJs = congestion != null ? json.encode(congestion).toJS : null;
      final result = _jsSetRouteFromBuffer(
        buffer.toJS,
        points.length.toJS,
        sourceId.toJS,
        congestionJs,
      );
      return result?.toDart ?? false;
    } catch (e) {
      debugPrint('[RIDEL-HPC] setRouteFromBuffer error: $e');
      return false;
    }
  }

  /// Injects a simple (non-congestion) route into MapLibre via binary buffer.
  static bool setSimpleRouteFromBuffer({
    required List<LatLng> points,
    required String sourceId,
    int routeIndex = 0,
  }) {
    if (!kIsWeb || !_isCaptured) return false;
    try {
      final buffer = latLngToBuffer(points);
      final result = _jsSetSimpleRouteFromBuffer(
        buffer.toJS,
        points.length.toJS,
        sourceId.toJS,
        routeIndex.toJS,
      );
      return result?.toDart ?? false;
    } catch (e) {
      debugPrint('[RIDEL-HPC] setSimpleRouteFromBuffer error: $e');
      return false;
    }
  }

  /// Updates the navigation puck position via direct JS call.
  /// Much faster than Dart GeoJSON → JSON → JS for 1Hz GPS updates.
  static void updatePuck(double lng, double lat, double bearing) {
    if (!kIsWeb || !_isCaptured) return;
    try {
      _jsUpdatePuck(lng.toJS, lat.toJS, bearing.toJS);
    } catch (e) {
      debugPrint('[RIDEL-HPC] updatePuck error: $e');
    }
  }
}
