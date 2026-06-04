import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ridel/features/map/services/route_engine_service.dart';
import 'package:ridel/features/map/services/routing_service.dart';

import 'map_camera_controller.dart';

class MapNavigationController {
  // ═══════════════════════════════════════════════════════════════════════════
  // 📡 GRANULAR REACTIVE NOTIFIERS (UI Layer Consumes These)
  // ═══════════════════════════════════════════════════════════════════════════

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

  // 🎯 NEW — Snapped Position (for UI pointer / blue dot override)
  final ValueNotifier<LatLng?> snappedPosition = ValueNotifier(null);

  // 🚨 NEW — Off-Route State (for reroute UI overlay)
  final ValueNotifier<bool> isOffRoute = ValueNotifier(false);

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧠 INTERNAL STATE
  // ═══════════════════════════════════════════════════════════════════════════

  RouteResult? _activeRoute;
  int _currentStepIndex = 0;

  // ───── Pre-computed Instruction Cache (Thread-safe) ─────
  List<String> _parsedInstructions = [];
  List<String> _maneuverIcons = [];
  List<LatLng> _stepStartLocations = []; // Needed for step boundary mapping
  List<LatLng> _stepEndLocations = [];
  List<double> _stepDistances = [];
  List<double> _stepDurations = [];

  // ───── 🚀 NEW — Local Windowing State ─────
  /// Current start index of the sliding window over the polyline.
  int _windowStart = 0;

  /// Pre-allocated snap result — reused every GPS tick. Zero GC pressure.
  final SnapResult _snapResult = SnapResult();

  /// Pre-computed step boundary indices (polyline index → step index mapping).
  /// Built once at navigation start via RoutingService.buildStepBoundaries().
  List<int> _stepBoundaries = [];

  /// Consecutive off-route tick counter. Reroute only fires after N consecutive
  /// off-route detections to prevent false positives from GPS jitter.
  int _consecutiveOffRouteTicks = 0;
  static const int _offRouteTickThreshold = 3; // ~3 seconds at 1Hz GPS

  // ───── External Controllers ─────
  MapCameraController? _cameraController;

  // ───── Off-route detection ─────
  bool _isRerouting = false;

  /// Optional callback for rerouting — set by MapEngine to wire in RouteEngineService.
  Future<RouteResult?> Function(LatLng userPos)? onRerouteRequested;

  void init(MapCameraController cameraController) {
    _cameraController = cameraController;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚀 START / STOP NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> startNavigation(RouteResult route) async {
    _activeRoute = route;
    _currentStepIndex = 0;
    _windowStart = 0;
    _consecutiveOffRouteTicks = 0;
    _snapResult.reset();
    isOffRoute.value = false;

    // 🚀 Safely cast List<dynamic> to List<Map<String, dynamic>>
    final List<Map<String, dynamic>> rawSteps =
        List<Map<String, dynamic>>.from(route.steps);

    // 🚀 Offload heavy parsing to a background isolate
    final parsed = await Isolate.run(() => _parseStepsSync(rawSteps));

    _parsedInstructions = parsed.instructions;
    _maneuverIcons = parsed.maneuverIcons;
    _stepDistances = parsed.stepDistances;
    _stepDurations = parsed.stepDurations;

    // 🚀 Reconstruct LatLng on Main Thread (safe from Isolate memory restrictions)
    _stepStartLocations = List.generate(parsed.startLatitudes.length,
        (i) => LatLng(parsed.startLatitudes[i], parsed.startLongitudes[i]));
    _stepEndLocations = List.generate(parsed.endLatitudes.length,
        (i) => LatLng(parsed.endLatitudes[i], parsed.endLongitudes[i]));

    // 🚀 NEW — Pre-compute step boundaries (one-time O(steps * ~100) operation)
    _stepBoundaries = RoutingService.buildStepBoundaries(
      route.coordinates,
      _stepStartLocations,
    );

    _updateNavigationNotifiers();
    isNavigating.value = true;
    _cameraController?.setCameraForMode(CameraMode.driving);
  }

  void stopNavigation() {
    isNavigating.value = false;
    isOffRoute.value = false;
    snappedPosition.value = null;
    _activeRoute = null;
    _currentStepIndex = 0;
    _windowStart = 0;
    _consecutiveOffRouteTicks = 0;
    _parsedInstructions.clear();
    _maneuverIcons.clear();
    _stepStartLocations.clear();
    _stepEndLocations.clear();
    _stepDistances.clear();
    _stepDurations.clear();
    _stepBoundaries.clear();
    _isRerouting = false;
    _snapResult.reset();

    _cameraController?.setCameraForMode(CameraMode.explore);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⚡ THE 60 FPS LOCATION LOOP — HOT PATH
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> processLocationUpdate(Position userPos) async {
    if (!isNavigating.value ||
        _activeRoute == null ||
        _parsedInstructions.isEmpty) {
      return;
    }

    _updateCompassAndBearing(userPos.heading);

    final List<LatLng> polyline = _activeRoute!.coordinates;
    if (polyline.length < 2) return;

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 1: Snap user to nearest polyline segment using Local Window
    // ─────────────────────────────────────────────────────────────────────
    RoutingService.snapToRoute(
      userPos.latitude,
      userPos.longitude,
      polyline,
      _windowStart,
      _snapResult,
    );

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 2: Update snapped position for UI pointer
    // ─────────────────────────────────────────────────────────────────────
    snappedPosition.value = _snapResult.snappedLatLng;

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 3: Cross-Track Distance → Off-Route Detection
    // ─────────────────────────────────────────────────────────────────────
    if (_snapResult.crossTrackDistance >
        RoutingService.offRouteThresholdMeters) {
      _consecutiveOffRouteTicks++;
      if (_consecutiveOffRouteTicks >= _offRouteTickThreshold) {
        isOffRoute.value = true;
        await _handleOffRoute(LatLng(userPos.latitude, userPos.longitude));
      }
    } else {
      _consecutiveOffRouteTicks = 0;
      isOffRoute.value = false;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 4: Window Advance — Slide forward if needed
    // ─────────────────────────────────────────────────────────────────────
    if (_snapResult.shouldAdvanceWindow) {
      _windowStart = (_windowStart + 1).clamp(0, polyline.length - 2);
    }

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 5: Step Instruction Matching
    // ─────────────────────────────────────────────────────────────────────
    if (_stepBoundaries.isNotEmpty) {
      final int newStepIndex = RoutingService.segmentToStepIndex(
        _snapResult.segmentIndex,
        _stepBoundaries,
      );

      if (newStepIndex != _currentStepIndex &&
          newStepIndex < _parsedInstructions.length) {
        _currentStepIndex = newStepIndex;
        _updateNavigationNotifiers();
      }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 6: Remaining Distance & ETA
    // ─────────────────────────────────────────────────────────────────────
    final double remDist = RoutingService.remainingPolylineDistance(
      polyline,
      _snapResult.segmentIndex,
      _snapResult.alongTrackFraction,
    );
    remainingDistance.value = remDist;

    // Null-safe speed fallback
    final double currentSpeed = userPos.speed >= 0 ? userPos.speed : 0.0;
    remainingDuration.value = RoutingService.estimateRemainingTime(
      remDist,
      currentSpeed,
    );

    // Distance to next turn = distance from snapped position to current step end
    if (_currentStepIndex < _stepEndLocations.length) {
      distanceToNextTurn.value = RoutingService.haversine(
        _snapResult.snappedLat,
        _snapResult.snappedLng,
        _stepEndLocations[_currentStepIndex].latitude,
        _stepEndLocations[_currentStepIndex].longitude,
      );
    }

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 7: Arrival Detection
    // ─────────────────────────────────────────────────────────────────────
    if (remDist < 25.0) {
      currentInstruction.value = "You have arrived!";
      remainingDistance.value = 0.0;
      distanceToNextTurn.value = 0.0;
      // Don't auto-stop — let the UI handle the arrival UX.
    }

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 8: Camera Follow (using snapped position + segment bearing)
    // ─────────────────────────────────────────────────────────────────────
    await _cameraController?.processLocationUpdate(userPos);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateCompassAndBearing(double heading) {
    double normalizedHeading = heading % 360;
    if (normalizedHeading < 0) normalizedHeading += 360;

    currentBearing.value = normalizedHeading;
    isDeviatedFromNorth.value =
        (normalizedHeading > 5.0 && normalizedHeading < 355.0);
  }

  Future<void> _handleOffRoute(LatLng userPos) async {
    if (_isRerouting) return;
    _isRerouting = true;
    currentInstruction.value = "Rerouting...";

    // 🚀 Attempt automatic reroute via the injected callback
    if (onRerouteRequested != null) {
      try {
        final newRoute = await onRerouteRequested!(userPos);
        if (newRoute != null && isNavigating.value) {
          await startNavigation(newRoute);
          debugPrint("🔄 Reroute successful. New route loaded.");
          return;
        }
      } catch (e) {
        debugPrint("⚠️ Reroute failed: $e");
      } finally {
        _isRerouting = false;
      }
    } else {
      // Fallback: No reroute callback wired. Reset after timeout.
      await Future.delayed(const Duration(seconds: 3));
      _isRerouting = false;
    }
  }

  void _updateNavigationNotifiers() {
    if (_currentStepIndex < _parsedInstructions.length) {
      currentInstruction.value = _parsedInstructions[_currentStepIndex];
      maneuverIcon.value = _maneuverIcons[_currentStepIndex];
      currentStepIndexNotifier.value = _currentStepIndex;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

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
    snappedPosition.dispose();
    isOffRoute.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧵 STATIC ISOLATE LOGIC (Primitive Friendly)
  // ═══════════════════════════════════════════════════════════════════════════

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
}

// ═══════════════════════════════════════════════════════════════════════════
// 📦 INTERNAL DATA CLASS (100% Primitive & Isolate Safe)
// ═══════════════════════════════════════════════════════════════════════════

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
