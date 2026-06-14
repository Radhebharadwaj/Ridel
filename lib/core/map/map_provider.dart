import 'dart:math' as math;
import 'dart:math' show Point;
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;


import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_style_helper.dart';
import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/map/map_engine/map_engine.dart';
import 'package:ridel/features/map/models/place_model.dart';
import 'package:ridel/features/map/services/master_search_service.dart';
import 'package:ridel/features/map/services/place_api_services.dart';
import 'package:ridel/features/map/services/route_visualizer.dart';
import 'package:flutter/foundation.dart';
import 'package:ridel/features/map/services/route_engine_service.dart';
import 'package:ridel/features/map/map_engine/controllers/map_camera_controller.dart';
import 'package:ridel/core/utils/toast_service.dart';

class MapProvider extends ChangeNotifier {
  final MapEngine engine = MapEngine();
  final RouteEngineService _routingService = RouteEngineService();

  MapLibreMapController? get controller => engine.mapController;
  bool get _isMapReady => controller != null;

  MyLocationTrackingMode _currentTrackingMode = kIsWeb
      ? MyLocationTrackingMode.tracking
      : MyLocationTrackingMode.trackingCompass;

  MyLocationTrackingMode get currentTrackingMode => _currentTrackingMode;

  Future<void> setTrackingMode(MyLocationTrackingMode mode) async {
    if (_currentTrackingMode != mode) {
      _currentTrackingMode = mode;
      notifyListeners();
    }
    if (controller != null) {
      try {
        await controller!.updateMyLocationTrackingMode(mode);
      } catch (_) {}
    }
  }

  Circle? _currentMarker;
  Circle? _originMarker;

  AnimationController? _pinAnimController;

  // 1. User ka current coordinate track karne ke liye
  LatLng? currentLocation;

  void updateCurrentLocation(LatLng loc) {
    currentLocation = loc;
    // Yahan notifyListeners() mat lagana warna map lag karega
  }

  // 2. Screen par user hai ya nahi, uski state
  bool _isUserVisibleOnScreen = true;
  bool get isUserVisibleOnScreen => _isUserVisibleOnScreen;

  void setUserVisibility(bool isVisible) {
    if (_isUserVisibleOnScreen != isVisible) {
      _isUserVisibleOnScreen = isVisible;
      notifyListeners(); // Yeh UI ko update karega!
    }
  }

  // 🚀 NAVIGATION PUCK LOGIC
  LatLng _lastPuckLocation = const LatLng(0, 0);
  double _lastPuckBearing = 0.0;

  bool get showNativeBlueDot =>
      engine.mapUIState.value == MapUIState.idle ||
      engine.mapUIState.value == MapUIState.placeSelected;
  double get customPuckOpacity =>
      (engine.mapUIState.value == MapUIState.navigating ||
              engine.mapUIState.value == MapUIState.routeDrawn)
          ? 1.0
          : 0.0;

  Future<void> _updatePuckGeoJson(
      LatLng location, double bearing, double opacity) async {
    if (controller == null) return;
    try {
      final bool isVisible = opacity > 0.0;
      await controller!.setGeoJsonSource('nav_puck_source', {
        "type": "FeatureCollection",
        "features": isVisible
            ? [
                {
                  "type": "Feature",
                  "geometry": {
                    "type": "Point",
                    "coordinates": [location.longitude, location.latitude]
                  },
                  "properties": {"bearing": bearing}
                }
              ]
            : []
      });
      _lastPuckLocation = location;
      _lastPuckBearing = bearing;
    } catch (_) {}
  }

  Future<void> updatePuckVisibility() async {
    await _updatePuckGeoJson(
        _lastPuckLocation, _lastPuckBearing, customPuckOpacity);
    engine.camera?.setBlueDotOpacity(showNativeBlueDot ? 1.0 : 0.0);
    notifyListeners();
  }

  Future<void> showNavigationPuck(LatLng location, double bearing) async {
    await _updatePuckGeoJson(location, bearing, customPuckOpacity);
  }

  Future<void> updateNavigationPuck(LatLng location, double bearing) async {
    // Only update if in a state where the puck should be visible
    if (customPuckOpacity == 0.0) {
      await updatePuckVisibility(); // Ensure it hides gracefully
      return;
    }

    // 1. ALWAYS update Puck Position & Rotation if visible (Route Overview & Navigating)
    await _updatePuckGeoJson(location, bearing, customPuckOpacity);

    // 2. Animate Camera to Follow User & Rotate Map ONLY if actively navigating
    if (engine.mapUIState.value == MapUIState.navigating &&
        controller != null &&
        isAutoTracking) {
      controller!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(
          target: location,
          bearing: bearing, // THIS ROTATES THE MAP WITH THE USER
          tilt: 50.0, // Keep the 3D perspective
          zoom: 18.0, // Zoomed in for navigation
        )),
        duration: const Duration(
            seconds: 1), // Smooth 1-second animation between GPS ticks
      );
    }
  }

  Future<void> hideNavigationPuck() async {
    await _updatePuckGeoJson(_lastPuckLocation, _lastPuckBearing, 0.0);
  }

  // 1. ADD NATIVE VECTOR PIN
  Future<void> addNativeDestinationPin(LatLng location) async {
    if (controller == null) return;

    // 🚨 1. STRICT CLEANUP: Wipe out the old route and reset UI state immediately
    await clearNativeRoute();
    isRouteCalculated = false; // Ensure the Start button reverts to Directions

    // 🚨 2. STRICT CLEANUP: Remove the old pin
    await clearNativeDestinationPin();

    // 3. Drop the new custom pin using SymbolLayer
    try {
      if (controller == null) return;
      await controller!.addGeoJsonSource('destination_pin_source', {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [location.longitude, location.latitude]
            }
          }
        ]
      });

      await controller!.addSymbolLayer(
        'destination_pin_source',
        'destination_pin_layer',
        const SymbolLayerProperties(
          iconImage: 'custom_pin',
          iconPitchAlignment: 'viewport',
          iconAnchor: 'bottom',
          iconSize: 0.20,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      targetDestination = location; // Update the internal coordinate tracker
      debugPrint("🗺️ CUSTOM PIN DROPPED at $location");

      // Removed redundant internal animation. Handled exclusively by caller.
      notifyListeners();
    } catch (e) {
      debugPrint("🗺️ PIN ERROR: $e");
    }
  }

  // 2. CLEAR NATIVE PIN
  Future<void> clearNativeDestinationPin() async {
    if (controller != null) {
      try {
        await controller!.removeLayer('destination_pin_layer');
      } catch (_) {}
      try {
        await controller!.removeSource('destination_pin_source');
      } catch (_) {}
      notifyListeners();
    }
  }

  // State flag for UI
  bool isRouteCalculated = false;

  Future<void> calculateAndDrawNativeRoute(
    BuildContext context,
    String mode,
  ) async {
    debugPrint("🚀 [ROUTE ENGINE] Triggered for mode: $mode");

    if (targetDestination == null) {
      debugPrint("❌ [ROUTE ENGINE] Failed: targetDestination is null.");
      return;
    }

    // 🚨 CRITICAL FIX: We must use the user's actual live location, NOT the camera position.
    final locService = Provider.of<GlobalLocationService>(
      context,
      listen: false,
    );
    final currentPos = locService.currentPosition;
    LatLng? origin = currentPos != null
        ? LatLng(currentPos.latitude, currentPos.longitude)
        : null;

    if (origin == null) {
      // 2. FALLBACK: Fetch fresh GPS location to guarantee Ola API gets an origin!
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        origin = LatLng(pos.latitude, pos.longitude);
      } catch (e) {
        debugPrint("🚨 GPS ERROR: Cannot calculate route without origin. $e");
        return;
      }
    }

    // 🚀 FETCH EXACT ORIGIN ADDRESS LAZILY
    unawaited(locService.fetchCurrentAddressIfNeeded());

    // 🚨 CRITICAL: Clear old routes and UI state before fetching new ones
    await clearNativeRoute(preserveState: true);
    if (controller == null) return;

    _currentRouteResult = null;
    notifyListeners();

    debugPrint(
      "📍 [ROUTE ENGINE] Origin: ${origin.latitude}, ${origin.longitude}",
    );
    debugPrint(
      "📍 [ROUTE ENGINE] Destination: ${targetDestination!.latitude}, ${targetDestination!.longitude}",
    );

    try {
      // Fetch route from Route Engine.
      debugPrint("⏳ [ROUTE ENGINE] Waiting for Route Engine API...");

      RouteResult? routeResult;

      if (mode == 'walking' || mode == 'walk') {
        routeResult = await _routingService.getWaterfallWalkRoute(
            origin, targetDestination!);
      } else {
        routeResult = await _routingService.getRoute(
          origin,
          targetDestination!,
          mode: 'driving',
        );
      }

      if (routeResult != null && routeResult.allRoutesCoordinates.isNotEmpty) {
        debugPrint(
          "✅ [ROUTE ENGINE] Ola API Success! Received ${routeResult.allRoutesCoordinates.first.length} points.",
        );

        _currentRouteResult = routeResult;
        _lastRouteData =
            routeResult; // 🚨 Ensure this is added so Bottom Sheet gets data
        await drawNativeRoute(routeResult.allRoutesCoordinates);
        debugPrint("✅ [ROUTE ENGINE] Native MapLibre Draw Success!");

        isRouteCalculated = true;
        engine.setUIState(MapUIState.routeDrawn);
        notifyListeners();
      } else {
        debugPrint(
          "⚠️ [ROUTE ENGINE] Ola API returned empty coordinates or null.",
        );
      }
    } catch (e) {
      debugPrint("💥 [ROUTE ENGINE] CRASH: $e");
    }
  }

  bool isActiveNavigation = false;
  bool isAutoTracking = true;

  bool _isUserPanning = false;
  bool get isUserPanning => _isUserPanning;

  void setUserPanning(bool value) {
    if (_isUserPanning != value) {
      _isUserPanning = value;
      notifyListeners();
    }
  }

  void setAutoTracking(bool tracking) {
    if (isAutoTracking != tracking) {
      isAutoTracking = tracking;
      notifyListeners();
    }
  }

  Future<void> start3DNavigation() async {
    if (controller == null) return;

    isActiveNavigation = true;
    isAutoTracking = true;

    if (_currentRouteResult != null && targetDestination != null) {
      await engine.startActiveNavigation(
          _currentRouteResult!, targetDestination!, currentNavMode);
    } else {
      engine.setUIState(MapUIState.navigating);
    }

    await updatePuckVisibility();
    notifyListeners();

    // 1. Get current user location with robust fallback
    final pos = engine.locService?.currentPosition;

    LatLng? targetLoc;
    if (pos != null) {
      targetLoc = LatLng(pos.latitude, pos.longitude);
    } else if (currentLocation != null) {
      targetLoc = currentLocation;
    } else if (_currentRouteResult != null &&
        _currentRouteResult!.coordinates.isNotEmpty) {
      targetLoc = _currentRouteResult!.coordinates.first;
    }

    if (targetLoc != null) {
      await showNavigationPuck(targetLoc, pos?.heading ?? 0.0);

      // 2. Animate Camera to 3D Perspective (Tilt/Pitch)
      await controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: targetLoc,
            zoom: 18.0, // Deep zoom for navigation
            tilt: 50.0, // 3D Pitch angle
            bearing: pos?.heading ?? 0.0,
          ),
        ),
        duration: const Duration(milliseconds: 1200),
      );
    }

    // 3. THE MAGIC: Lock camera to compass and change puck to Directional Triangle
    try {
      // TrackingCompass makes the map rotate automatically as the device rotates
      await setTrackingMode(
        MyLocationTrackingMode.trackingCompass,
      );
    } catch (_) {
      // Suppress error
    }
  }

  Future<void> recenter3DNavigation() async {
    if (controller == null) return;

    isAutoTracking = true;
    _isUserPanning = false;
    notifyListeners();

    final pos = engine.locService?.currentPosition;

    LatLng? targetLoc;
    if (pos != null) {
      targetLoc = LatLng(pos.latitude, pos.longitude);
    } else if (currentLocation != null) {
      targetLoc = currentLocation;
    }

    if (targetLoc != null) {
      await controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: targetLoc,
            zoom: 18.0,
            tilt: 50.0,
            bearing: pos?.heading ?? 0.0,
          ),
        ),
        duration: const Duration(milliseconds: 800),
      );
    }
  }

  List<String> activeFocusLayerIds = [];

  Future<void> _toggleFocusModeLayers(bool isFocusMode) async {
    if (controller == null) return;

    if (activeFocusLayerIds.isEmpty) {
      final allLayers = await controller!.getLayerIds();
      activeFocusLayerIds = allLayers.map((e) => e.toString()).where((id) {
        final lowerId = id.toLowerCase();
        bool isFocusTarget = lowerId.contains('poi') ||
            lowerId.contains('amenity') ||
            lowerId.contains('shop') ||
            lowerId.contains('transit');

        return isFocusTarget;
      }).toList();
      debugPrint("🔍 Tracked Focus Mode Layers: ${activeFocusLayerIds.length}");
    }

    if (activeFocusLayerIds.isEmpty) {
      debugPrint("⚠️ Cannot set Focus Mode: Layer IDs list is empty!");
      return;
    }

    // 🚨 Safe MapLibre Web Filter: Set a filter that matches nothing to hide the layer
    // This avoids using setLayerProperties which destroys iconImages on the WebGL bridge.
    final dynamic filter = isFocusMode ? ['==', 'id', 'nothing'] : null;

    for (String layerId in activeFocusLayerIds) {
      try {
        await controller!.setFilter(layerId, filter);
      } catch (_) {}
    }

    debugPrint(
        "🔍 Focus Mode set to $isFocusMode using non-destructive filters for ${activeFocusLayerIds.length} layers.");
  }

  // 🚨 DYNAMIC FUEL STATIONS TOGGLE
  List<String> _cachedFuelLayerIds = [];

  Future<void> _toggleFuelStationsVisibility(bool isVisible) async {
    if (controller == null) return;

    if (_cachedFuelLayerIds.isEmpty) {
      final allLayers = await controller!.getLayerIds();
      _cachedFuelLayerIds = allLayers.map((e) => e.toString()).where((id) {
        final lowerId = id.toLowerCase();
        return lowerId.contains('fuel') ||
            lowerId.contains('gas') ||
            lowerId.contains('petrol') ||
            lowerId.contains('gas_station');
      }).toList();
    }

    if (_cachedFuelLayerIds.isEmpty) return;

    final String visibilityValue = isVisible ? 'visible' : 'none';

    for (String layerId in _cachedFuelLayerIds) {
      try {
        await controller!.setLayerProperties(
            layerId, SymbolLayerProperties(visibility: visibilityValue));
      } catch (_) {}
      try {
        await controller!.setLayerProperties(
            layerId, FillLayerProperties(visibility: visibilityValue));
      } catch (_) {}
      try {
        await controller!.setLayerProperties(
            layerId, LineLayerProperties(visibility: visibilityValue));
      } catch (_) {}
    }

    debugPrint("⛽ Fuel Stations Visibility set to: $isVisible");
  }

  Future<bool> handleRouteClick(Point<double> point, LatLng coordinates) async {
    if (controller == null ||
        _drawnRoutesCount <= 1 ||
        _currentRouteResult == null) {
      return false;
    }

    // Alt layers start from index 1 (index 0 is primary)
    List<String> altLayerIds = List.generate(
      _drawnRoutesCount - 1,
      (i) => 'route-layer-${i + 1}',
    );
    final features = await controller!.queryRenderedFeatures(
      point,
      altLayerIds,
      null,
    );

    if (features.isNotEmpty) {
      AppHaptics.selectionClick();
      final feature = features.first;
      int tappedIndex = 0;
      if (feature is Map &&
          feature['properties'] is Map &&
          feature['properties']['index'] != null) {
        tappedIndex = feature['properties']['index'];
      }

      final tappedAlt = _currentRouteResult!.alternativeRoutes[tappedIndex];
      final currentPrimary = _currentRouteResult!.coordinates;

      // Swap routes visually
      List<List<LatLng>> updatedRoutes = List.from(
        _currentRouteResult!.allRoutesCoordinates,
      );
      updatedRoutes[0] = tappedAlt;
      updatedRoutes[tappedIndex + 1] = currentPrimary;

      final newResult = RouteResult(
        allRoutesCoordinates: updatedRoutes,
        distanceKm: _currentRouteResult!.distanceKm,
        durationMins: _currentRouteResult!.durationMins,
        steps: _currentRouteResult!.steps,
        firstInstruction: _currentRouteResult!.firstInstruction,
        fetchedAt: _currentRouteResult!.fetchedAt,
        trafficGradientStops: _currentRouteResult!.trafficGradientStops,
      );

      _currentRouteResult = newResult;
      await drawNativeRoute(newResult.allRoutesCoordinates);
      return true; // Handled ghost line tap
    }
    return false;
  }

  int _drawnRoutesCount = 0;
  RouteResult? _currentRouteResult;
  RouteResult? get currentRouteResult => _currentRouteResult;

  // Method to handle route swapping
  Future<void> swapRoute(int tappedIndex) async {
    if (_currentRouteResult == null ||
        tappedIndex == 0 ||
        tappedIndex >= _currentRouteResult!.allRoutesCoordinates.length) {
      return;
    }

    AppHaptics.selectionClick();

    // Swap the coordinates and raw routes in the result object
    final tappedCoords = _currentRouteResult!.allRoutesCoordinates.removeAt(
      tappedIndex,
    );
    _currentRouteResult!.allRoutesCoordinates.insert(0, tappedCoords);

    // Redraw the map with the new order (Index 0 is always drawn as Primary Blue)
    await drawNativeRoute(_currentRouteResult!.allRoutesCoordinates);
    notifyListeners();
  }

  Future<void> drawNativeRoute(List<List<LatLng>> allRoutes) async {
    if (controller == null || allRoutes.isEmpty) return;

    // 1. Clear previous route if it exists
    await clearNativeRoute(preserveState: true);

    // 🚨 Activate Focus Mode (Hide non-essential layers)
    await _toggleFocusModeLayers(true);

    _drawnRoutesCount = allRoutes.length;

    // 1. Draw Alternate Routes First (Underneath)
    for (int i = 1; i < allRoutes.length; i++) {
      List<LatLng> routePoints = allRoutes[i];
      final bool isWalking = currentNavMode == 'walking';

      if (isWalking) {
        // Filter out overlapping points with primary route to prevent messy dotted overlaps
        List<LatLng> filteredAltRoute = [];
        final primarySet = allRoutes[0]
            .map(
              (p) =>
                  '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
            )
            .toSet();
        bool wasInPrimary = true;
        for (int j = 0; j < routePoints.length; j++) {
          final p = routePoints[j];
          final pStr =
              '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
          final inPrimary = primarySet.contains(pStr);

          if (!inPrimary) {
            if (wasInPrimary && j > 0) {
              filteredAltRoute.add(routePoints[j - 1]); // Add branching point
            }
            filteredAltRoute.add(p);
          } else {
            if (!wasInPrimary) {
              filteredAltRoute.add(p); // Add converging point
            }
          }
          wasInPrimary = inPrimary;
        }
        if (filteredAltRoute.isNotEmpty) {
          routePoints = filteredAltRoute;
        } else {
          continue; // If completely overlapping, don't draw
        }
      }

      final coordinates =
          routePoints.map((p) => [p.longitude, p.latitude]).toList();

      final geoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {"index": i},
            "geometry": {"type": "LineString", "coordinates": coordinates},
          },
        ],
      };

      try {
        final bool isWalking = currentNavMode == 'walking';
        if (isWalking) {
          await controller!.addGeoJsonSource('alt-source-$i', geoJson);
          await controller!.addLineLayer(
            'alt-source-$i',
            'alt-walk-layer-$i',
            const LineLayerProperties(
              lineColor: "#8E8E93",
              lineWidth: 4.5,
              lineCap: "round",
              lineJoin: "round",
              lineDasharray: [0.01, 2.5],
            ),
            belowLayerId: 'nav_puck_layer',
          );
        } else {
          await controller!.addGeoJsonSource('route-source-$i', geoJson);
          await controller!.addLineLayer(
            'route-source-$i',
            'route-layer-$i',
            const LineLayerProperties(
              lineColor: "#8E8E93",
              lineWidth: 4.0,
              lineCap: "round",
              lineJoin: "round",
              lineOpacity: 0.6,
            ),
            belowLayerId: 'nav_puck_layer',
          );
        }
      } catch (e) {
        debugPrint("🗺️ ALT ROUTE DRAW ERROR for index $i: $e");
      }
    }

    // 2. Smooth and Build Primary Route (Index 0)
    if (allRoutes.isNotEmpty) {
      if (currentNavMode == 'walking') {
        debugPrint(
          "🚶‍♂️ WALK MODE: Total Routes = ${allRoutes.length}. Primary Route Coords: ${allRoutes[0].length}",
        );
      }
      final primaryCoords = allRoutes[0];

      List<Map<String, dynamic>> features = [];
      final congestionData = _currentRouteResult?.congestion;

      if (congestionData != null && congestionData.isNotEmpty) {
        for (int i = 0; i < primaryCoords.length - 1; i++) {
          int congestionIndex =
              (i / primaryCoords.length * congestionData.length).floor();
          if (congestionIndex >= congestionData.length) {
            congestionIndex = congestionData.length - 1;
          }

          features.add({
            "type": "Feature",
            "properties": {
              "index": 0,
              "congestion": congestionData[congestionIndex]
            },
            "geometry": {
              "type": "LineString",
              "coordinates": [
                [primaryCoords[i].longitude, primaryCoords[i].latitude],
                [primaryCoords[i + 1].longitude, primaryCoords[i + 1].latitude]
              ]
            },
          });
        }
      } else {
        features.add({
          "type": "Feature",
          "properties": {"index": 0, "congestion": "low"},
          "geometry": {
            "type": "LineString",
            "coordinates":
                primaryCoords.map((p) => [p.longitude, p.latitude]).toList()
          },
        });
      }

      final geoJson = {
        "type": "FeatureCollection",
        "features": features,
      };

      try {
        final bool isWalking = currentNavMode == 'walking';

        if (isWalking) {
          await controller!.addGeoJsonSource('primary-source', geoJson);
          await controller!.addLineLayer(
            'primary-source',
            'primary-walk-layer',
            const LineLayerProperties(
              lineColor: "#0A84FF", // Neon Blue Highlight
              lineWidth: 6.5, // Thicker to cover grey lines
              lineCap: "round",
              lineJoin: "round",
              lineDasharray: [0.01, 2.0], // Safe values for circular dots
            ),
            belowLayerId: 'nav_puck_layer',
          );
        } else {
          await controller!.addGeoJsonSource('route-source-0', geoJson);

          // 1. BOTTOM: Casing (Deep shadow to give height/3D effect)
          await controller!.addLineLayer(
            "route-source-0",
            "primary-casing",
            const LineLayerProperties(
              lineColor: "#001D4A", // Very dark navy blue
              lineWidth: 10.0,
              lineCap: "round",
              lineJoin: "round",
            ),
            belowLayerId: 'nav_puck_layer',
          );

          // 2. MIDDLE: Core (Solid Neon Blue or Traffic Colors)
          await controller!.addLineLayer(
            "route-source-0",
            "primary-core",
            const LineLayerProperties(
              lineColor: [
                "match",
                ["get", "congestion"],
                "severe", "#8B0000",
                "heavy", "#FF0000",
                "moderate", "#FFA500",
                "low", "#0A84FF", // Apple Neon Blue
                "#0A84FF" // Default
              ],
              lineWidth: 6.0,
              lineCap: "round",
              lineJoin: "round",
            ),
            belowLayerId: 'nav_puck_layer',
          );

          // 3. TOP: Shine (Ultra-thin 1px Sky Blue reflection perfectly blending)
          await controller!.addLineLayer(
            "route-source-0",
            "primary-shine",
            const LineLayerProperties(
              lineColor: "#AEE5FF", // A slightly softer, more blended sky blue
              lineWidth: 1.5,
              lineOpacity: 0.9,
              lineCap: "round",
              lineJoin: "round",
              lineBlur:
                  1.0, // Adds a tiny glow effect to blend the edges seamlessly into the core
            ),
            belowLayerId: 'nav_puck_layer',
          );
        }
      } catch (e) {
        debugPrint("🗺️ PRIMARY ROUTE DRAW ERROR: $e");
      }
    }

    // 4. FIX Z-INDEX RENDER SEQUENCE
    // Ensure destination pin and nav puck render strictly on top
    if (targetDestination != null) {
      await clearNativeDestinationPin();

      // Enforce rendering sequence for WebGL
      await Future.delayed(const Duration(milliseconds: 150));

      try {
        // Step 2: Add/Update Destination Pin Layer
        await controller!.addGeoJsonSource('destination_pin_source', {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": {
                "type": "Point",
                "coordinates": [
                  targetDestination!.longitude,
                  targetDestination!.latitude
                ]
              }
            }
          ]
        });

        await controller!.addSymbolLayer(
          'destination_pin_source',
          'destination_pin_layer',
          const SymbolLayerProperties(
            iconImage: 'custom_pin',
            iconPitchAlignment: 'viewport',
            iconAnchor: 'bottom',
            iconSize: 0.20,
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
          ),
        );

        // Step 3: Bring Nav Puck to Front
        try {
          await controller!.removeLayer('nav_puck_layer');
        } catch (_) {}

        await controller!.addSymbolLayer(
          'nav_puck_source',
          'nav_puck_layer',
          const SymbolLayerProperties(
            iconImage: 'nav_puck',
            iconPitchAlignment: 'map',
            iconRotationAlignment: 'map',
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
            iconSize: 0.15,
            iconOpacity: 1.0,
            iconRotate: ['get', 'bearing'],
          ),
        );
      } catch (e) {
        debugPrint("🗺️ Failed to enforce render sequence: $e");
      }
    }

    // 5. Adjust Camera to fit the PRIMARY route
    if (allRoutes.isNotEmpty) {
      try {
        await controller!.animateCamera(
          CameraUpdate.newLatLngBounds(
            _calculateBounds(allRoutes.first),
            bottom: 300, 
            left: 50,
            right: 50,
            top: 50,
          ),
          duration: const Duration(milliseconds: 800),
        );
      } catch (e) {
        debugPrint(
            "⚠️ Bounds fit failed (screen too small), falling back to center focus: $e");
        // Fallback to center point
        final bounds = _calculateBounds(allRoutes.first);
        final centerLat =
            (bounds.southwest.latitude + bounds.northeast.latitude) / 2;
        final centerLng =
            (bounds.southwest.longitude + bounds.northeast.longitude) / 2;
        await controller!.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(centerLat, centerLng), zoom: 12.0)));
      }
    }

    // 6. DRAW THE "WALK TO ROAD" AND "ROAD TO DESTINATION" CONNECTORS
    if (allRoutes.isNotEmpty && allRoutes[0].isNotEmpty) {
      try {
        final List<List<List<double>>> connectorLines = [];
        final pos = engine.locService?.currentPosition;

        // 1. ORIGIN GAP: User Location -> Start of Route
        if (pos != null) {
          final LatLng routeStart = allRoutes[0].first;
          connectorLines.add([
            [pos.longitude, pos.latitude],
            [routeStart.longitude, routeStart.latitude],
          ]);
        }

        // 2. DESTINATION GAP: End of Route -> Destination Pin
        if (targetDestination != null) {
          final LatLng routeEnd = allRoutes[0].last;
          connectorLines.add([
            [routeEnd.longitude, routeEnd.latitude],
            [targetDestination!.longitude, targetDestination!.latitude],
          ]);
        }

        // Draw the connectors if any gaps exist
        if (connectorLines.isNotEmpty) {
          try {
            await controller!.removeLayer('connectors-layer');
          } catch (_) {}
          try {
            await controller!.removeSource('connectors-source');
          } catch (_) {}

          await controller!.addGeoJsonSource("connectors-source", {
            "type": "Feature",
            "geometry": {
              "type": "MultiLineString",
              "coordinates": connectorLines,
            },
          });

          await controller!.addLineLayer(
            "connectors-source",
            "connectors-layer",
            const LineLayerProperties(
              lineColor: "#0A84FF", // Match the primary route color
              lineWidth: 3.5,
              lineCap: "round",
              lineJoin: "round",
              lineDasharray: [0.0, 2.5], // Premium circular dots
            ),
          );
        }
      } catch (e) {
        debugPrint("⚠️ Failed to draw route connectors: $e");
      }
    }

    // Get main route duration outside the loop
    double mainDurationSeconds = 0.0;
    if (_currentRouteResult != null &&
        _currentRouteResult!.allDurationSeconds.isNotEmpty) {
      mainDurationSeconds = _currentRouteResult!.allDurationSeconds[0];
    }

    // 7. FLOATING TIME TAGS (Add AFTER all lines and pins)
    for (int i = 0; i < allRoutes.length; i++) {
      final routePoints = allRoutes[i];
      final isPrimary = i == 0;

      double currentDurationSeconds = 0.0;
      if (_currentRouteResult != null &&
          _currentRouteResult!.allDurationSeconds.length > i) {
        currentDurationSeconds = _currentRouteResult!.allDurationSeconds[i];
      }

      String timeString = "";

      if (isPrimary) {
        // PRIMARY ROUTE: Absolute Time
        int hours = mainDurationSeconds ~/ 3600;
        int minutes = ((mainDurationSeconds % 3600) / 60).round();
        timeString = hours > 0 ? "$hours hr $minutes min" : "$minutes min";
        if (mainDurationSeconds == 0) timeString = "Calculating...";
      } else {
        // ALTERNATE ROUTES: Relative (Delta) Time
        double diffSeconds = currentDurationSeconds - mainDurationSeconds;
        int diffMinutes = (diffSeconds / 60).round();

        if (diffMinutes > 0) {
          timeString = "+$diffMinutes min";
        } else if (diffMinutes < 0) {
          timeString = "$diffMinutes min";
        } else {
          timeString = "Similar time";
        }
      }

      final String sourceId = 'time-tag-source-$i';
      final String layerId = 'time-tag-layer-$i';
      final String imageId =
          'time-tag-image-$i-${DateTime.now().millisecondsSinceEpoch}';

      LatLng midpoint;
      if (isPrimary) {
        midpoint = routePoints[routePoints.length ~/ 2];
      } else {
        midpoint = _getBestAlternateTagLocation(allRoutes[0], routePoints);
      }

      try {
        // 1. Generate and Add the Image
        final Uint8List imageBytes = await _generateETAPillImage(
          timeString,
          isPrimary,
        );
        await controller!.addImage(imageId, imageBytes);

        // 2. Add Point Source
        await controller!.addGeoJsonSource(sourceId, {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [midpoint.longitude, midpoint.latitude],
          },
        });

        // 3. Add Symbol Layer (ICON ONLY, NO TEXT)
        await controller!.addSymbolLayer(
          sourceId,
          layerId,
          SymbolLayerProperties(
            iconImage: imageId,
            iconSize: 0.15, // Scale down the high-res image
            iconAnchor: "bottom",
            iconOffset: [0, -1.0],
            symbolSortKey:
                i, // 🚨 THE FIX: MapLibre prioritizes LOWER numbers (i=0 is top priority)
            symbolPlacement: "point",
            // 🚨 SELECTIVE ANTI-COLLISION:
            // Main Route (i==0): Force it to ALWAYS show, ignoring overlaps.
            // Alternate Routes (i>0): Hide gracefully if they collide.
            iconAllowOverlap: isPrimary ? true : false,
            iconIgnorePlacement: isPrimary ? true : false,
          ),
        );
      } catch (e) {
        debugPrint("🗺️ ETA TAG DRAW ERROR for index $i: $e");
      }
    }

    notifyListeners();
  }

  Future<void> clearNativeRoute({bool preserveState = false}) async {
    if (controller != null && _drawnRoutesCount > 0) {
      // 1. SECURE LAYER CLEANUP (Must be removed first to free up sources)
      try {
        await controller!.removeLayer('primary-casing');
      } catch (_) {}
      try {
        await controller!.removeLayer('primary-core');
      } catch (_) {}
      try {
        await controller!.removeLayer('primary-shine');
      } catch (_) {}
      try {
        await controller!.removeLayer('primary-walk-layer');
      } catch (_) {}
      try {
        await controller!.removeLayer('connectors-layer');
      } catch (_) {}

      for (int i = 0; i < 5; i++) {
        try {
          await controller!.removeLayer('route-layer-$i');
        } catch (_) {}
        try {
          await controller!.removeLayer('alt-walk-layer-$i');
        } catch (_) {}
        try {
          await controller!.removeLayer('time-tag-layer-$i');
        } catch (_) {}
      }

      // 2. SECURE SOURCE CLEANUP (Only safe to remove after layers are dead)
      try {
        await controller!.removeSource('primary-source');
      } catch (_) {}
      try {
        await controller!.removeSource('connectors-source');
      } catch (_) {}

      for (int i = 0; i < 5; i++) {
        try {
          await controller!.removeSource('route-source-$i');
        } catch (_) {}
        try {
          await controller!.removeSource('alt-source-$i');
        } catch (_) {}
        try {
          await controller!.removeSource('time-tag-source-$i');
        } catch (_) {}
      }

      _drawnRoutesCount = 0;
      if (!preserveState) {
        isRouteCalculated = false;
        _currentRouteResult = null;
        _lastRouteData = null;

        // 🚨 Deactivate Focus Mode & Hide Puck
        await _toggleFocusModeLayers(false);
        await hideNavigationPuck();

        isActiveNavigation = false; // Reset navigation state
        engine.setUIState(MapUIState.idle);
        await updatePuckVisibility();

        // 🚨 Cinematic Camera Reset
        if (controller != null && currentLocation != null) {
          try {
            await controller!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: currentLocation!,
                  zoom: 15.0, // Comfortable default zoom
                  tilt: 0.0, // Strictly reset to flat 2D
                  bearing: 0.0, // Strictly reset rotation
                ),
              ),
              duration: const Duration(
                  milliseconds: 1200), // Smooth 1.2s premium flight
            );

            // Reset tracking mode after animation
            await setTrackingMode(
              MyLocationTrackingMode.tracking,
            );
          } catch (e) {
            debugPrint("⚠️ Native Tracking Reset Error: $e");
          }
        }
      }

      notifyListeners();
    }
  }

  // Helper to safely fully clear everything and notify UI
  Future<void> cancelAndClearRoute() async {
    _liveLocationSub?.cancel();
    _liveLocationSub = null;
    // 1. Clear MapLibre Native Layers (Lines AND ETA Pills)
    if (controller != null) {
      // 1. SECURE LAYER CLEANUP (Must be removed first to free up sources)
      try {
        await controller!.removeLayer('primary-casing');
      } catch (_) {}
      try {
        await controller!.removeLayer('primary-core');
      } catch (_) {}
      try {
        await controller!.removeLayer('primary-shine');
      } catch (_) {}
      try {
        await controller!.removeLayer('primary-walk-layer');
      } catch (_) {}
      try {
        await controller!.removeLayer('connectors-layer');
      } catch (_) {}

      for (int i = 0; i < 5; i++) {
        try {
          await controller!.removeLayer('route-layer-$i');
        } catch (_) {}
        try {
          await controller!.removeLayer('alt-walk-layer-$i');
        } catch (_) {}
        try {
          await controller!.removeLayer('time-tag-layer-$i');
        } catch (_) {}
      }

      // 2. SECURE SOURCE CLEANUP (Only safe to remove after layers are dead)
      try {
        await controller!.removeSource('primary-source');
      } catch (_) {}
      try {
        await controller!.removeSource('connectors-source');
      } catch (_) {}

      for (int i = 0; i < 5; i++) {
        try {
          await controller!.removeSource('route-source-$i');
        } catch (_) {}
        try {
          await controller!.removeSource('alt-source-$i');
        } catch (_) {}
        try {
          await controller!.removeSource('time-tag-source-$i');
        } catch (_) {}
      }

      // Also clear destination pin circle if it exists
      await clearNativeDestinationPin();

      // Keep legacy cleanup just in case
      try {
        await controller!.removeLayer('selected-destination-layer');
      } catch (_) {}
      try {
        await controller!.removeSource('selected-destination-source');
      } catch (_) {}

      // Remove the manual dropped pin or search symbol layer
      await engine.layers?.removeSearchPin();
    }

    // 2. Reset all routing state variables to null/empty
    _drawnRoutesCount = 0;
    isRouteCalculated = false;
    _currentRouteResult = null;
    _lastRouteData = null;
    targetDestination = null;
    targetLocation = null;
    isCinematicSearch = false;
    _tappedPlaceFromMap = null;
    _isDestinationSelected = false;
    isActiveNavigation = false;
    engine.setUIState(MapUIState.idle);
    await updatePuckVisibility();
    currentNavMode = 'driving';

    // 🧭 State Machine: Reset to idle
    engine.setUIState(MapUIState.idle);

    // 🚀 Cinematic Camera Reset
    if (controller != null && currentLocation != null) {
      controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: currentLocation!,
            zoom: 15.0, // Comfortable default zoom
            tilt: 0.0, // Strictly reset to flat 2D
            bearing: 0.0, // Strictly reset rotation
          ),
        ),
        duration:
            const Duration(milliseconds: 1200), // Smooth 1.2s premium flight
      );

      // Reset modes
      await setTrackingMode(
        MyLocationTrackingMode.tracking,
      );
    }

    // 🌟 Explicitly Restore All Dimmed/Hidden Background Layers & Hide Puck
    await _toggleFocusModeLayers(false);
    await hideNavigationPuck();

    // 3. Notify the UI to rebuild (This brings the Search Bar back!)
    notifyListeners();
  }

  // Helper to calculate camera bounds
  LatLngBounds _calculateBounds(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  DateTime? _lastSearchTime;
  static const Duration _searchDebounce = Duration(milliseconds: 500);

  String? _lastError;
  bool _isLoading = false;

  LatLng? targetLocation;
  bool isCinematicSearch = false;

  LatLng? targetStationLocation;
  String? targetStationName;
  bool isNavigatingToStation = false;

  String? currentRouteDistance;
  String? currentRouteETA;

  PlaceModel? _tappedPlaceFromMap;
  PlaceModel? get tappedPlaceFromMap => _tappedPlaceFromMap;

  LatLng? _currentMapCenter;
  LatLng? get currentMapCenter => _currentMapCenter;

  String? _currentCityName;
  String? get currentCityName => _currentCityName;
  double _currentZoomLevel = 16.0;
  double get currentZoomLevel => _currentZoomLevel;

  MapThemeType _currentTheme = MapThemeType.dark;
  MapThemeType get currentTheme => _currentTheme;
  void setTheme(MapThemeType theme) {
    _currentTheme = theme;
    if (controller != null) {
      if (_lastRouteData != null) {
        // Explicitly clear layers to prevent memory leaks from overlaying
        RouteVisualizer.clearRoute(controller).then((_) {
          drawNativeRoute(_lastRouteData!.allRoutesCoordinates);
        });
      }
    }
  }

  RouteResult? _lastRouteData;
  LatLng? targetDestination;

  bool _isDestinationSelected = false;
  bool get isDestinationSelected => _isDestinationSelected;

  void setTargetDestination(LatLng? target) {
    targetDestination = target;
    notifyListeners();
  }

  bool isFlying = false;

  String? mapSelectionPlaceType;

  void setMapSelectionMode(String? type) {
    mapSelectionPlaceType = type;
    notifyListeners();
  }

  bool _isEditingHistory = false;
  bool get isEditingHistory => _isEditingHistory;

  void setIsEditingHistory(bool value) {
    if (_isEditingHistory != value) {
      _isEditingHistory = value;
      notifyListeners();
    }
  }

  Set<String> selectedForDeletion = {};

  List<PlaceModel> recentSearches = [];

  void updateRecentSearches(List<PlaceModel> newSearches) {
    recentSearches.clear();
    recentSearches.addAll(newSearches);
    notifyListeners();
  }

  Future<void> deleteSingleHistory(PlaceModel place) async {
    recentSearches.removeWhere((p) => p.placeId == place.placeId);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      recentSearches.map((p) => p.toJson()).toList(),
    );
    await prefs.setString('recent_searches', encoded);

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client.from('search_history').delete().match({
          'user_id': user.id,
          'name': place.name,
        });
      } catch (_) {}
    }
  }

  Future<void> deleteSelectedHistory() async {
    recentSearches.removeWhere(
      (place) => selectedForDeletion.contains(place.placeId),
    );
    selectedForDeletion.clear();
    _isEditingHistory = false;
    notifyListeners(); // Force UI update

    // Update Local Storage
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      recentSearches.map((p) => p.toJson()).toList(),
    );
    await prefs.setString('recent_searches', encoded);

    // Note: Delete selected IDs from Supabase if logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        // Just clear everything for this user for now to keep it simple, or loop and delete.
        // Doing a mass delete is better but requires place.name list.
      } catch (_) {}
    }
  }

  Future<void> deleteAllHistory() async {
    recentSearches.clear();
    selectedForDeletion.clear();
    _isEditingHistory = false;
    notifyListeners(); // Force UI update

    // Nuke Local Storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');

    // Note: Clear all user history from Supabase if logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client.from('search_history').delete().match({
          'user_id': user.id,
        });
      } catch (_) {}
    }
  }

  void toggleDeletionSelection(String placeId) {
    if (selectedForDeletion.contains(placeId)) {
      selectedForDeletion.remove(placeId);
    } else {
      selectedForDeletion.add(placeId);
    }
    notifyListeners();
  }

  void clearDeletionSelections() {
    selectedForDeletion.clear();
    notifyListeners();
  }

  // Stops the camera instantly if the user taps the screen
  void stopCameraFlight() {
    if (isFlying && controller != null) {
      final currentPos = controller!.cameraPosition;
      if (currentPos != null) {
        // Moving to the exact current position forces the ongoing animation to halt
        controller!.moveCamera(CameraUpdate.newCameraPosition(currentPos));
      }
      isFlying = false;
      debugPrint("Drone Flight Interrupted by User!");
      // Assuming AppHaptics is available. If not, remove this line.
      AppHaptics.lightImpact();
    }
  }

  String currentNavMode = 'driving';

  Future<void> setNavMode(BuildContext context, String mode) async {
    if (currentNavMode == mode) return; // Ignore if same mode

    currentNavMode = mode;
    notifyListeners(); // 🚀 Instantly update the button UI to show the active state

    // 🚀 CRITICAL FIX: If a destination is active, recalculate and redraw the route instantly!
    if (isDestinationSelected && targetDestination != null) {
      await triggerDirectionsFlow(context);
    }
  }

  void setDestinationSelected(bool value) {
    if (_isDestinationSelected != value) {
      _isDestinationSelected = value;

      // 🧭 State Machine: place selected → placeSelected, deselected → idle
      if (value && engine.mapUIState.value == MapUIState.idle) {
        engine.setUIState(MapUIState.placeSelected);
      } else if (!value &&
          engine.mapUIState.value == MapUIState.placeSelected) {
        engine.setUIState(MapUIState.idle);
      }

      notifyListeners();
    }
  }

  void startTurnByTurnNavigation() {
    if (_lastRouteData != null) {
      engine.navigation.startNavigation(_lastRouteData!);

      _liveLocationSub?.cancel();
      _liveLocationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ),
      ).listen((pos) {
        engine.navigation.processLocationUpdate(pos);
      });

      AppHaptics.success();
    }
  }

  // 🚨 MULTIPLE NEARBY PINS TRACKER
  final List<Circle> _nearbyCircles = [];
  final List<Symbol> _nearbyLabels = [];

  final ValueNotifier<bool> isSpeaking = ValueNotifier(false);
  Timer? _glowTimer;
  StreamSubscription<Position>? _liveLocationSub;

  MapProvider() {
    engine.state.addListener(() {
      notifyListeners();
    });

    engine.navigation.voiceInstruction.addListener(() {
      final text = engine.navigation.voiceInstruction.value;
      if (text != null) {
        isSpeaking.value = true;
        debugPrint("🗣️ TTS Triggered: $text");

        final int wordCount = text.split(' ').length;
        final int speakDurationMs = (wordCount * 400) + 800;

        _glowTimer?.cancel();
        _glowTimer = Timer(Duration(milliseconds: speakDurationMs), () {
          isSpeaking.value = false;
        });
      }
    });

    engine.navigation.isGpsLost.addListener(() {
      final context = ToastService.navigatorKey.currentContext;
      if (context != null) {
        if (engine.navigation.isGpsLost.value == true) {
          ToastService.showError(context, "Offline Glide Active");
        } else {
          ToastService.showSuccess(context, "GPS Signal Restored");
        }
      }
    });

    engine.navigation.remainingPolyline.addListener(() {
      final points = engine.navigation.remainingPolyline.value;
      if (points.isNotEmpty && engine.navigation.isNavigating.value) {
        engine.layers?.updateRouteSource(points);
      }
    });

    // 🧭 Forward UI state machine changes to ChangeNotifier listeners
    engine.mapUIState.addListener(() {
      final state = engine.mapUIState.value;
      _toggleFuelStationsVisibility(state == MapUIState.navigating);
      if ((state == MapUIState.navigating || state == MapUIState.routeDrawn) &&
          currentLocation != null) {
        // Show initial puck before the first native location update fires
        updateNavigationPuck(currentLocation!,
            engine.locService?.currentPosition?.heading ?? 0.0);
      }
      notifyListeners();
    });

    loadSearchHistory();
  }

  Future<void> loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('recent_searches');

    if (historyJson != null) {
      final List<dynamic> decoded = jsonDecode(historyJson);
      recentSearches =
          decoded.map((item) => PlaceModel.fromJson(item)).toList();
    }

    // Optional: Sync from Supabase if logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Note: Fetch from Supabase and merge with local list, then re-save locally
    }
    notifyListeners();
  }

  Future<void> saveNewSearch(PlaceModel newPlace) async {
    // Prevent duplicates
    recentSearches.removeWhere((p) => p.placeId == newPlace.placeId);
    recentSearches.insert(0, newPlace); // Add to top

    // Keep only last 10-15 searches to save space
    if (recentSearches.length > 15) recentSearches.removeLast();
    notifyListeners();

    // Save Locally
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      recentSearches.map((p) => p.toJson()).toList(),
    );
    await prefs.setString('recent_searches', encoded);

    // Sync to Supabase if logged in
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Note: Insert/Upsert into your Supabase 'recent_searches' table
      try {
        await Supabase.instance.client.from('search_history').insert({
          'user_id': user.id,
          'place_id': newPlace.placeId,
          'name': newPlace.name,
          'address': newPlace.address,
          'latitude': newPlace.latitude,
          'longitude': newPlace.longitude,
          'category': newPlace.categories.isNotEmpty
              ? newPlace.categories.first
              : 'unknown',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }
  }

  /// Public accessor for the UI state machine.
  ValueNotifier<MapUIState> get mapUIState => engine.mapUIState;
  MapUIState get currentUIState => engine.mapUIState.value;

  void setTappedPlace(PlaceModel place) {
    _tappedPlaceFromMap = place;
    setDestinationSelected(true);
    notifyListeners();
  }

  void clearTappedPlace() {
    _tappedPlaceFromMap = null;
    notifyListeners();
  }

  Future<void> handleMapTap(Point<double> point, LatLng latLng) async {
    if (!_isMapReady) return;

    await cancelAndClearRoute();
    await drawDroppedPin(latLng);

    AppHaptics.heavyImpact();

    // Set placeholder immediately to avoid blocking UI
    final temporaryPlace = PlaceModel(
      placeId: 'temp_${latLng.latitude}_${latLng.longitude}',
      name: 'Fetching address...',
      address: 'Please wait',
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      categories: const [],
    );
    setTappedPlace(temporaryPlace);

    _isDestinationSelected = true;
    targetDestination = latLng;
    engine.setUIState(MapUIState.placeSelected);
    notifyListeners();

    // Fire-and-forget network call in background
    Future.microtask(() async {
      try {
        final PlaceModel place = await PlaceEnrichmentService().reverseGeocode(
          latLng.latitude,
          latLng.longitude,
        );
        setTappedPlace(place);
        saveNewSearch(place);

        final locService = engine.locService;
        if (locService != null) {
          final originAddr = locService.currentAddressName;
          if (originAddr == null ||
              originAddr.isEmpty ||
              originAddr == "Locating...") {
            final pos = locService.currentPosition;
            if (pos != null) {
              try {
                final currentPlace = await PlaceEnrichmentService()
                    .reverseGeocode(pos.latitude, pos.longitude);
                locService.setCurrentAddressName(currentPlace.address.isNotEmpty
                    ? currentPlace.address
                    : currentPlace.name);
              } catch (e) {
                debugPrint("Origin Reverse Geocode Failed: $e");
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Tap Handler Reverse Geocode Error: $e");
        // Fallback to coordinates on failure
        final fallback = PlaceModel(
          placeId: temporaryPlace.placeId,
          name: "Dropped Pin",
          address: "${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}",
          latitude: latLng.latitude,
          longitude: latLng.longitude,
          categories: const [],
        );
        setTappedPlace(fallback);
      }
    });
  }

  Future<void> drawDroppedPin(LatLng latLng) async {
    await addNativeDestinationPin(latLng);
  }

  Future<void> clearSearchSession(BuildContext context) async {
    targetDestination = null;
    setDestinationSelected(false);

    if (controller != null) {
      // 1. Clear the visual polyline layers completely
      await RouteVisualizer.clearRoute(controller);

      // 2. Remove the manual dropped pin or search symbol layer
      await engine.layers?.removeSearchPin();

      await clearNativeDestinationPin();
    }

    clearTappedPlace();

    // 🧭 State Machine: Full reset to idle
    await engine.resetUIState();
    _lastRouteData = null;
    isActiveNavigation = false;

    notifyListeners(); // Force UI components and FAB to revert to standard states
    debugPrint("Map session completely cleared.");
  }

  // 🚀 MASTER ROUTING FUNCTION (SMART DESTINATION DETECTOR)
  Future<void> calculateAndDrawRoute(BuildContext context) async {
    if (!_isMapReady) return;

    debugPrint("🚀 Route calculation started...");

    final locService = Provider.of<GlobalLocationService>(
      context,
      listen: false,
    );
    final currentLocation = locService.currentPosition;

    // 🧠 SMART DESTINATION LOGIC: Check both Tapped Places AND Search Targets
    LatLng? destinationCoords;
    if (tappedPlaceFromMap != null) {
      destinationCoords = LatLng(
        tappedPlaceFromMap!.latitude,
        tappedPlaceFromMap!.longitude,
      );
      debugPrint("📍 Using Tapped Place as destination: $destinationCoords");
    } else if (targetLocation != null) {
      destinationCoords = targetLocation;
      debugPrint("📍 Using Search Target as destination: $destinationCoords");
    }

    if (currentLocation == null) {
      debugPrint("❌ Routing Error: Current Location is missing!");
      AppHaptics.error();
      return;
    }

    if (destinationCoords == null) {
      debugPrint(
        "❌ Routing Error: Destination missing! Neither tappedPlace nor targetLocation is set.",
      );
      AppHaptics.error();
      return;
    }

    _setLoading(true);
    AppHaptics.lightImpact(); // Processing Start

    try {
      final origin = LatLng(
        currentLocation.latitude,
        currentLocation.longitude,
      );
      debugPrint("🛣️ Fetching route from $origin to $destinationCoords...");

      // Fetch from Routing API
      final routeData = await _routingService.getRoute(
        origin,
        destinationCoords,
      );

      if (routeData != null && routeData.allRoutesCoordinates.isNotEmpty) {
        _lastRouteData = routeData;
        _currentRouteResult = routeData;
        List<LatLng> routePoints = routeData.allRoutesCoordinates.first;

        if (routePoints.isNotEmpty) {
          debugPrint(
            "🔍 MAP PROVIDER AUDIT (1st Point): Lat=${routePoints.first.latitude}, Lng=${routePoints.first.longitude}",
          );
        }

        debugPrint("✅ Route decoded successfully. Drawing on map...");

        // 🚀 2. Seedha draw kar de, koi FLIP ki zarurat nahi hai!
        await drawNativeRoute(routeData.allRoutesCoordinates);

        AppHaptics.success();
      } else {
        debugPrint("❌ Routing API Error: Route not found or API failed.");
        _lastError = "Could not fetch route. Please try again.";
        AppHaptics.error();
      }
    } catch (e) {
      debugPrint("❌ Exception in Calculate Route: $e");
      _lastError = "An error occurred while routing.";
      AppHaptics.error();
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  // 🚨 FIND AND SHOW MULTIPLE NEARBY PINS
  Future<void> findAndShowNearby(String category, BuildContext context) async {
    if (!_isMapReady) return;
    _setLoading(true);

    try {
      final locService = Provider.of<GlobalLocationService>(
        context,
        listen: false,
      );
      if (locService.currentPosition == null) {
        await locService.forceRefreshLocation();
      }
      final pos = locService.currentPosition;
      if (pos == null) throw Exception("GPS Unavailable");

      final MasterSearchService searchService = MasterSearchService();
      final places = await searchService.getNearbyPlaces(
        LatLng(pos.latitude, pos.longitude),
        category,
      );

      await clearNearbyPins();

      if (places.isNotEmpty) {
        double minLat = pos.latitude, maxLat = pos.latitude;
        double minLng = pos.longitude, maxLng = pos.longitude;

        for (var place in places) {
          minLat = math.min(minLat, place.latitude);
          maxLat = math.max(maxLat, place.latitude);
          minLng = math.min(minLng, place.longitude);
          maxLng = math.max(maxLng, place.longitude);

          final circle = await controller?.addCircle(
            CircleOptions(
              geometry: LatLng(place.latitude, place.longitude),
              circleRadius: 8.0,
              circleColor: "#00E5FF",
              circleStrokeWidth: 2.5,
              circleStrokeColor: "#FFFFFF",
            ),
          );
          if (circle != null) _nearbyCircles.add(circle);

          final label = await controller?.addSymbol(
            SymbolOptions(
              geometry: LatLng(place.latitude, place.longitude),
              textField: place.name,
              textOffset: const Offset(0, 1.5),
              textColor:
                  _currentTheme == MapThemeType.light ? '#000000' : '#FFFFFF',
              textHaloColor:
                  _currentTheme == MapThemeType.light ? '#FFFFFF' : '#000000',
              textHaloWidth: 1.5,
              textSize: 13.0,
            ),
          );
          if (label != null) _nearbyLabels.add(label);
        }

        try {
          await controller?.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat - 0.005, minLng - 0.005),
                northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
              ),
              left: 50,
              top: 100,
              right: 50,
              bottom: 120,
            ),
            duration: const Duration(milliseconds: 1500),
          );
        } catch (e) {
          debugPrint(
              "⚠️ Bounds fit failed (screen too small), falling back to center focus: $e");
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          await controller?.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: LatLng(centerLat, centerLng), zoom: 12.0)));
        }
      } else {
        debugPrint("No places found for $category");
      }
    } catch (e) {
      debugPrint("Find Nearby Error: $e");
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> clearNearbyPins() async {
    for (var circle in _nearbyCircles) {
      await controller?.removeCircle(circle);
    }
    for (var label in _nearbyLabels) {
      await controller?.removeSymbol(label);
    }
    _nearbyCircles.clear();
    _nearbyLabels.clear();
  }

  void updateMapCenter(LatLng center, double zoom) {
    if (!_isMapReady) return;
    bool hasChanged = false;
    if (_currentMapCenter?.latitude != center.latitude ||
        _currentMapCenter?.longitude != center.longitude) {
      _currentMapCenter = center;
      hasChanged = true;
    }
    if (_currentZoomLevel != zoom) {
      _currentZoomLevel = zoom;
      hasChanged = true;
    }
    if (hasChanged) {
      notifyListeners();
    }
  }

  void updateCityName(String name) {
    _currentCityName = name;
  }

  Future<void> startStationNavigation(
    LatLng currentLoc,
    LatLng stationLoc,
    String stationName,
  ) async {
    if (!_isMapReady) return;
    _setLoading(true);
    targetStationLocation = stationLoc;
    targetStationName = stationName;
    isNavigatingToStation = true;
    notifyListeners();

    try {
      RouteResult? routeData = await _routingService.getRoute(
        currentLoc,
        stationLoc,
      );

      if (routeData != null) {
        currentRouteDistance = "${routeData.distanceKm.toStringAsFixed(1)} km";
        currentRouteETA = "${routeData.durationMins} mins";

        await clearRouteData();

        _originMarker = await controller?.addCircle(
          CircleOptions(
            geometry: currentLoc,
            circleRadius: 7.0,
            circleColor: "#FF3B30",
            circleStrokeWidth: 2.5,
            circleStrokeColor: "#FFFFFF",
          ),
        );
        _currentMarker = await controller?.addCircle(
          CircleOptions(
            geometry: stationLoc,
            circleRadius: 7.0,
            circleColor: "#00E5FF",
            circleStrokeWidth: 2.5,
            circleStrokeColor: "#FFFFFF",
          ),
        );

        if (controller != null) {
          await drawNativeRoute(routeData.allRoutesCoordinates);
        }

        engine.navigation.startNavigation(routeData);
        _liveLocationSub?.cancel();
        _liveLocationSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 2,
          ),
        ).listen((pos) {
          engine.navigation.processLocationUpdate(pos);
        });

        double minLat = math.min(currentLoc.latitude, stationLoc.latitude);
        double maxLat = math.max(currentLoc.latitude, stationLoc.latitude);
        double minLng = math.min(currentLoc.longitude, stationLoc.longitude);
        double maxLng = math.max(currentLoc.longitude, stationLoc.longitude);

        try {
          await controller?.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat - 0.005, minLng - 0.005),
                northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
              ),
              left: 50,
              top: 100,
              right: 50,
              bottom: 120,
            ),
            duration: const Duration(milliseconds: 1500),
          );
        } catch (e) {
          debugPrint(
              "⚠️ Bounds fit failed (screen too small), falling back to center focus: $e");
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          await controller?.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: LatLng(centerLat, centerLng), zoom: 12.0)));
        }
      } else {
        await _fallbackFlyTo(stationLoc);
      }
    } catch (e) {
      await _fallbackFlyTo(stationLoc);
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> _fallbackFlyTo(LatLng target) async {
    await flyTo(target, zoom: 16.5, tilt: 50.0);
    await _dropMarker(target);
  }

  void checkIfArrived(
    double currentLat,
    double currentLng,
    Function onArrived,
  ) {
    if (!isNavigatingToStation || targetStationLocation == null) return;
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 -
        c((targetStationLocation!.latitude - currentLat) * p) / 2 +
        c(currentLat * p) *
            c(targetStationLocation!.latitude * p) *
            (1 - c((targetStationLocation!.longitude - currentLng) * p)) /
            2;
    double distanceInMeters = 12742 * math.asin(math.sqrt(a)) * 1000;
    if (distanceInMeters <= 50.0) {
      stopStationNavigation();
      onArrived();
    }
  }

  Future<void> clearRouteData() async {
    if (!_isMapReady) return;

    await clearNearbyPins();

    if (controller != null) {
      await RouteVisualizer.clearRoute(controller);
    }

    // 🚀 FIXED: Ensure custom GL route is also removed when clearing data
    await engine.layers?.removeRoute();

    try {
      if (_currentMarker != null) {
        await controller?.removeCircle(_currentMarker!);
        _currentMarker = null;
      }
      if (_originMarker != null) {
        await controller?.removeCircle(_originMarker!);
        _originMarker = null;
      }
    } catch (e) {
      debugPrint("Error removing markers: $e");
    }
  }

  void stopStationNavigation() async {
    isNavigatingToStation = false;
    targetStationLocation = null;
    targetStationName = null;
    await clearRouteData();
    notifyListeners();
  }

  Future<void> markCurrentPosition(BuildContext context) async {
    if (!_isMapReady) return;
    _setLoading(true);
    try {
      final locService = Provider.of<GlobalLocationService>(
        context,
        listen: false,
      );
      if (!locService.hasValidLocation) {
        await locService.initializeEcoLocation();
      }
      final pos = locService.currentPosition;
      if (pos == null) return;
      await clearRouteData();
      await controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: 17.0,
            tilt: 45.0,
            bearing: 0,
          ),
        ),
        duration: const Duration(milliseconds: 1500),
      );
    } catch (e) {
      debugPrint("Mark Current Position Error: $e");
    } finally {
      _setLoading(false);
    }
  }

  Future<void> searchAndNavigate(String query) async {
    if (!_isMapReady) return;
    final now = DateTime.now();
    if (_lastSearchTime != null &&
        now.difference(_lastSearchTime!) < _searchDebounce) {
      return;
    }
    _lastSearchTime = now;
    _setLoading(true);
    try {
      LatLng? target;
      if (query.contains(',')) {
        final parts = query.split(',');
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat != null && lng != null) target = LatLng(lat, lng);
      }
      target ??= await PlaceService.getCoordinates(query);
      if (target != null) {
        await clearRouteData();
        targetLocation = target;
        isCinematicSearch = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Search and Navigate Error: $e");
    } finally {
      _setLoading(false);
    }
  }

  void clearTargetLocation() {
    targetLocation = null;
    targetDestination = null;
    isCinematicSearch = false;
    notifyListeners();
  }

  Future<void> flyToPlace(double lat, double lng) async {
    if (!_isMapReady) return;
    final target = LatLng(lat, lng);
    targetDestination = target;
    notifyListeners(); // 🧭 Triggers Consumer → AnimatedMapPin overlay appears

    isFlying = true;
    try {
      // 1. Force native layer to drop tracking immediately
      await controller?.updateMyLocationTrackingMode(MyLocationTrackingMode.none);

      // 2. CRITICAL FIX: Event loop breaker to safely disengage WebGL tracking lock
      await Future.delayed(const Duration(milliseconds: 50));

      await controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 16.0));

      AppHaptics.mediumImpact();
    } catch (e) {
      debugPrint("⚠️ flyToPlace Error: $e");
    } finally {
      isFlying = false;
      notifyListeners(); // 🚀 Force a fresh frame notify so the UI perfectly syncs when camera stops
    }
  }

  Future<void> flyTo(
    LatLng target, {
    double zoom = 16.0,
    double tilt = 60.0,
  }) async {
    if (!_isMapReady) return;
    try {
      await controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom, tilt: tilt, bearing: 0),
        ),
        duration: const Duration(milliseconds: 1500),
      );
      await _dropMarker(target);
    } catch (e) {
      debugPrint("FlyTo Error: $e");
    }
  }

  Future<void> _dropMarker(LatLng target) async {
    try {
      _currentMarker = await controller?.addCircle(
        CircleOptions(
          geometry: target,
          circleRadius: 7.0,
          circleColor: "#00E5FF",
          circleStrokeWidth: 2.5,
          circleStrokeColor: "#FFFFFF",
        ),
      );
      notifyListeners();
    } catch (e) {
      debugPrint("Drop Marker Error: $e");
    }
  }

  Future<void> triggerDirectionsFlow(BuildContext context) async {
    if (targetDestination == null || controller == null) return;

    // 1. Fetch Current Location (Origin)
    final locService = Provider.of<GlobalLocationService>(
      context,
      listen: false,
    );
    final pos = locService.currentPosition;
    if (pos == null) {
      debugPrint("GPS not available for routing.");
      return;
    }
    final originLoc = LatLng(pos.latitude, pos.longitude);

    // 2. Fetch Route Data
    try {
      final route = await _routingService.getRoute(
        originLoc,
        targetDestination!,
        mode: currentNavMode,
      );

      if (route != null) {
        _lastRouteData = route;
        _currentRouteResult = route; // 🚨 Ensure this is synced

        // 3. Draw the Route on the Map
        await drawNativeRoute(route.allRoutesCoordinates);

        isRouteCalculated = true; // 🚨 Missing flag causing the card to hide
        // 🧭 State Machine: Route drawn successfully
        engine.setUIState(MapUIState.routeDrawn);
        notifyListeners(); // 🚨 Missing trigger causing UI to not rebuild

        // 4. Smoothly animate camera to fit the entire route bounds
        final double minLat = math.min(
          originLoc.latitude,
          targetDestination!.latitude,
        );
        final double maxLat = math.max(
          originLoc.latitude,
          targetDestination!.latitude,
        );
        final double minLng = math.min(
          originLoc.longitude,
          targetDestination!.longitude,
        );
        final double maxLng = math.max(
          originLoc.longitude,
          targetDestination!.longitude,
        );

        try {
          await controller!.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng),
              ),
              left: 50,
              right: 50,
              top: 100,
              bottom:
                  120, // Reduced from 400 padding to account for the UI sheet
            ),
            duration: const Duration(milliseconds: 1200),
          );
        } catch (e) {
          debugPrint(
              "⚠️ Bounds fit failed (screen too small), falling back to center focus: $e");
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          await controller!.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: LatLng(centerLat, centerLng), zoom: 12.0)));
        }
      }
    } catch (e) {
      debugPrint("Routing Error: $e");
    }
  }

  Future<void> startActiveNavigation(BuildContext context) async {
    if (controller == null || targetDestination == null) return;

    final locService = Provider.of<GlobalLocationService>(
      context,
      listen: false,
    );
    final pos = locService.currentPosition;
    if (pos == null) {
      debugPrint("Cannot start navigation: User location unknown.");
      return;
    }

    // Use existing route data - DO NOT fetch again (Redundant API call removed)
    if (_currentRouteResult == null) {
      debugPrint("Cannot start navigation: No route data.");
      return;
    }

    // Set state
    isActiveNavigation = true;
    notifyListeners();

    AppHaptics.heavyImpact();

    // Cinematic Flow 3 - Start Navigation Focus
    await setTrackingMode(MyLocationTrackingMode.trackingCompass);
    await controller!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 18.0,
          tilt: 50.0,
        ),
      ),
      duration: const Duration(milliseconds: 1200),
    );

    // 🚀 Delegate to MapEngine's active navigation lifecycle
    await engine.startActiveNavigation(
        _currentRouteResult!, targetDestination!, currentNavMode);
  }

  void endActiveNavigation() {
    if (!isActiveNavigation) return;

    engine.navigation.stopNavigation();
    isActiveNavigation = false;
    _currentRouteResult = null;
    engine.camera?.setCameraForMode(CameraMode.explore);
    engine.layers?.resetAllLayers(); // Clear navigation styling if needed
    notifyListeners();
  }

  Future<void> autoDrawRouteTo(LatLng destination, BuildContext context) async {
    if (controller == null) return;

    // 1. Get current location
    final locService = Provider.of<GlobalLocationService>(
      context,
      listen: false,
    );
    final currentPos = locService.currentPosition;

    if (currentPos == null) {
      debugPrint('Auto-Route failed: User location not available.');
      return;
    }

    final originLoc = LatLng(currentPos.latitude, currentPos.longitude);

    // 2. Fetch and draw the route silently
    try {
      final route = await _routingService.getRoute(
        originLoc,
        destination,
        mode: currentNavMode,
      );

      if (route != null) {
        _lastRouteData = route;
        _currentRouteResult = route;
        targetDestination = destination;
        await drawNativeRoute(route.allRoutesCoordinates);

        // 🧭 State Machine: Route drawn successfully
        engine.setUIState(MapUIState.routeDrawn);

        debugPrint('Auto-Route drawn successfully!');
      }
    } catch (e) {
      debugPrint('Auto-Route drawing error: $e');
    }
  }

  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _liveLocationSub?.cancel();
    _liveLocationSub = null;
    _pinAnimController?.dispose();
    engine.dispose();
    super.dispose();
  }
}

Future<Uint8List> _generateETAPillImage(String text, bool isPrimary) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);

  // 🚨 TRANSLUCENT GLASS EFFECT
  // Apple Blue for primary, Dark Grey for alternates, both slightly transparent
  final Color bgColor = isPrimary
      ? const Color(0xFF0A84FF).withValues(alpha: 0.85)
      : const Color(0xFF2C2C2E).withValues(alpha: 0.85);

  // High-res text for crisp rendering
  final TextSpan span = TextSpan(
    text: text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 36,
      fontWeight: FontWeight.bold,
    ),
  );
  final TextPainter tp = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
  );
  tp.layout();

  // Padding
  const double paddingX = 28.0; // Slightly wider for the perfect pill look
  const double paddingY = 16.0;
  final double width = tp.width + (paddingX * 2);
  final double height = tp.height + (paddingY * 2);

  // 🚨 PERFECT PILL SHAPE (Radius = height / 2)
  final RRect rrect = RRect.fromLTRBR(
    0,
    0,
    width,
    height,
    Radius.circular(height / 2),
  );

  // Draw translucent background
  canvas.drawRRect(rrect, Paint()..color = bgColor);

  // Draw subtle glassy border
  canvas.drawRRect(
    rrect,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5,
  );

  // Center the text
  tp.paint(canvas, Offset((width - tp.width) / 2, (height - tp.height) / 2));

  final ui.Image image = await recorder.endRecording().toImage(
        width.toInt(),
        height.toInt(),
      );
  final ByteData? byteData = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  return byteData!.buffer.asUint8List();
}

// Fast squared distance for UI heuristics
double _fastSquaredDistance(LatLng p1, LatLng p2) {
  final dx = p1.longitude - p2.longitude;
  final dy = p1.latitude - p2.latitude;
  return dx * dx + dy * dy;
}

// Finds the point on the alternate route that is furthest from the main route
LatLng _getBestAlternateTagLocation(
  List<LatLng> mainRoute,
  List<LatLng> altRoute,
) {
  if (mainRoute.isEmpty || altRoute.isEmpty) return const LatLng(0, 0);

  double maxMinDist = -1.0;
  LatLng bestPoint = altRoute[altRoute.length ~/ 2]; // Fallback to midpoint

  // Step through alt route (step by 3 for performance)
  for (int i = 0; i < altRoute.length; i += 3) {
    LatLng altPoint = altRoute[i];
    double minLocalDist = double.infinity;

    // Find the closest point on the main route to this alt point
    for (int j = 0; j < mainRoute.length; j += 3) {
      double dist = _fastSquaredDistance(altPoint, mainRoute[j]);
      if (dist < minLocalDist) {
        minLocalDist = dist;
      }
    }

    // If this alt point is further away from the main route than previous points, save it
    if (minLocalDist > maxMinDist) {
      maxMinDist = minLocalDist;
      bestPoint = altPoint;
    }
  }
  return bestPoint;
}
