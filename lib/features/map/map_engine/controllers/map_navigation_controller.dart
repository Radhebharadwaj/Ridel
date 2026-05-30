import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/features/map/services/route_engine_service.dart';

import 'map_camera_controller.dart';

class MapNavigationController {
  // ───── Granular Reactive Notifiers (UI Layer) ─────
  final ValueNotifier<bool> isNavigating = ValueNotifier(false);
  final ValueNotifier<String> currentInstruction =
      ValueNotifier('Head towards the route');
  final ValueNotifier<double> distanceToNextTurn = ValueNotifier(0.0);
  final ValueNotifier<double> remainingDistance = ValueNotifier(0.0);
  final ValueNotifier<double> remainingDuration = ValueNotifier(0.0);
  final ValueNotifier<int> currentStepIndexNotifier = ValueNotifier(0);
  final ValueNotifier<String?> maneuverIcon = ValueNotifier(null);

  // 🧭 Compass & Bearing States
  final ValueNotifier<double> currentBearing = ValueNotifier(0.0);
  final ValueNotifier<bool> isDeviatedFromNorth = ValueNotifier(false);

  RouteResult? _activeRoute;
  int _currentStepIndex = 0;

  // ───── Pre‑computed Instruction Cache (Thread‑safe) ─────
  List<String> _parsedInstructions = [];
  List<String> _maneuverIcons = [];
  List<LatLng> _stepStartLocations = []; // Needed for Cross-Track error
  List<LatLng> _stepEndLocations = [];
  List<double> _stepDistances = [];
  List<double> _stepDurations = [];

  // ───── External Controllers ─────
  MapCameraController? _cameraController;

  // ───── Off‑route detection ─────
  static const double offRouteDeadZoneMeters = 25.0; // Cross-track tolerance
  DateTime? _lastOffRouteCheck;
  static const Duration offRouteThrottle = Duration(seconds: 4);
  bool _isRerouting = false;

  void init(MapCameraController cameraController) {
    _cameraController = cameraController;
  }

  // ───── Start Navigation ─────
  Future<void> startNavigation(RouteResult route) async {
    _activeRoute = route;
    _currentStepIndex = 0;

    // 🚀 FIX: Safely cast List<dynamic> to List<Map<String, dynamic>>
    final List<Map<String, dynamic>> rawSteps =
        List<Map<String, dynamic>>.from(route.steps);

    // 🚀 FIX: Offload parsing using primitive-only data structures across the Isolate boundary
    final parsed = await Isolate.run(() => _parseStepsSync(rawSteps));

    _parsedInstructions = parsed.instructions;
    _maneuverIcons = parsed.maneuverIcons;
    _stepDistances = parsed.stepDistances;
    _stepDurations = parsed.stepDurations;

    // 🚀 Reconstruct LatLng objects on the Main Thread (Safe from Isolate Memory restrictions)
    _stepStartLocations = List.generate(parsed.startLatitudes.length,
        (i) => LatLng(parsed.startLatitudes[i], parsed.startLongitudes[i]));
    _stepEndLocations = List.generate(parsed.endLatitudes.length,
        (i) => LatLng(parsed.endLatitudes[i], parsed.endLongitudes[i]));

    _updateNavigationNotifiers();
    isNavigating.value = true;
    _cameraController?.setCameraForMode(CameraMode.driving);
  }

  void stopNavigation() {
    isNavigating.value = false;
    _activeRoute = null;
    _currentStepIndex = 0;
    _parsedInstructions.clear();
    _maneuverIcons.clear();
    _stepStartLocations.clear();
    _stepEndLocations.clear();
    _stepDistances.clear();
    _stepDurations.clear();
    _isRerouting = false;

    _cameraController?.setCameraForMode(CameraMode.explore);
  }

  // ───── The 60FPS Location Loop ─────
  Future<void> processLocationUpdate(Position userPos) async {
    if (!isNavigating.value ||
        _activeRoute == null ||
        _parsedInstructions.isEmpty) {
      return;
    }

    _updateCompassAndBearing(userPos.heading);
    await _cameraController?.processLocationUpdate(userPos);

    if (_currentStepIndex >= _stepEndLocations.length) {
      currentInstruction.value = "You have arrived!";
      remainingDistance.value = 0.0;
      distanceToNextTurn.value = 0.0;
      return;
    }

    final userLatLng = LatLng(userPos.latitude, userPos.longitude);
    final stepStart = _stepStartLocations[_currentStepIndex];
    final stepEnd = _stepEndLocations[_currentStepIndex];

    final distToTurn = _calculateDistance(userLatLng, stepEnd);
    distanceToNextTurn.value = distToTurn;

    _updateRemainingETA(distToTurn);

    // 🚀 Smart Off-Route Detection using True Cross-Track Distance
    if (_shouldCheckOffRoute(stepStart, stepEnd, userLatLng)) {
      await _handleOffRoute(userLatLng);
    }

    // 🚀 FIX: Null-safe speed fallback
    final double currentSpeed = userPos.speed >= 0 ? userPos.speed : 0.0;
    double turnThreshold = currentSpeed > 15.0 ? 55.0 : 25.0;

    if (distToTurn < turnThreshold &&
        _currentStepIndex < _stepEndLocations.length - 1) {
      _currentStepIndex++;
      _updateNavigationNotifiers();
    }
  }

  void _updateCompassAndBearing(double heading) {
    double normalizedHeading = heading % 360;
    if (normalizedHeading < 0) normalizedHeading += 360;

    currentBearing.value = normalizedHeading;
    isDeviatedFromNorth.value =
        (normalizedHeading > 5.0 && normalizedHeading < 355.0);
  }

  void _updateRemainingETA(double distToTurn) {
    double stepDistRemain = _stepDistances[_currentStepIndex];
    double stepDurationRemain = _stepDurations[_currentStepIndex];

    double ratio = 1.0;
    if (stepDistRemain > 0) {
      ratio = (distToTurn / stepDistRemain).clamp(0.0, 1.0);
    }

    double totalDist = distToTurn;
    double totalDur = stepDurationRemain * ratio;

    for (int i = _currentStepIndex + 1; i < _stepDistances.length; i++) {
      totalDist += _stepDistances[i];
      totalDur += _stepDurations[i];
    }
    remainingDistance.value = totalDist;
    remainingDuration.value = totalDur;
  }

  bool _shouldCheckOffRoute(LatLng stepStart, LatLng stepEnd, LatLng userPos) {
    final now = DateTime.now();
    if (_lastOffRouteCheck != null &&
        now.difference(_lastOffRouteCheck!) < offRouteThrottle) {
      return false;
    }

    // 🚀 TRUE CROSS-TRACK ERROR MATH (Apple/Google Standard)
    // Calculates perpendicular distance from user to the current route segment
    double crossTrackError =
        _calculateCrossTrackDistance(stepStart, stepEnd, userPos);

    if (crossTrackError.abs() > offRouteDeadZoneMeters) {
      _lastOffRouteCheck = now;
      return true;
    }
    return false;
  }

  Future<void> _handleOffRoute(LatLng userPos) async {
    if (_isRerouting) return;
    _isRerouting = true;
    currentInstruction.value = "Rerouting...";

    // 🚀 HOOK: Hook into actual OlaRoutingService / MapService here
    // Example: final newRoute = await routingService.getRoute(userPos, destination);
    // await startNavigation(newRoute);

    await Future.delayed(const Duration(seconds: 2));
    _isRerouting = false;
  }

  void _updateNavigationNotifiers() {
    if (_currentStepIndex < _parsedInstructions.length) {
      currentInstruction.value = _parsedInstructions[_currentStepIndex];
      maneuverIcon.value = _maneuverIcons[_currentStepIndex];
      currentStepIndexNotifier.value = _currentStepIndex;
    }
  }

  void dispose() {
    stopNavigation();
    isNavigating.dispose();
    currentInstruction.dispose();
    distanceToNextTurn.dispose();
    remainingDistance.dispose();
    remainingDuration.dispose();
    currentStepIndexNotifier.dispose();
    maneuverIcon.dispose();
    currentBearing.dispose();
    isDeviatedFromNorth.dispose();
  }

  // ───── Static Isolate Logic (Primitive Friendly) ─────
  static _ParsedSteps _parseStepsSync(List<Map<String, dynamic>> steps) {
    final instructions = <String>[];
    final icons = <String>[];

    final startLats = <double>[];
    final startLngs = <double>[];
    final endLats = <double>[];
    final endLngs = <double>[];

    final stepDistances = <double>[];
    final stepDurations = <double>[];

    for (final step in steps) {
      final raw = step['html_instructions'] as String? ?? 'Continue';
      final clean = raw.replaceAll(RegExp(r'<[^>]*>'), '');
      instructions.add(clean.trim());

      icons.add(step['maneuver'] as String? ?? '');

      // Parse Start Location (Fallback to end of previous if needed, but APIs usually provide it)
      final start = step['start_location'] ?? step['end_location'];
      startLats.add((start['lat'] as num).toDouble());
      startLngs.add((start['lng'] as num).toDouble());

      // Parse End Location
      final end = step['end_location'];
      endLats.add((end['lat'] as num).toDouble());
      endLngs.add((end['lng'] as num).toDouble());

      stepDistances
          .add((step['distance']?['value'] as num?)?.toDouble() ?? 0.0);
      stepDurations
          .add((step['duration']?['value'] as num?)?.toDouble() ?? 0.0);
    }

    return _ParsedSteps(instructions, icons, startLats, startLngs, endLats,
        endLngs, stepDistances, stepDurations);
  }

  double _calculateDistance(LatLng a, LatLng b) {
    const p = pi / 180.0;
    final aVal = 0.5 -
        cos((b.latitude - a.latitude) * p) / 2 +
        cos(a.latitude * p) *
            cos(b.latitude * p) *
            (1 - cos((b.longitude - a.longitude) * p)) /
            2;
    return 12742 * asin(sqrt(aVal)) * 1000;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * pi / 180.0;
    double lng1 = start.longitude * pi / 180.0;
    double lat2 = end.latitude * pi / 180.0;
    double lng2 = end.longitude * pi / 180.0;

    double dLon = (lng2 - lng1);
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double brng = atan2(y, x);
    return (brng * 180.0 / pi + 360.0) % 360.0;
  }

  double _calculateCrossTrackDistance(
      LatLng segmentStart, LatLng segmentEnd, LatLng userPos) {
    double d13 = _calculateDistance(segmentStart, userPos) / 6371000.0;
    double brng13 = _calculateBearing(segmentStart, userPos) * pi / 180.0;
    double brng12 = _calculateBearing(segmentStart, segmentEnd) * pi / 180.0;

    // Cross-track error formula
    return asin(sin(d13) * sin(brng13 - brng12)) * 6371000.0;
  }
}

// ───── Internal Data Class (100% Primitive & Isolate Safe) ─────
class _ParsedSteps {
  final List<String> instructions;
  final List<String> maneuverIcons;

  final List<double> startLatitudes;
  final List<double> startLongitudes;
  final List<double> endLatitudes;
  final List<double> endLongitudes;

  final List<double> stepDistances;
  final List<double> stepDurations;

  _ParsedSteps(
      this.instructions,
      this.maneuverIcons,
      this.startLatitudes,
      this.startLongitudes,
      this.endLatitudes,
      this.endLongitudes,
      this.stepDistances,
      this.stepDurations);
}
