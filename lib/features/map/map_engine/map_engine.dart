import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/features/map/models/place_model.dart';

import 'controllers/map_camera_controller.dart';
import 'controllers/map_layer_controller.dart';
import 'controllers/map_mode_controller.dart';
import 'controllers/map_navigation_controller.dart';
import 'package:ridel/features/map/services/route_engine_service.dart';
import 'package:ridel/features/map/services/route_visualizer.dart';

enum EngineState { idle, switchingMode, animatingCamera, updatingLayers, error }

/// 🧭 The 4-state UI state machine for the map interaction lifecycle.
/// Controls what the primary action button (QuickActionButtons) shows.
enum MapUIState {
  /// Default exploration — no place or route selected.
  idle,

  /// A place has been selected (pin dropped) — show "Directions" button.
  placeSelected,

  /// A route polyline has been drawn on the map — show "Start" button.
  routeDrawn,

  /// Active turn-by-turn navigation is running — show "Stop" button.
  navigating,
}

/// The Core Engine. Converted to a Pure Orchestrator class.
/// Zero `notifyListeners()` to guarantee 60/120 FPS performance.
class MapEngine {
  MapLibreMapController? mapController;

  // ───── Granular Reactive State (Zero full-tree rebuilds) ─────
  final ValueNotifier<EngineState> state = ValueNotifier(EngineState.idle);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final ValueNotifier<double> realTimeSpeedKmph = ValueNotifier(0.0);

  /// 🧭 UI State Machine — drives QuickActionButtons morphing.
  final ValueNotifier<MapUIState> mapUIState = ValueNotifier(MapUIState.idle);

  late MapModeController mode;
  MapLayerController? layers;
  MapCameraController? camera;
  final MapNavigationController navigation = MapNavigationController();

  GlobalLocationService? locService;

  // ───── Route Engine for Rerouting ─────
  final RouteEngineService _routeEngine = RouteEngineService();
  LatLng? _navigationDestination; // The original destination for rerouting

  bool isDarkTheme = true;
  bool _isSwitchingMode = false;

  StreamSubscription<Position>? _positionStream;
  DateTime? _lastActionTime;
  static const Duration _debounceInterval = Duration(milliseconds: 300);

  MapEngine() {
    mode = MapModeController();

    // Bind layer toggles to mode changes (Executes background logic, NO UI REBUILD)
    mode.is3DMode.addListener(_onUserToggledLayers);
    mode.showTransitLayer.addListener(_onUserToggledLayers);
    mode.showTraffic.addListener(_onUserToggledLayers);
    mode.showPOIs.addListener(_onUserToggledLayers);
    mode.mapType.addListener(_onUserToggledLayers);
  }

  bool get isUserInIndia {
    final pos = locService?.currentPosition;
    if (pos == null) return true;
    final lat = pos.latitude;
    final lng = pos.longitude;
    return (lat >= 8.0 && lat <= 37.0 && lng >= 68.0 && lng <= 97.0);
  }

  Future<void> _onUserToggledLayers() async {
    if (layers == null || mapController == null) return;

    final camPos = mapController?.cameraPosition;
    if (camPos != null && !mode.isDrivingMode.value) {
      double targetPitch = mode.is3DMode.value ? 60.0 : 0.0;
      camera?.animateCameraCinematic(center: camPos.target, pitch: targetPitch);
    }
    await layers?.toggle3DVisibility(mode.is3DMode.value);
    await layers?.applyCustomToggles(mode);
  }

  // 🚀 FIX: TickerProvider (vsync) is now safely injected from the UI Widget Tree
  Future<void> onMapCreated(
    MapLibreMapController controller,
    bool isDark,
    GlobalLocationService locationService,
    TickerProvider vsync,
  ) async {
    mapController = controller;
    isDarkTheme = isDark;
    locService = locationService;

    layers = MapLayerController(controller);
    camera = MapCameraController(controller, locService!, vsync);

    // 🚀 FIX: Passed both mapController and camera to match your init signature
    navigation.init(camera!);

    // 🚀 CRITICAL WIRE: Inject reroute callback → RouteEngineService
    navigation.onRerouteRequested = (LatLng userPos) async {
      if (_navigationDestination == null) return null;
      try {
        final newRoute = await _routeEngine.getRoute(
          userPos,
          _navigationDestination!,
        );
        if (newRoute != null && mapController != null) {
          // Redraw the new route polyline on the map
          await RouteVisualizer.drawRoute(
            mapController,
            newRoute.coordinates,
            isDarkTheme,
          );
        }
        return newRoute;
      } catch (e) {
        debugPrint('⚠️ Reroute failed in MapEngine: $e');
        return null;
      }
    };

    try {
      await layers?.initLayerSystem();

      _initGPS();
      camera
          ?.setCameraForMode(_getCameraModeForMapMode(mode.currentMode.value));
      _setState(EngineState.idle);
    } catch (e) {
      _setError('Failed to initialize layers: $e');
    }
  }

  CameraMode _getCameraModeForMapMode(MapMode mapMode) {
    switch (mapMode) {
      case MapMode.explore:
      case MapMode.city3d:
        return CameraMode.explore;
      case MapMode.driving:
        return CameraMode.driving;
      case MapMode.transit:
        return CameraMode.transit;
    }
  }

  void _initGPS() {
    if (locService == null) return;

    locService!.startLiveTracking();
    _positionStream = locService!.engineLocationStream.listen((newPos) {
      // 🚀 FIX: Granular reactive update. Zero main-thread frame drops.
      realTimeSpeedKmph.value = locService!.currentSpeedKmph;
      camera?.processLocationUpdate(newPos);

      // 🚀 CRITICAL WIRE: Feed navigation controller on every GPS tick
      if (navigation.isNavigating.value) {
        navigation.processLocationUpdate(newPos);
      }
    });
  }

  Future<void> setMode(MapMode newMode) async {
    if (_shouldDebounce() ||
        _isSwitchingMode ||
        mode.currentMode.value == newMode) {
      return;
    }

    _isSwitchingMode = true;
    _setState(EngineState.switchingMode);

    try {
      mode.setMode(newMode);
      await layers?.resetAllLayers();
      await layers?.applyCustomToggles(mode);
      await camera?.setCameraForMode(_getCameraModeForMapMode(newMode));
      _clearError();
    } finally {
      _isSwitchingMode = false;
      _setState(EngineState.idle);
    }
  }

  Future<void> executeSearchFlight(LatLng target, {PlaceModel? place}) async {
    if (mapController == null || camera == null || layers == null) return;
    if (_shouldDebounce()) return; // 🚀 Debounce added to search flight

    _setState(EngineState.animatingCamera);

    // 🚀 FIX: Removed the redundant fadePOIsTemporarily()
    await layers!.showSearchPin(target, place: place);
    await camera!.animateSearchFlight(target);

    _setState(EngineState.idle);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🧭 ACTIVE NAVIGATION LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Starts step-by-step navigation with a pre-fetched route.
  /// Call this from MapProvider after the user taps "Start Navigation".
  ///
  /// [route] — The RouteResult from RouteEngineService.
  /// [destination] — The final destination LatLng (needed for rerouting).
  Future<void> startActiveNavigation(RouteResult route, LatLng destination) async {
    _navigationDestination = destination;

    // 1. Draw the route polyline on the map
    if (mapController != null) {
      await RouteVisualizer.drawRoute(
        mapController,
        route.coordinates,
        isDarkTheme,
      );
    }

    // 2. Start the navigation state machine (parses steps, builds boundaries)
    await navigation.startNavigation(route);

    // 3. Switch camera to driving mode (60° tilt, 17.8 zoom, heading-locked)
    await camera?.setCameraForMode(CameraMode.driving);

    // 4. Ensure GPS is feeding the navigation loop
    if (locService != null && !locService!.isLiveTracking) {
      locService!.startLiveTracking();
    }

    // 5. Transition UI state machine
    mapUIState.value = MapUIState.navigating;

    debugPrint('🧭 Active navigation started → ${route.steps.length} steps');
  }

  /// Stops navigation and cleans up all route visuals.
  Future<void> stopActiveNavigation() async {
    navigation.stopNavigation();
    _navigationDestination = null;

    if (mapController != null) {
      await RouteVisualizer.clearRoute(mapController);
    }

    // Transition UI state machine back to idle
    mapUIState.value = MapUIState.idle;

    await camera?.setCameraForMode(CameraMode.explore);
    debugPrint('🛑 Active navigation stopped.');
  }

  /// Sets the UI state machine to a specific state (for external callers).
  void setUIState(MapUIState state) {
    if (mapUIState.value != state) {
      mapUIState.value = state;
    }
  }

  /// Resets the full UI state machine to idle and clears route visuals.
  Future<void> resetUIState() async {
    if (mapUIState.value == MapUIState.navigating) {
      await stopActiveNavigation();
    } else {
      if (mapController != null) {
        await RouteVisualizer.clearRoute(mapController);
      }
      mapUIState.value = MapUIState.idle;
    }
  }

  void onLocateMeTapped() {
    if (_shouldDebounce()) return; // 🚀 FIX: Debounce applied
    camera?.onLocateMeTapped(
        mode.is3DMode.value, mode.currentMode.value == MapMode.driving);
  }

  void onCompassTapped() {
    if (_shouldDebounce()) return; // 🚀 FIX: Debounce applied
    camera?.resetCompass();
  }

  void onUserPannedMap() {
    // Calling the newly created gesture hook in the Camera Controller
    camera?.onUserPanGesture();
  }

  void updateExtrusionProgress(double progress) {
    layers?.updateBuildingExtrusion(progress, isDarkTheme);
    if (progress == 0.0 && !mode.is3DMode.value) {
      layers?.toggle3DVisibility(false);
    }
  }

  // ───── State Management Helpers ─────

  bool get hasError => lastError.value != null;

  void _setError(String error) {
    lastError.value = error;
    _setState(EngineState.error);
  }

  void _clearError() {
    lastError.value = null;
  }

  void _setState(EngineState newState) {
    state.value = newState;
  }

  bool _shouldDebounce() {
    final now = DateTime.now();
    if (_lastActionTime != null &&
        now.difference(_lastActionTime!) < _debounceInterval) {
      return true;
    }
    _lastActionTime = now;
    return false;
  }

  // ───── Memory Leak Prevention ─────

  void dispose() {
    // 1. Remove Listeners
    mode.is3DMode.removeListener(_onUserToggledLayers);
    mode.showTransitLayer.removeListener(_onUserToggledLayers);
    mode.showTraffic.removeListener(_onUserToggledLayers);
    mode.showPOIs.removeListener(_onUserToggledLayers);
    mode.mapType.removeListener(_onUserToggledLayers);

    // 2. Cancel Streams
    _positionStream?.cancel();

    // 3. Dispose ValueNotifiers
    state.dispose();
    lastError.dispose();
    realTimeSpeedKmph.dispose();
    mapUIState.dispose();

    // 4. Dispose Child Controllers
    camera?.dispose();
    layers?.dispose();
    navigation.dispose();
    mode.dispose();
    _routeEngine.dispose();

    // 5. Dispose Native Map
    mapController?.dispose();
  }
}
