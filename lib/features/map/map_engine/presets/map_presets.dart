import 'package:flutter/physics.dart';

/// Defines the strict UI, Camera Physics, and Visual Configuration contract
/// for all map modes. Immutable – zero mutable state, zero memory leaks.
abstract class MapPreset {
  // ─── Map Style & Visual Identity ───
  /// MapLibre style URL – each mode can load a distinct visual theme
  /// (e.g., navigation‑optimized, high‑contrast transit, elegant exploration)
  String get mapStyleUrl;

  // ─── Cinematic Camera Physics ───
  double get targetZoom;
  double get targetPitch;
  double get targetBearing;
  double get minZoom;
  double get maxZoom;
  double get minPitch;
  double get maxPitch;

  /// Spring simulation parameters for mode transitions.
  /// Driving uses stiffer spring for snappy response; Explore uses softer.
  SpringDescription get cameraSpring;

  // ─── Gesture Permissions (prevents accidental UI breakage) ───
  bool get allowPitchGesture; // user can tilt the map?
  bool get allowRotateGesture; // user can rotate the map?
  bool get allowZoomGesture;

  // ─── UI Overlays & Widgets ───
  bool get showTraffic;
  bool get show3DBuildings;
  bool get showCompass;
  bool get showUserLocation;
  bool get showTrafficIncidents; // 🚧 accident / road closure overlays
  bool get showSpeedCameras; // 📸 speed camera markers

  // 🎯 MapLibre Native Layer Filter Expressions
  List<dynamic>? get poiFilter;
  List<dynamic>? get transitFilter;

  /// Explicitly enable specific MapLibre layer groups (e.g., '3d-buildings-premium')
  List<String> get enabledLayerGroups;
}

// ══════════════════════════════════════════════════════
// 🌍 EXPLORE MODE – Elegant Discovery
// ══════════════════════════════════════════════════════
class ExplorePreset extends MapPreset {
  @override
  String get mapStyleUrl =>
      'mapbox://styles/mapbox/streets-v12'; // classic exploration

  @override
  double get targetZoom => 14.5;
  @override
  double get targetPitch => 0.0;
  @override
  double get targetBearing => 0.0;
  @override
  double get minZoom => 3.0;
  @override
  double get maxZoom => 22.0;
  @override
  double get minPitch => 0.0; // locked flat
  @override
  double get maxPitch => 0.0;

  @override
  SpringDescription get cameraSpring => const SpringDescription(
      mass: 1.0, stiffness: 40.0, damping: 14.0); // soft, graceful

  @override
  bool get allowPitchGesture => false; // keep flat experience
  @override
  bool get allowRotateGesture => true;
  @override
  bool get allowZoomGesture => true;

  @override
  bool get showTraffic => false;
  @override
  bool get show3DBuildings => false;
  @override
  bool get showCompass => true;
  @override
  bool get showUserLocation => true;
  @override
  bool get showTrafficIncidents => false;
  @override
  bool get showSpeedCameras => false;

  @override
  List<dynamic>? get poiFilter => null; // show all POIs
  @override
  List<dynamic>? get transitFilter => null;
  @override
  List<String> get enabledLayerGroups =>
      ['poi-labels', 'place-labels', 'road-labels'];
}

// ══════════════════════════════════════════════════════
// 🚗 DRIVING MODE – Focused, Immersive Navigation
// ══════════════════════════════════════════════════════
class DrivingPreset extends MapPreset {
  @override
  String get mapStyleUrl =>
      'mapbox://styles/mapbox/navigation-day-v1'; // crisp navigation style

  @override
  double get targetZoom => 17.8;
  @override
  double get targetPitch => 60.0;
  @override
  double get targetBearing => 0.0; // will follow heading
  @override
  double get minZoom => 12.0;
  @override
  double get maxZoom => 22.0;
  @override
  double get minPitch => 45.0;
  @override
  double get maxPitch => 70.0;

  @override
  SpringDescription get cameraSpring => const SpringDescription(
      mass: 1.0, stiffness: 65.0, damping: 12.0); // tight, responsive

  @override
  bool get allowPitchGesture => true; // but restricted to 45‑70°
  @override
  bool get allowRotateGesture => true;
  @override
  bool get allowZoomGesture => true;

  @override
  bool get showTraffic => true;
  @override
  bool get show3DBuildings => true; // extrude for depth
  @override
  bool get showCompass => true;
  @override
  bool get showUserLocation => true;
  @override
  bool get showTrafficIncidents => true; // road closures / accidents
  @override
  bool get showSpeedCameras => true; // speed camera markers

  @override
  List<dynamic>? get poiFilter => [
        'any',
        [
          '==',
          ['get', 'class'],
          'fuel'
        ],
        [
          '==',
          ['get', 'class'],
          'parking'
        ],
        [
          '==',
          ['get', 'class'],
          'motorway_junction'
        ],
      ];

  @override
  List<dynamic>? get transitFilter => [
        '==',
        ['get', 'class'],
        'none'
      ];

  @override
  List<String> get enabledLayerGroups =>
      ['3d-buildings-premium', 'traffic-incidents', 'speed-cameras'];
}

// ══════════════════════════════════════════════════════
// 🚇 TRANSIT MODE – Clean, High‑Contrast Network View
// ══════════════════════════════════════════════════════
class TransitPreset extends MapPreset {
  @override
  String get mapStyleUrl =>
      'mapbox://styles/mapbox/light-v11'; // bright, minimal background

  @override
  double get targetZoom => 13.5;
  @override
  double get targetPitch => 0.0;
  @override
  double get targetBearing => 0.0;
  @override
  double get minZoom => 10.0;
  @override
  double get maxZoom => 20.0;
  @override
  double get minPitch => 0.0;
  @override
  double get maxPitch => 15.0; // subtle perspective allowed

  @override
  SpringDescription get cameraSpring => const SpringDescription(
      mass: 1.0, stiffness: 50.0, damping: 15.0); // balanced

  @override
  bool get allowPitchGesture => true;
  @override
  bool get allowRotateGesture => false; // keep North‑up orientation
  @override
  bool get allowZoomGesture => true;

  @override
  bool get showTraffic => false;
  @override
  bool get show3DBuildings => false;
  @override
  bool get showCompass => true;
  @override
  bool get showUserLocation => true;
  @override
  bool get showTrafficIncidents => false;
  @override
  bool get showSpeedCameras => false;

  @override
  List<dynamic>? get poiFilter => [
        'any',
        [
          '==',
          ['get', 'class'],
          'transit_station'
        ],
        [
          '==',
          ['get', 'class'],
          'railway'
        ],
        [
          '==',
          ['get', 'class'],
          'bus_station'
        ],
        [
          '==',
          ['get', 'class'],
          'tram_stop'
        ],
      ];

  @override
  List<dynamic>? get transitFilter => null; // show all transit lines

  @override
  List<String> get enabledLayerGroups =>
      ['transit-lines', 'transit-stations', 'transit-labels'];
}
