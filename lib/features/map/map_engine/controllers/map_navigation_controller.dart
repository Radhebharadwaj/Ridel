import 'dart:async';

import 'dart:math';
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
  final ValueNotifier<String?> voiceInstruction = ValueNotifier(null);
  final ValueNotifier<List<LatLng>> remainingPolyline = ValueNotifier([]);

  // 🧭 Compass & Bearing States
  final ValueNotifier<double> currentBearing = ValueNotifier(0.0);
  final ValueNotifier<bool> isDeviatedFromNorth = ValueNotifier(false);

  // 🎯 NEW — Snapped Position (for UI pointer / blue dot override)
  final ValueNotifier<LatLng?> snappedPosition = ValueNotifier(null);

  // 🚨 NEW — Off-Route State (for reroute UI overlay)
  final ValueNotifier<bool> isOffRoute = ValueNotifier(false);

  // 📡 NEW — Dead Reckoning State
  DateTime? _lastRealGpsTime;
  Timer? _heartbeatTimer;
  final ValueNotifier<bool> isGpsLost = ValueNotifier(false);

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
  final Set<int> _spokenMilestones = {};

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

  double _smoothedSpeed = -1.0;
  double _averageRouteSpeed = 5.0; // Base fallback (approx 18 km/h)

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
    // Force early camera tilt so the UI responds instantly
    _cameraController?.setCameraForMode(CameraMode.driving);

    _activeRoute = route;
    _currentStepIndex = 0;
    _windowStart = 0;
    _consecutiveOffRouteTicks = 0;
    _snapResult.reset();
    isOffRoute.value = false;
    isGpsLost.value = false;
    _lastRealGpsTime = DateTime.now().add(const Duration(seconds: 5));
    _startGpsHeartbeat();

    final double routeDistanceMeters = route.distanceKm * 1000.0;
    final double routeDurationSeconds = route.durationMins * 60.0;
    _averageRouteSpeed = (routeDistanceMeters > 0 && routeDurationSeconds > 0) 
        ? (routeDistanceMeters / routeDurationSeconds) 
        : 5.0;
    _smoothedSpeed = -1.0;

    remainingDistance.value = routeDistanceMeters;
    remainingDuration.value = routeDurationSeconds;

    // 🚀 Safely cast List<dynamic> to List<Map<String, dynamic>>
    final List<Map<String, dynamic>> rawSteps =
        List<Map<String, dynamic>>.from(route.steps);

    // 🚀 Execute synchronously (Isolate.run crashes on Flutter Web)
    final parsed = _parseStepsSync(rawSteps);

    _parsedInstructions = parsed.instructions;
    _maneuverIcons = parsed.maneuverIcons;
    _stepDistances = parsed.stepDistances;

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

    // Prime the Top Banner immediately
    if (_parsedInstructions.isNotEmpty) {
      currentInstruction.value = _parsedInstructions.first;
      if (_stepDistances.isNotEmpty) distanceToNextTurn.value = _stepDistances.first;
    }

    _updateNavigationNotifiers();
    if (_stepDistances.isNotEmpty) distanceToNextTurn.value = _stepDistances.first;
    remainingPolyline.value = route.coordinates;
    if (route.coordinates.isNotEmpty) {
      snappedPosition.value = route.coordinates.first;
    }
    isNavigating.value = true;
  }

  void stopNavigation() {
    _heartbeatTimer?.cancel();
    isGpsLost.value = false;
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
    _stepBoundaries.clear();
    _spokenMilestones.clear();
    _isRerouting = false;
    _snapResult.reset();
    remainingPolyline.value = [];

    _cameraController?.setCameraForMode(CameraMode.explore);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ⚡ THE 60 FPS LOCATION LOOP — HOT PATH
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> processLocationUpdate(Position userPos, {bool isSimulated = false}) async {
    if (!isSimulated) {
      _lastRealGpsTime = DateTime.now();
      isGpsLost.value = false;
    }

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
        _spokenMilestones.clear();
        final double initialStepDist = _stepDistances[newStepIndex];
        if (initialStepDist < 1000) _spokenMilestones.add(1000);
        if (initialStepDist < 500) _spokenMilestones.add(500);
        if (initialStepDist < 200) _spokenMilestones.add(200);
        if (initialStepDist < 50) _spokenMilestones.add(50);
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
    remainingPolyline.value = [snappedPosition.value!, ...polyline.sublist(_snapResult.segmentIndex + 1)];

    // Null-safe speed fallback
    final double currentSpeed = userPos.speed >= 0 ? userPos.speed : 0.0;

    if (_smoothedSpeed < 0) {
      _smoothedSpeed = currentSpeed > 0 ? currentSpeed : _averageRouteSpeed;
    } else {
      final double alpha = currentSpeed > _smoothedSpeed ? 0.2 : 0.05;
      _smoothedSpeed = (currentSpeed * alpha) + (_smoothedSpeed * (1 - alpha));
    }

    final double effectiveSpeedForEta = max(_smoothedSpeed, 2.0); // 2.0 m/s is ~7.2 km/h (slow walking/crawling traffic).

    remainingDuration.value = RoutingService.estimateRemainingTime(
      remDist,
      effectiveSpeedForEta,
    );

    // Distance to next turn = distance from snapped position to current step end
    if (_currentStepIndex < _stepEndLocations.length) {
      distanceToNextTurn.value = RoutingService.haversine(
        _snapResult.snappedLat,
        _snapResult.snappedLng,
        _stepEndLocations[_currentStepIndex].latitude,
        _stepEndLocations[_currentStepIndex].longitude,
      );
      if (_currentStepIndex < _parsedInstructions.length) {
        _checkAndTriggerVoice(distanceToNextTurn.value, _parsedInstructions[_currentStepIndex]);
      }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 7: Arrival Detection
    // ─────────────────────────────────────────────────────────────────────
    if (remDist < 25.0 && _currentStepIndex >= _parsedInstructions.length - 1) {
      if (isGpsLost.value == true) {
        currentInstruction.value = "Near destination. GPS signal lost.";
        voiceInstruction.value = "You are near your destination, but GPS signal is lost.";
      } else {
        currentInstruction.value = "You have arrived!";
        voiceInstruction.value = "You have arrived at your destination.";
      }
      remainingDistance.value = 0.0;
      distanceToNextTurn.value = 0.0;
      remainingDuration.value = 0.0;
      // Don't auto-stop — let the UI handle the arrival UX.
    }

    // ─────────────────────────────────────────────────────────────────────
    // 🎯 STEP 8: Camera Follow (using snapped position + segment bearing)
    // ─────────────────────────────────────────────────────────────────────
    await _cameraController?.processLocationUpdate(userPos, isSimulated: isSimulated);
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

  void _checkAndTriggerVoice(double distanceMeters, String instruction) {
    final milestones = [1000, 500, 200, 50]; // meters
    for (final milestone in milestones) {
      if (distanceMeters <= milestone && !_spokenMilestones.contains(milestone)) {
        _spokenMilestones.add(milestone);
        String formattedText;
        if (milestone == 1000) {
          formattedText = "In 1 kilometer, $instruction";
        } else if (milestone == 50) {
          formattedText = "Turn soon: $instruction";
        } else {
          formattedText = "In $milestone meters, $instruction";
        }
        voiceInstruction.value = formattedText;
        break;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧹 LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  void dispose() {
    _heartbeatTimer?.cancel();
    stopNavigation();
    isNavigating.dispose();
    currentInstruction.dispose();
    distanceToNextTurn.dispose();
    remainingDistance.dispose();
    remainingDuration.dispose();
    currentStepIndexNotifier.dispose();
    maneuverIcon.dispose();
    voiceInstruction.dispose();
    currentBearing.dispose();
    isDeviatedFromNorth.dispose();
    snappedPosition.dispose();
    isOffRoute.dispose();
    isGpsLost.dispose();
    remainingPolyline.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📡 DEAD RECKONING ENGINE (Tunnel Mode)
  // ═══════════════════════════════════════════════════════════════════════════

  void _startGpsHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lastRealGpsTime != null) {
        final int age = DateTime.now().difference(_lastRealGpsTime!).inSeconds;
        if (age > 10) {
          isGpsLost.value = true;
          _simulateLocation();
        }
      }
    });
  }

  void _simulateLocation() {
    if (!isNavigating.value || _activeRoute == null) return;
    
    final LatLng? startLoc = snappedPosition.value;
    if (startLoc == null) return;

    if (_smoothedSpeed <= 0.5) {
      final Position stoppedPos = Position(
        longitude: startLoc.longitude,
        latitude: startLoc.latitude,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: _snapResult.segmentBearing,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        isMocked: true,
      );
      processLocationUpdate(stoppedPos, isSimulated: true);
      return;
    }

    double moveDist = _smoothedSpeed * 1.0;
    final List<LatLng> polyline = _activeRoute!.coordinates;
    int idx = _snapResult.segmentIndex;
    LatLng current = startLoc;
    double remainingMove = moveDist;

    while (idx < polyline.length - 1 && remainingMove > 0) {
      final LatLng pNext = polyline[idx + 1];
      final double distToNext = RoutingService.haversine(
        current.latitude, current.longitude, pNext.latitude, pNext.longitude);
      
      if (remainingMove >= distToNext) {
        remainingMove -= distToNext;
        current = pNext;
        idx++;
      } else {
        final double bearing = RoutingService.bearing(
            current.latitude, current.longitude, pNext.latitude, pNext.longitude);
        
        const double R = 6371000.0;
        final double d = remainingMove / R;
        final double lat1 = current.latitude * pi / 180.0;
        final double lon1 = current.longitude * pi / 180.0;
        final double brng = bearing * pi / 180.0;
        
        final double lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng));
        final double lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2));
        
        current = LatLng(lat2 * 180.0 / pi, lon2 * 180.0 / pi);
        remainingMove = 0;
      }
    }

    final Position mockedPosition = Position(
      longitude: current.longitude,
      latitude: current.latitude,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: _snapResult.segmentBearing,
      headingAccuracy: 0.0,
      speed: _smoothedSpeed,
      speedAccuracy: 0.0,
      isMocked: true,
    );

    processLocationUpdate(mockedPosition, isSimulated: true);
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
    }

    return _ParsedSteps(instructions, icons, startLats, startLngs, endLats,
        endLngs, stepDistances);
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

  _ParsedSteps(
      this.instructions,
      this.maneuverIcons,
      this.startLatitudes,
      this.startLongitudes,
      this.endLatitudes,
      this.endLongitudes,
      this.stepDistances);
}
