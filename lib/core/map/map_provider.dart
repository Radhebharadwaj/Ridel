import 'dart:math' as math;
import 'dart:math' show Point;
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:ridel/features/commute/shared/services/database_helper.dart';
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
  int _routingSessionCounter = 0;

  // 🚀 STYLE BARRIER FLAGS
  bool isStyleFullyLoaded = false;
  
  void resetPuckInitialization() {
    // Intentionally empty. Puck relies purely on onStyleLoadedCallback now.
  }

  // 🚀 GLOBAL SHEET CONTROLLER
  final DraggableScrollableController sheetController =
      DraggableScrollableController();

  // 🚀 DYNAMIC DPI SCALER: Leaves Web untouched, boosts Mobile by 2x-2.5x
  double get mapItemScale => kIsWeb ? 1.0 : 2.5;

  // Multi-stop tracking
  List<PlaceModel> intermediateStops = [];

  bool isAddingStopMode = false;
  bool isDropPinMode = false;

  bool _is3D = false;
  bool get is3D => _is3D;

  void setIs3D(bool value) {
    if (_is3D != value) {
      _is3D = value;
      notifyListeners();
    }
  }

  void setAddingStopMode(bool value) {
    if (isAddingStopMode != value) {
      isAddingStopMode = value;
      notifyListeners();
    }
  }

  void setDropPinMode(bool value) {
    if (isDropPinMode != value) {
      isDropPinMode = value;
      notifyListeners();
    }
  }

  void addIntermediateStop(PlaceModel place) {
    if (intermediateStops.length < 3) {
      // Limit to 3 stops for premium UX
      intermediateStops.add(place);
      notifyListeners();
    }
  }

  void removeIntermediateStop(int index) {
    if (index >= 0 && index < intermediateStops.length) {
      intermediateStops.removeAt(index);
      notifyListeners();
    }
  }

  void reorderIntermediateStops(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1; // Standard Flutter reorder adjustment
    }
    final PlaceModel item = intermediateStops.removeAt(oldIndex);
    intermediateStops.insert(newIndex, item);
    notifyListeners();

    // Auto-recalculate the full route with the new sequence
    if (targetDestination != null) {
      final context = ToastService.navigatorKey.currentContext;
      if (context != null) {
        calculateAndDrawNativeRoute(context, currentNavMode);
      }
    }
  }

  static Future<Uint8List> loadAndResizeImage(
      String assetPath, int targetWidth) async {
    final ByteData data = await rootBundle.load(assetPath);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: targetWidth, // CRITICAL: Locks the pixel width strictly
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? resizedData =
        await fi.image.toByteData(format: ui.ImageByteFormat.png);
    return resizedData!.buffer.asUint8List();
  }

  MapLibreMapController? get controller => engine.mapController;
  bool get _isMapReady => controller != null;

  // 🚀 CRITICAL FIX: Expose location permission state to the UI layer!
  bool get hasLocationPermission {
    return engine.locService?.hasLocationPermission ?? false;
  }

  // 🚀 TWO-KEY GATEKEEPER FOR MAP PROVIDER
  double _getClampedZoom(double requestedZoom) {
    final pos = engine.locService?.currentPosition;
    final bool isRealGps = pos != null && 
                           !pos.isMocked && 
                           hasLocationPermission && 
                           pos.accuracy <= 150.0 &&
                           pos.accuracy > 0.0;
    
    // Check dummy coordinates as well
    final bool isDummyCenter = pos != null && (
        (pos.latitude.toStringAsFixed(4) == "28.6139" && pos.longitude.toStringAsFixed(4) == "77.2090") || 
        (pos.latitude.toStringAsFixed(4) == "21.1458" && pos.longitude.toStringAsFixed(4) == "79.0882") || 
        (pos.latitude == 0.0 && pos.longitude == 0.0));
    
    if (!isRealGps || isDummyCenter) {
      return requestedZoom > 10.5 ? 10.5 : requestedZoom;
    }
    return requestedZoom;
  }

  MyLocationTrackingMode _currentTrackingMode = kIsWeb
      ? MyLocationTrackingMode.tracking
      : MyLocationTrackingMode.trackingCompass;

  MyLocationTrackingMode get currentTrackingMode => _currentTrackingMode;

  Future<void> setTrackingMode(MyLocationTrackingMode mode) async {
    if (_currentTrackingMode != mode) {
      _currentTrackingMode = mode;
      notifyListeners();
    }
    // Native tracking purged
  }

  Circle? _currentMarker;
  Circle? _originMarker;
  Symbol? _droppedPinSymbol;
  Symbol? _navPuckSymbol;

  Timer? _geocodeDebounceTimer; // 🚀 FIX: Timer for debouncing API calls
  AnimationController? _pinAnimController;

  // 1. User ka current coordinate track karne ke liye
  LatLng? currentLocation;

  void updateCurrentLocation(LatLng loc) {
    currentLocation = loc;
    // Yahan notifyListeners() mat lagana warna map lag karega
  }

  Future<void> initializeMapAndPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return; // Prompt user to turn on GPS

    LocationPermission permission = await Geolocator.checkPermission();

    // PROACTIVE REQUEST ON FIRST LAUNCH
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // INSTANT SNAP IF GRANTED
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      await initializeLocation();
    }
  }

  Future<void> initializeLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        // STEP 1: INSTANT CACHED FETCH (0ms lag)
        // 🚀 CRITICAL FIX: getLastKnownPosition is NOT supported on Web!
        if (!kIsWeb) {
          final Position? cachedPosition = await Geolocator.getLastKnownPosition();
          if (cachedPosition != null) {
            currentLocation = LatLng(cachedPosition.latitude, cachedPosition.longitude);
            notifyListeners(); // Instantly triggers initial centering in the UI
          }
        }
        
        // STEP 2: ASYNCHRONOUS HIGH-ACCURACY REFINEMENT (Short 2.5s timeout)
        // Fetch the exact live GPS coordinate in the background without blocking the map render
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(milliseconds: 2500), // Aggressive 2.5s cut-off
          ),
        ).then((Position livePosition) {
          currentLocation = LatLng(livePosition.latitude, livePosition.longitude);
          notifyListeners(); // Glides the camera smoothly to the refined live coordinates
        }).catchError((e) {
          debugPrint("⚠️ Live GPS refinement fallback to stream/cache: $e");
        });
      }
    } catch (e) {
      debugPrint("❌ Location initialization pipeline failed: $e");
    }
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

  bool get showNativeBlueDot =>
      engine.mapUIState.value == MapUIState.idle ||
      engine.mapUIState.value == MapUIState.placeSelected;

  bool get hideNativeBlueDot =>
      engine.mapUIState.value == MapUIState.navigating ||
      engine.mapUIState.value == MapUIState.routeDrawn;

  double get customPuckOpacity =>
      (engine.mapUIState.value == MapUIState.navigating ||
              engine.mapUIState.value == MapUIState.routeDrawn)
          ? 1.0
          : 0.0;

  static const String _navPuckSourceId = 'custom-nav-puck-source';
  static const String _navPuckLayerId = 'custom-nav-puck-layer';

  // 🚀 INITIALIZES THE NAVIGATION ARROW LAYER (For Turn-by-Turn Mode Only)
  Future<void> initializeNavigationPuckLayer(MapLibreMapController ctrl) async {
    try {
      await ctrl.removeLayer(_navPuckLayerId);
      await ctrl.removeSource(_navPuckSourceId);
    } catch (_) {}

    try {
      await ctrl.addSource(_navPuckSourceId, const GeojsonSourceProperties(
        data: {
          "type": "FeatureCollection",
          "features": []
        }
      ));

      // Uses the real 'nav_puck' PNG asset injected from assets/images/nav_puck.png
      await ctrl.addSymbolLayer(
        _navPuckSourceId,
        _navPuckLayerId,
        const SymbolLayerProperties(
          iconImage: 'nav_puck',
          iconSize: 1.0,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconPitchAlignment: 'map',
          iconRotationAlignment: 'map',
          iconRotate: ['get', 'bearing'], // Dynamically rotates with GPS heading!
        ),
      );
      debugPrint("✅ Navigation Arrow Layer ('nav_puck') mounted successfully!");
    } catch (e) {
      debugPrint("❌ Nav Puck Layer mount error: $e");
    }
  }

  Future<void> updateLocationRenderingMode(LatLng pos, double heading) async {
    if (controller == null) return;
    currentLocation = pos;

    // 🛑 MODE B: ACTIVE TURN-BY-TURN NAVIGATION
    if (engine.mapUIState.value == MapUIState.navigating || engine.mapUIState.value == MapUIState.routeDrawn) {
      try {
        // 1. Hide the Native MapLibre Blue Dot
        await controller!.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
      } catch (_) {}

      // 2. Feed live coordinates & bearing into our 'nav_puck.png' symbol layer
      final featureCollection = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [pos.longitude, pos.latitude]
            },
            "properties": {
              "bearing": heading // Rotates the nav_puck arrow!
            }
          }
        ]
      };
      try {
        await controller!.setGeoJsonSource(_navPuckSourceId, featureCollection);
      } catch (_) {}

      // 3. Camera Tracking Logic for Navigation
      if (isAutoTracking) {
        try {
          await controller!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: pos,
                bearing: heading,
                zoom: _getClampedZoom(16.5),
                tilt: 45.0,
              ),
            ),
          );
        } catch (e) {
          debugPrint("Camera animation error: $e");
        }
      }
    } 
    // 🔵 MODE A: NORMAL / IDLE BROWSING (Use Native MapLibre Dot with built-in pulse!)
    else {
      try {
        // 1. Clear the navigation arrow from screen
        await controller!.setGeoJsonSource(_navPuckSourceId, {
          "type": "FeatureCollection",
          "features": []
        });

        // 2. Enable Native MapLibre Blue Dot tracking
        const targetMode = kIsWeb ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.trackingCompass;
        await controller!.updateMyLocationTrackingMode(targetMode);
      } catch (_) {}
    }
    notifyListeners();
  }


  // 1. ADD NATIVE VECTOR PIN (DEPRECATED: Using Flutter Overlay)
  Future<void> addNativeDestinationPin(LatLng location) async {
    targetDestination = location; // Update the internal coordinate tracker
    debugPrint("🗺️ CUSTOM PIN DROPPED at $location");
  }

  // 2. CLEAR NATIVE PIN (DEPRECATED)
  Future<void> clearNativeDestinationPin() async {
    // Intentionally empty. We use a Flutter UI overlay pin now.
  }

  // State flag for UI
  bool isRouteCalculated = false;
  bool isCalculatingRoute = false;

  bool get hasActiveRoute =>
      isRouteCalculated || engine.mapUIState.value == MapUIState.routeDrawn;

  // 🚀 HELPER: Strictly validates if the user's current location is a real physical GPS lock
  bool _isRealPhysicalGpsAvailable(BuildContext context) {
    final locService = Provider.of<GlobalLocationService>(context, listen: false);
    final pos = locService.currentPosition;
    
    if (pos == null || !locService.hasLocationPermission || pos.isMocked) return false;
    
    // Precision Check: True GPS precision is < 100m. IP fallbacks return > 100m or 0.0.
    if (pos.accuracy > 150.0 || pos.accuracy == 0.0) return false;

    // Fallback Coordinate Check (Delhi NCR & Nagpur dummy centers)
    final latStr = pos.latitude.toStringAsFixed(4);
    final lngStr = pos.longitude.toStringAsFixed(4);
    final isDummyCenter = (latStr == "28.6139" && lngStr == "77.2090") || 
                          (latStr == "21.1458" && lngStr == "79.0882") || 
                          (pos.latitude == 0.0 && pos.longitude == 0.0);

    return !isDummyCenter;
  }



  Future<void> _handlePermissionGrantAndRetry(BuildContext context) async {
    if (!context.mounted) return;
    
    final locService = Provider.of<GlobalLocationService>(context, listen: false);
    
    // 🌐 PLATFORM 1: FLUTTER WEB
    if (kIsWeb) {
      LocationPermission perm = await Geolocator.checkPermission();
      
      if (!context.mounted) return;
      
      // If permanently denied in browser, standard request will silently fail!
      if (perm == LocationPermission.deniedForever) {
        ToastService.showActionToast(
          context,
          message: "Location blocked in browser! Click the lock/info icon in your address bar to reset permissions.",
          actionLabel: "OK",
          onActionTap: () {},
        );
        return;
      }

      // 🚀 CRITICAL: Must actively request and AWAIT the browser dialog resolution!
      perm = await Geolocator.requestPermission();
      
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        debugPrint("✅ [Web Handshake] Permission granted via browser prompt!");
        await locService.initializeEcoLocation(isManualTrigger: true);
      } else {
        debugPrint("❌ [Web Handshake] User denied browser prompt.");
        return;
      }
    } 
    // 📱 PLATFORM 2: ANDROID / iOS NATIVE
    else {
      bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      
      // Step A: If GPS Hardware toggle is OFF, invoke native OS location settings/dialog
      if (!isServiceEnabled) {
        await Geolocator.openLocationSettings();
        // Allow 1 second for user to toggle OS switch and return to app
        await Future.delayed(const Duration(seconds: 1));
        isServiceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!isServiceEnabled) return; // Abort if user left GPS turned off
      }

      // Step B: If permission is denied, invoke native OS runtime prompt
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      } else if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return;
      }

      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        await locService.initializeEcoLocation(isManualTrigger: true);
      } else {
        return;
      }
    }

    // 🚀 STAGE 2: VERIFIED RETRY PIPELINE
    // Only after the handshake succeeds and high-accuracy GPS arrives do we draw the route!
    if (!context.mounted) return;
    await Future.delayed(const Duration(milliseconds: 300)); // Allow Blue Dot to mount in WebGL
    
    final pos = locService.currentPosition;
    final bool isPhysicalGps = pos != null && !pos.isMocked && locService.hasLocationPermission && pos.accuracy <= 150.0;
    
    if (isPhysicalGps) {
      debugPrint("🎯 [Handshake Success] High-accuracy GPS verified! Executing auto-retry for routing...");
      
      // 1. Ignite the native Blue Dot tracking (Purged)
      
      // 2. Automatically retry calculating and drawing the driving route
      if (!context.mounted) return;
      await calculateAndDrawNativeRoute(context, 'driving', isAutoTriggered: true);
    } else {
      debugPrint("⏳ [Handshake Waiting] Permission granted, but high-accuracy coordinate still settling...");
    }
  }

  Future<void> calculateAndDrawNativeRoute(
    BuildContext context,
    String mode, {
    bool isAutoTriggered = false,
  }) async {
    // 🛡️ THE ROUTING GATEKEEPER: Abort routing if real physical GPS is missing!
    if (!_isRealPhysicalGpsAvailable(context)) {
      debugPrint("🛑 [Routing Gatekeeper] Aborted route calculation! Invoking native permission handshake directly.");
      
      // 🚀 DIRECT NATIVE TRIGGER: Bypass custom UI and ask OS directly!
      if (!isAutoTriggered && context.mounted) {
        await _handlePermissionGrantAndRetry(context); 
      }
      return; // 🚀 INSTANT ABORT: Do not draw polyline!
    }

    isCalculatingRoute = true;
    notifyListeners();

    debugPrint("🚀 [ROUTE ENGINE] Triggered for mode: $mode");

    if (targetDestination == null) {
      debugPrint("❌ [ROUTE ENGINE] Failed: targetDestination is null.");
      isCalculatingRoute = false;
      notifyListeners();
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
        isCalculatingRoute = false;
        notifyListeners();
        return;
      }
    }

    // 🚀 FETCH EXACT ORIGIN ADDRESS LAZILY
    unawaited(locService.fetchCurrentAddressIfNeeded());

    // 🚨 CRITICAL: Clear old routes and UI state before fetching new ones
    await clearNativeRoute(preserveState: true);
    if (controller == null) {
      isCalculatingRoute = false;
      notifyListeners();
      return;
    }

    _currentRouteResult = null;
    notifyListeners();

    debugPrint(
      "📍 [ROUTE ENGINE] Origin: ${origin.latitude}, ${origin.longitude}",
    );
    debugPrint(
      "📍 [ROUTE ENGINE] Destination: ${targetDestination!.latitude}, ${targetDestination!.longitude}",
    );

    _routingSessionCounter++;
    final int currentSessionId = _routingSessionCounter;

    try {
      // Fetch route from Route Engine.
      debugPrint("⏳ [ROUTE ENGINE] Waiting for Route Engine API...");

      final safeContext = ToastService.navigatorKey.currentContext;
      if (safeContext != null && safeContext.mounted) {
        ToastService.showLoading(safeContext, "Finding route...");
      }

      RouteResult? routeResult;

      final waypointsList = intermediateStops.isNotEmpty
          ? intermediateStops
              .map((place) => LatLng(place.latitude, place.longitude))
              .toList()
          : null;

      if (mode == 'walking' || mode == 'walk') {
        routeResult = await _routingService
            .getWaterfallWalkRoute(origin, targetDestination!,
                waypoints: waypointsList)
            .timeout(const Duration(seconds: 10));
      } else {
        routeResult = await _routingService
            .getRoute(
              origin,
              targetDestination!,
              mode: 'driving',
              waypoints: waypointsList,
            )
            .timeout(const Duration(seconds: 10));
      }

      if (currentSessionId != _routingSessionCounter) {
        debugPrint(
            "⚠️ [ROUTE ENGINE] Discarding stale route response due to new user request.");
        return; // Completely abort processing this stale data
      }

      if (routeResult != null && routeResult.allRoutesCoordinates.isNotEmpty) {
        debugPrint(
          "✅ [ROUTE ENGINE] Ola API Success! Received ${routeResult.allRoutesCoordinates.first.length} points.",
        );

        _currentRouteResult = routeResult;
        _lastRouteData =
            routeResult; // 🚨 Ensure this is added so Bottom Sheet gets data

        // 🚀 Remove existing puck so it can be re-added on top of the new route
        if (_navPuckSymbol != null && controller != null) {
          await controller!.removeSymbol(_navPuckSymbol!);
          _navPuckSymbol = null;
        }

        await drawNativeRoute(routeResult.allRoutesCoordinates);
        debugPrint("✅ [ROUTE ENGINE] Native MapLibre Draw Success!");

        if (currentLocation != null) {
          final heading = engine.locService?.currentPosition?.heading ?? 0.0;
          updateLocationRenderingMode(currentLocation!, heading);
        }

        isRouteCalculated = true;
        engine.setUIState(MapUIState.routeDrawn);
        notifyListeners();

        // 🚨 IMMEDIATELY animate the bottom sheet down to its collapsed header view!
        if (sheetController.isAttached) {
          sheetController.animateTo(
            0.14, // Exact fractional height that naturally reveals strictly the top Dropped Pin header!
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
          );
        }
      } else {
        debugPrint(
          "⚠️ [ROUTE ENGINE] Ola API returned empty coordinates or null.",
        );
      }
    } catch (e) {
      debugPrint("💥 [ROUTE ENGINE] CRASH: $e");
      _setLoading(false);
      final context = ToastService.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Route unavailable for this distance/mode."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    } finally {
      isCalculatingRoute = false;
      ToastService.dismiss();
      notifyListeners();
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
    final context = ToastService.navigatorKey.currentContext;
    if (context != null && !_isRealPhysicalGpsAvailable(context)) {
      debugPrint("🛑 [Routing Gatekeeper] Aborted 3D navigation! Invoking native permission handshake directly.");
      await _handlePermissionGrantAndRetry(context);
      return;
    }

    if (controller == null) return;

    isActiveNavigation = true;
    isAutoTracking = true;

    if (_currentRouteResult != null && targetDestination != null) {
      await engine.startActiveNavigation(
          _currentRouteResult!, targetDestination!, currentNavMode);
    } else {
      engine.setUIState(MapUIState.navigating);
    }

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
      updateLocationRenderingMode(targetLoc, pos?.heading ?? 0.0);

      try {
        await controller!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: targetLoc,
              zoom: _getClampedZoom(18.0), // Deep zoom for navigation
              tilt: 50.0, // 3D Pitch angle
              bearing: pos?.heading ?? 0.0,
            ),
          ),
          duration: const Duration(milliseconds: 1200),
        );
      } catch (e) {
        debugPrint("animateCamera Error: $e");
      }
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
      try {
        await controller!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: targetLoc,
              zoom: _getClampedZoom(18.0),
              tilt: 50.0,
              bearing: pos?.heading ?? 0.0,
            ),
          ),
          duration: const Duration(milliseconds: 800),
        );
      } catch (e) {
        debugPrint("animateCamera Error: $e");
      }
      try {
        await setTrackingMode(MyLocationTrackingMode.trackingCompass);
      } catch (_) {}
    }
  }

  List<String> activeFocusLayerIds = [];

  Future<void> _toggleFocusModeLayers(bool isFocusMode) async {
    // 🛑 FATAL CRASH GUARD: Completely disabled. 
    // Overwriting native MapLibre filters with 'null' destroys the original style rules, 
    // causing 'Missing required image id' WebGL fatal crashes and screen freezes.
    return;
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
    final context = ToastService.navigatorKey.currentContext;
    if (context != null && !_isRealPhysicalGpsAvailable(context)) {
      debugPrint("🛑 [Routing Gatekeeper] Aborted route selection! Invoking native permission handshake directly.");
      await _handlePermissionGrantAndRetry(context);
      return false;
    }

    // 1. Guard clause: Do nothing if actively navigating
    if (isActiveNavigation ||
        engine.mapUIState.value == MapUIState.navigating) {
      return false;
    }

    if (controller == null ||
        _drawnRoutesCount <= 1 ||
        _currentRouteResult == null) {
      return false;
    }

    // Alt layers start from index 1 (index 0 is primary)
    List<String> altLayerIds = [];
    for (int i = 1; i < _drawnRoutesCount; i++) {
      altLayerIds.add('route-layer-$i');
      altLayerIds.add(
          'alt-walk-layer-$i'); // CRITICAL: Makes walking routes clickable!
    }

    try {
      // 2. Safely query features
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
    } catch (e) {
      // 3. Catch missing layer exceptions silently
      debugPrint("Ignored Map Click: Layer does not exist yet.");
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

    Future<void> safeAddLineLayer(
        String sourceId, String layerId, LineLayerProperties props) async {
      try {
        await controller!.addLineLayer(sourceId, layerId, props);
      } catch (e) {
        debugPrint("🗺️ LINE DRAW ERROR for $layerId: $e");
      }
    }

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
          try {
            await controller!.addGeoJsonSource('alt-source-$i', geoJson);
          } catch (_) {}
          await safeAddLineLayer(
            'alt-source-$i',
            'alt-walk-layer-$i',
            const LineLayerProperties(
              lineColor: "#8E8E93",
              lineWidth: 4.5,
              lineCap: "round",
              lineJoin: "round",
              lineDasharray: [0.001, 2.0],
            ),
          );
        } else {
          try {
            await controller!.addGeoJsonSource('route-source-$i', geoJson);
          } catch (_) {}
          await safeAddLineLayer(
            'route-source-$i',
            'route-layer-$i',
            const LineLayerProperties(
              lineColor: "#8E8E93",
              lineWidth: 4.0,
              lineCap: "round",
              lineJoin: "round",
              lineOpacity: 0.6,
            ),
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

      final congestionData = _currentRouteResult?.congestion;
      final geoJson = await compute(_buildPrimaryGeoJson, {
        'coords': primaryCoords,
        'congestion': congestionData,
      });

      try {
        final bool isWalking = currentNavMode == 'walking';

        if (isWalking) {
          try {
            await controller!.addGeoJsonSource('primary-source', geoJson);
          } catch (_) {}
          await safeAddLineLayer(
            'primary-source',
            'primary-walk-layer',
            const LineLayerProperties(
              lineColor: "#0A84FF", // Neon Blue Highlight
              lineWidth: 6.5, // Thicker to cover grey lines
              lineCap: "round",
              lineJoin: "round",
              lineDasharray: [0.001, 2.0], // Safe values for circular dots
            ),
          );
        } else {
          try {
            await controller!.addGeoJsonSource('route-source-0', geoJson);
          } catch (_) {}

          // 1. BOTTOM: Casing (Deep shadow to give height/3D effect)
          await safeAddLineLayer(
            "route-source-0",
            "primary-casing",
            const LineLayerProperties(
              lineColor: "#001D4A", // Very dark navy blue
              lineWidth: 10.0,
              lineCap: "round",
              lineJoin: "round",
            ),
          );

          // 2. MIDDLE: Core (Solid Neon Blue or Traffic Colors)
          await safeAddLineLayer(
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
          );

          // 3. TOP: Shine (Ultra-thin 1px Sky Blue reflection perfectly blending)
          await safeAddLineLayer(
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
          );
        }
      } catch (e) {
        debugPrint("🗺️ PRIMARY ROUTE DRAW ERROR: $e");
      }
    }

    // 5. Adjust Camera to fit the PRIMARY route
    if (allRoutes.isNotEmpty) {
      try {
        await controller!.animateCamera(
          CameraUpdate.newLatLngBounds(
            _calculateBounds(allRoutes.first),
            bottom: 380,
            left: 50,
            right: 50,
            top: 100,
          ),
          duration: const Duration(milliseconds: 1000),
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
            CameraPosition(target: LatLng(centerLat, centerLng), zoom: _getClampedZoom(12.0))));
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
          try {
            await controller!.removeSource('intermediate-pins-source');
          } catch (_) {}

          try {
            await controller!.addGeoJsonSource("connectors-source", {
              "type": "Feature",
              "geometry": {
                "type": "MultiLineString",
                "coordinates": connectorLines,
              },
            });
          } catch (_) {}

          await safeAddLineLayer(
            "connectors-source",
            "connectors-layer",
            const LineLayerProperties(
              lineColor: "#0A84FF", // Match the primary route color
              lineWidth: 3.5,
              lineCap: "round",
              lineJoin: "round",
              lineDasharray: [0.001, 2.0], // Premium circular dots
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
      final String imageId = 'time-tag-image-$i';

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
        try {
          if (imageId.trim().isNotEmpty) {
            await controller!.addImage(imageId, imageBytes);
          }
        } catch (_) {}

        // 2. Add Point Source
        try {
          await controller!.addGeoJsonSource(sourceId, {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [midpoint.longitude, midpoint.latitude],
            },
          });
        } catch (_) {}

        // 3. Add Symbol Layer (ICON ONLY, NO TEXT)
        try {
          await controller!.addSymbolLayer(
            sourceId,
            layerId,
            SymbolLayerProperties(
              iconImage: imageId.isNotEmpty
                  ? imageId
                  : 'custom-marker', // Fallback added
              iconSize: 0.32 * mapItemScale,
              iconAnchor: "center", // Centered perfectly on the route line
              symbolSortKey: i,
              symbolPlacement: "point",
              iconAllowOverlap: isPrimary ? true : false,
              iconIgnorePlacement: isPrimary ? true : false,
            ),
          );
        } catch (_) {}
      } catch (e) {
        debugPrint("🗺️ ETA TAG DRAW ERROR for index $i: $e");
      }
    }

    // KILL GHOST PINS TO PREVENT DOUBLE PINS
    if (_droppedPinSymbol != null && controller != null) {
      await controller!.removeSymbol(_droppedPinSymbol!);
      _droppedPinSymbol = null;
    }
    await engine.layers?.removeSearchPin();

    // 8. ROAD SNAP & BULLETPROOF Z-INDEX FOR PIN
    if (targetDestination != null && controller != null && !isDropPinMode) {
      try {
        await controller!.removeLayer('ultimate-pin-layer');
      } catch (_) {}
      try {
        await controller!.removeSource('ultimate-pin-source');
      } catch (_) {}

      try {
        await controller!.addGeoJsonSource('ultimate-pin-source', {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [
              targetDestination!.longitude,
              targetDestination!.latitude
            ],
          },
        });
      } catch (_) {}

      try {
        await controller!.addSymbolLayer(
          'ultimate-pin-source',
          'ultimate-pin-layer',
          SymbolLayerProperties(
            iconImage: 'custom_pin',
            iconSize: 1.0 * mapItemScale,
            iconAnchor: 'bottom',
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
          ),
        );
      } catch (_) {}
    }

    // 9. INTERMEDIATE PINS
    if (intermediateStops.isNotEmpty && controller != null) {
      try {
        await controller!.removeLayer('intermediate-pins-layer');
      } catch (_) {}
      try {
        await controller!.removeSource('intermediate-pins-source');
      } catch (_) {}

      final features = intermediateStops
          .map((stop) => {
                "type": "Feature",
                "geometry": {
                  "type": "Point",
                  "coordinates": [stop.longitude, stop.latitude]
                }
              })
          .toList();

      try {
        await controller!.addGeoJsonSource('intermediate-pins-source', {
          "type": "FeatureCollection",
          "features": features,
        });
      } catch (_) {}

      try {
        await controller!.addSymbolLayer(
          'intermediate-pins-source',
          'intermediate-pins-layer',
          SymbolLayerProperties(
            iconImage: 'intermediate_pin',
            iconSize: 1.0 * mapItemScale,
            iconAnchor: 'bottom',
            iconAllowOverlap: true,
            iconIgnorePlacement: true,
          ),
        );
      } catch (e) {
        debugPrint("🗺️ INTERMEDIATE PIN DROP ERROR: $e");
      }
    }

    if (targetDestination != null) {
      await clearNativeDestinationPin();
    }

    notifyListeners();
  }

  Future<void> clearNativeRoute({bool preserveState = false}) async {
    // 🚀 1. INSTANT STATE LOCK: Kill streams before touching WebGL memory
    if (!preserveState) {
      engine.setUIState(MapUIState.idle);
      isActiveNavigation = false;
      isRouteCalculated = false;
      setAutoTracking(false);
      setUserPanning(false);


      try { await controller?.removeLayer("nav_puck_layer"); } catch (_) {}
      try { await controller?.removeSource("nav_puck_source"); } catch (_) {}
    }

    if (_drawnRoutesCount == 0) return;

    if (controller != null && _drawnRoutesCount > 0) {
      // 🚀 2. BULK LAYER CLEANUP
      final layersToRemove = [
        'primary-casing', 'primary-core', 'primary-shine', 'primary-walk-layer',
        'connectors-layer', 'intermediate-pins-layer'
      ];
      for (var layer in layersToRemove) {
        try { await controller!.removeLayer(layer); } catch (_) {}
      }
      for (int i = 0; i < 5; i++) {
        try { await controller!.removeLayer('route-layer-$i'); } catch (_) {}
        try { await controller!.removeLayer('alt-walk-layer-$i'); } catch (_) {}
        try { await controller!.removeLayer('time-tag-layer-$i'); } catch (_) {}
      }

      // 🚀 3. BULK SOURCE CLEANUP
      final sourcesToRemove = ['primary-source', 'connectors-source', 'intermediate-pins-source'];
      for (var source in sourcesToRemove) {
        try { await controller!.removeSource(source); } catch (_) {}
      }
      for (int i = 0; i < 5; i++) {
        try { await controller!.removeSource('route-source-$i'); } catch (_) {}
        try { await controller!.removeSource('alt-source-$i'); } catch (_) {}
        try { await controller!.removeSource('time-tag-source-$i'); } catch (_) {}
      }

      _drawnRoutesCount = 0;

      if (!preserveState) {
        _currentRouteResult = null;
        _lastRouteData = null;

        if (controller != null && currentLocation != null) {
          await controller!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(currentLocation!.latitude, currentLocation!.longitude),
                zoom: _getClampedZoom(15.0),
                tilt: 0.0,
                bearing: 0.0,
              ),
            ),
            duration: const Duration(milliseconds: 1200),
          );
        }
      }
      notifyListeners();
    }
  }

  Future<void> cancelAndClearRoute({bool resetCamera = true}) async {
    debugPrint("🛑 [Navigation] Executing End Route Teardown...");

    // 🚀 2. FREE THE CAMERA
    try {
      if (controller != null) {
        await controller!.animateCamera(CameraUpdate.bearingTo(0.0), duration: const Duration(milliseconds: 600));
        await controller!.animateCamera(CameraUpdate.tiltTo(0.0), duration: const Duration(milliseconds: 600));
      }
    } catch (_) {}

    // 🚀 3. INSTANT STATE LOCK TO KILL BACKGROUND LOGIC
    engine.setUIState(MapUIState.idle);
    isRouteCalculated = false;
    isActiveNavigation = false;
    setAutoTracking(false);
    setUserPanning(false);

    try { engine.navigation.stopNavigation(); } catch (_) {}

    _liveLocationSub?.cancel();
    _liveLocationSub = null;
    try { intermediateStops.clear(); } catch (_) { intermediateStops = []; }

    // 🚀 4. SECURE LAYER & SOURCE CLEANUP
    if (controller != null) {
      final layersToRemove = [
        'primary-casing', 'primary-core', 'primary-shine', 'primary-walk-layer',
        'connectors-layer', 'intermediate-pins-layer', 'ultimate-pin-layer',
        'selected-destination-layer'
      ];
      for (var layer in layersToRemove) {
        try { await controller!.removeLayer(layer); } catch (_) {}
      }
      for (int i = 0; i < 5; i++) {
        try { await controller!.removeLayer('route-layer-$i'); } catch (_) {}
        try { await controller!.removeLayer('alt-walk-layer-$i'); } catch (_) {}
        try { await controller!.removeLayer('time-tag-layer-$i'); } catch (_) {}
      }

      final sourcesToRemove = [
        'primary-source', 'connectors-source', 'intermediate-pins-source',
        'ultimate-pin-source', 'selected-destination-source'
      ];
      for (var source in sourcesToRemove) {
        try { await controller!.removeSource(source); } catch (_) {}
      }
      for (int i = 0; i < 5; i++) {
        try { await controller!.removeSource('route-source-$i'); } catch (_) {}
        try { await controller!.removeSource('alt-source-$i'); } catch (_) {}
        try { await controller!.removeSource('time-tag-source-$i'); } catch (_) {}
      }

      if (_droppedPinSymbol != null) {
        await controller!.removeSymbol(_droppedPinSymbol!);
        _droppedPinSymbol = null;
      }
      await engine.layers?.removeSearchPin();
    }

    // 🚀 5. RESET ALL VARIABLES
    _drawnRoutesCount = 0;
    _currentRouteResult = null;
    _lastRouteData = null;
    targetDestination = null;
    targetLocation = null;
    isCinematicSearch = false;
    _activeDestination = null;
    _isDestinationSelected = false;
    currentNavMode = 'driving';

    // 🚀 6. CINEMATIC CAMERA RESET
    if (resetCamera && currentLocation != null && controller != null) {
      await controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(currentLocation!.latitude, currentLocation!.longitude),
            zoom: _getClampedZoom(15.0),
            tilt: 0.0,
            bearing: 0.0,
          ),
        ),
        duration: const Duration(milliseconds: 1200),
      );
    }

    // Tell the custom layer to seamlessly switch back to the Blue Dot
    if (currentLocation != null) {
      updateLocationRenderingMode(currentLocation!, 0.0); 
    }
    // 🚀 7. NOTIFY UI TO RESTORE DEFAULT STATE
    notifyListeners();
    debugPrint("✅ [Navigation] End Route Teardown Complete. Camera is FREE.");
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

  PlaceModel? _activeDestination;
  PlaceModel? get activeDestination => _activeDestination;

  LatLng? _currentMapCenter;
  LatLng? get currentMapCenter => _currentMapCenter;

  String? _currentCityName;
  String? get currentCityName => _currentCityName;
  double _currentZoomLevel = 16.0;
  double get currentZoomLevel => _currentZoomLevel;

  MapThemeType _currentTheme = MapThemeType.dark;
  MapThemeType get currentTheme => _currentTheme;
  Future<void> setTheme(MapThemeType theme) async {
    // CRITICAL GUARD: If the theme is already active, DO NOT notify or rebuild!
    if (_currentTheme == theme) return;

    _currentTheme = theme;
    notifyListeners(); // Call strictly once!

    await _autoPushMapStyle();

    if (controller != null && _lastRouteData != null) {
      // Explicitly clear layers to prevent memory leaks from overlaying
      RouteVisualizer.clearRoute(controller).then((_) {
        drawNativeRoute(_lastRouteData!.allRoutesCoordinates);
      });
    }
  }

  Future<void> _autoPushMapStyle() async {
    if (controller == null) return;
    try {
      final String newStyle = await MapStyleHelper.getOlaStyle(
        false,
        themeType: _currentTheme,
        showLabels: _showLabels,
        showPOIs: _showPOIs,
      );

      // CRITICAL FOR WEB: Ensure the engine is ready to accept a new style string without crashing!
      await controller!.setStyle(newStyle);

      // Native tracking purged
    } catch (e) {
      debugPrint("❌ Auto style sync failed: $e");
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
      }, onError: (error) {
        debugPrint(
            "📍 [DEBUG] Map Provider GPS stream lost or glitched: $error");
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
  StreamSubscription<Position>? _locServiceSub;

  MapProvider() {
    engine.state.addListener(() {
      if (engine.isFullyBooted &&
          _locServiceSub == null &&
          engine.locService != null) {
        DateTime? lastMapUpdate;
        _locServiceSub = engine.locService!.engineLocationStream.listen((pos) {
          final now = DateTime.now();
          // 🚀 ONLY UPDATE ENGINE AT MAX 30 FPS (Every ~33ms)
          if (lastMapUpdate == null || now.difference(lastMapUpdate!).inMilliseconds > 33) {
            lastMapUpdate = now;
            // 🚀 CRITICAL: Always update the custom layer so the Blue Dot moves!
            updateLocationRenderingMode(LatLng(pos.latitude, pos.longitude), pos.heading);
          }
        });
      }
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
        updateLocationRenderingMode(currentLocation!,
            engine.locService?.currentPosition?.heading ?? 0.0);
      } else if (currentLocation != null) {
        updateLocationRenderingMode(currentLocation!, 0.0);
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
  // Layer visibility state
  bool _showLabels = true;
  bool _showPOIs = false;

  bool get showLabels => _showLabels;
  bool get showPOIs => _showPOIs;

  Future<void> toggleLabels(bool value) async {
    if (_showLabels == value) return;
    _showLabels = value;
    notifyListeners();
    await _autoPushMapStyle();
  }

  Future<void> togglePOIs(bool value) async {
    if (_showPOIs == value) return;
    _showPOIs = value;
    notifyListeners();
    await _autoPushMapStyle();
  }

  MapUIState get currentUIState => engine.mapUIState.value;

  void setActiveDestination(PlaceModel place) {
    _activeDestination = place;
    setDestinationSelected(true);
    notifyListeners();
  }

  void clearActiveDestination() {
    _activeDestination = null;
    notifyListeners();
  }

  Future<void> handleMapLongPress(LatLng latLng) async {
    // Delegate entirely to handleMapTap to ensure strict pin-drop flow without auto-routing.
    await handleMapTap(const Point(0, 0), latLng);
  }

  Future<void> handleMapTap(Point<double> point, LatLng latLng) async {
    if (!_isMapReady) return;

    // 🚀 TASK 1: FORCIBLY SEVER AUTO-TRACKING BEFORE CAMERA FLIGHT
    // This MUST happen first to prevent the GPS stream from yanking the camera back.
    setAutoTracking(false);

    // Native tracking purged

    await cancelAndClearRoute(resetCamera: false);

    AppHaptics.heavyImpact();

    // Set placeholder immediately to avoid blocking UI
    final temporaryPlace = PlaceModel(
      placeId: 'temp_${latLng.latitude}_${latLng.longitude}',
      name: 'Dropped Pin',
      address:
          '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}',
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      categories: const [],
    );

    // 🚀 FIX: Use the SAME unified setter as the Search flow to guarantee
    // consistent notifyListeners() propagation and FAB state morphing.
    setActiveDestination(temporaryPlace);

    // Hydrate global destination coordinates for routing and MapControlsPill
    targetLocation = latLng;
    targetDestination = latLng;

    // Transition UI state machine to "placeSelected" (drives QuickActionButtons + MapControlsPill morphing)
    engine.setUIState(MapUIState.placeSelected);

    // Single consolidated notification for all state changes above
    notifyListeners();

    // 🚀 TASK 2: Execute a cinematic flight strictly to the dropped pin
    Future.microtask(() async {
      if (engine.mapController != null) {
        await engine.mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: latLng, // strictly center on the PIN, not the user!
              zoom: _getClampedZoom(16.0), // Clean, immersive street-level zoom
              tilt: 0.0, // Clean flat cartographic angle
              bearing: 0.0, // North-up alignment
            ),
          ),
          duration:
              const Duration(milliseconds: 800), // Silky-smooth 60FPS glide
        );
      }
    });

    // Clear existing pin if any
    if (_droppedPinSymbol != null && controller != null) {
      await controller!.removeSymbol(_droppedPinSymbol!);
      _droppedPinSymbol = null;
    }

    if (controller != null && !isDropPinMode) {
      // 1. Drop the pin tilted slightly right
      _droppedPinSymbol = await controller!.addSymbol(
        SymbolOptions(
          geometry: latLng,
          iconImage: 'custom_pin',
          iconSize: 1.0 * mapItemScale,
          iconAnchor: 'bottom',
          iconRotate: 15.0, // Head tilted right
          zIndex: 998,
        ),
      );

      // 2. Sway Left
      Future.delayed(const Duration(milliseconds: 150), () async {
        if (_droppedPinSymbol != null && controller != null) {
          await controller!.updateSymbol(
              _droppedPinSymbol!, const SymbolOptions(iconRotate: -10.0));
        }
      });

      // 3. Sway slightly Right
      Future.delayed(const Duration(milliseconds: 300), () async {
        if (_droppedPinSymbol != null && controller != null) {
          await controller!.updateSymbol(
              _droppedPinSymbol!, const SymbolOptions(iconRotate: 5.0));
        }
      });

      // 4. Settle firmly in the center
      Future.delayed(const Duration(milliseconds: 450), () async {
        if (_droppedPinSymbol != null && controller != null) {
          await controller!.updateSymbol(
              _droppedPinSymbol!, const SymbolOptions(iconRotate: 0.0));
        }
      });
    }

    // 🚀 FIX: Robust Debounce to prevent API hemorrhage
    _geocodeDebounceTimer?.cancel();
    _geocodeDebounceTimer = Timer(const Duration(milliseconds: 1500), () async {
      try {
        final PlaceModel place = await PlaceEnrichmentService()
            .reverseGeocode(
              latLng.latitude,
              latLng.longitude,
            )
            .timeout(const Duration(seconds: 8));
        setActiveDestination(place);
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

        final context = ToastService.navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ToastService.showError(
              context, "Poor internet connection. Pin dropped offline.");
        }

        // Fallback to coordinates on failure
        final fallback = PlaceModel(
          placeId: temporaryPlace.placeId,
          name: "Dropped Pin",
          address:
              "${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}",
          latitude: latLng.latitude,
          longitude: latLng.longitude,
          categories: const [],
        );
        setActiveDestination(fallback);
      }
    });
  }

  Future<void> clearSearchSession(BuildContext context) async {
    targetDestination = null;
    intermediateStops.clear();
    setDestinationSelected(false);

    if (controller != null) {
      // 1. Clear the visual polyline layers completely
      await RouteVisualizer.clearRoute(controller);

      // 2. Remove the manual dropped pin or search symbol layer
      if (_droppedPinSymbol != null) {
        await controller!.removeSymbol(_droppedPinSymbol!);
        _droppedPinSymbol = null;
      }
      await engine.layers?.removeSearchPin();

      await clearNativeDestinationPin();
    }

    clearActiveDestination();

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
    if (activeDestination != null) {
      destinationCoords = LatLng(
        activeDestination!.latitude,
        activeDestination!.longitude,
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
      final waypointsList = intermediateStops.isNotEmpty
          ? intermediateStops
              .map((place) => LatLng(place.latitude, place.longitude))
              .toList()
          : null;

      final routeData = await _routingService.getRoute(
        origin,
        destinationCoords,
        waypoints: waypointsList,
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Route unavailable for this distance/mode."),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
              bottom: 380,
            ),
            duration: const Duration(milliseconds: 1000),
          );
        } catch (e) {
          debugPrint(
              "⚠️ Bounds fit failed (screen too small), falling back to center focus: $e");
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          await controller?.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: LatLng(centerLat, centerLng), zoom: _getClampedZoom(12.0))));
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

  // =========================================================================
  // 🚀 SPATIAL SEARCH ENGINE (Zero-API Local RAM Cache)
  // =========================================================================
  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  double _calculateHaversine(
      double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371; // Earth's radius in kilometers
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Future<List<Map<String, dynamic>>> getNearestStops(
      double userLat, double userLng, String type,
      {int limit = 15}) async {
    final int mode = (type.toLowerCase() == 'metro' ||
            type.toLowerCase() == 'metro stations')
        ? 0
        : 1;
    final List<Map<String, dynamic>> allStops =
        await DatabaseHelper.instance.getStopsByMode(mode);

    List<Map<String, dynamic>> stopsWithDistance = [];
    for (var stop in allStops) {
      double stopLat =
          double.tryParse((stop['lat'] ?? stop['LAT'] ?? '0').toString()) ??
              0.0;
      double stopLng = double.tryParse(
              (stop['lon'] ?? stop['LON'] ?? stop['lng'] ?? stop['LNG'] ?? '0')
                  .toString()) ??
          0.0;

      // Skip invalid coordinates
      if (stopLat == 0.0 && stopLng == 0.0) continue;

      double distance = _calculateHaversine(userLat, userLng, stopLat, stopLng);
      stopsWithDistance.add({
        ...stop,
        'calculated_distance': distance,
      });
    }

    stopsWithDistance.sort((a, b) => (a['calculated_distance'] as double)
        .compareTo(b['calculated_distance'] as double));
    return stopsWithDistance.take(limit).toList();
  }

  Future<void> showNearbyStopsOnMap(String type) async {
    final userLoc = engine.locService?.currentPosition;
    if (userLoc == null) {
      debugPrint("❌ GPS Unavailable for nearby stops");
      return;
    }

    _setLoading(true);
    try {
      // 🚀 1. Instant RAM Fetch (Zero API)
      final nearestStops =
          await getNearestStops(userLoc.latitude, userLoc.longitude, type);

      if (nearestStops.isEmpty) {
        debugPrint("⚠️ No stops found nearby for $type.");
        return;
      }

      // 🚀 2. Build GeoJSON
      final Map<String, dynamic> geoJson = {
        "type": "FeatureCollection",
        "features": nearestStops.map((stop) {
          double stopLat =
              double.tryParse((stop['lat'] ?? stop['LAT'] ?? '0').toString()) ??
                  0.0;
          double stopLng = double.tryParse((stop['lon'] ??
                      stop['LON'] ??
                      stop['lng'] ??
                      stop['LNG'] ??
                      '0')
                  .toString()) ??
              0.0;
          return {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [stopLng, stopLat] // MapLibre needs [Lng, Lat]
            },
            "properties": {
              "id": stop['stop_id'] ?? stop['STOP_ID'],
              "name": stop['stop_name'] ?? stop['STOP_NAME'] ?? stop['name'],
              "icon": (type.toLowerCase() == 'metro' ||
                      type.toLowerCase() == 'metro stations')
                  ? 'metro_icon'
                  : 'bus_icon'
            }
          };
        }).toList()
      };

      // 🚀 3. Render on Map
      await controller?.removeLayer('nearby-stops-layer');
      await controller?.removeSource('nearby-stops-source');

      await controller?.addGeoJsonSource('nearby-stops-source', geoJson);
      await controller?.addSymbolLayer(
        'nearby-stops-source',
        'nearby-stops-layer',
        SymbolLayerProperties(
          iconImage: const ['get', 'icon'],
          iconSize: 1.2 * mapItemScale,
          iconAllowOverlap: true,
          textField: const ['get', 'name'],
          textSize: 12.0 * mapItemScale,
          textOffset: const [0, 1.5],
          textColor: '#FFFFFF',
          textHaloColor: '#000000',
          textHaloWidth: 1.0,
        ),
      );

      // 4. Zoom bounds to fit nearby stops
      double minLat = 90.0, maxLat = -90.0;
      double minLng = 180.0, maxLng = -180.0;
      for (var stop in nearestStops) {
        double stopLat =
            double.tryParse((stop['lat'] ?? stop['LAT'] ?? '0').toString()) ??
                0.0;
        double stopLng = double.tryParse((stop['lon'] ??
                    stop['LON'] ??
                    stop['lng'] ??
                    stop['LNG'] ??
                    '0')
                .toString()) ??
            0.0;
        minLat = math.min(minLat, stopLat);
        maxLat = math.max(maxLat, stopLat);
        minLng = math.min(minLng, stopLng);
        maxLng = math.max(maxLng, stopLng);
      }

      await controller?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.005, minLng - 0.005),
            northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
          ),
          left: 50,
          top: 100,
          right: 50,
          bottom: 380,
        ),
        duration: const Duration(milliseconds: 1000),
      );
    } catch (e) {
      debugPrint("❌ Error showing nearby stops: $e");
    } finally {
      _setLoading(false);
      notifyListeners();
    }
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
        }, onError: (error) {
          debugPrint(
              "📍 [DEBUG] Map Provider GPS stream lost or glitched: $error");
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
              bottom: 380,
            ),
            duration: const Duration(milliseconds: 1000),
          );
        } catch (e) {
          debugPrint(
              "⚠️ Bounds fit failed (screen too small), falling back to center focus: $e");
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          await controller?.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: LatLng(centerLat, centerLng), zoom: _getClampedZoom(12.0))));
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
            zoom: _getClampedZoom(17.0),
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
        await flyToPlace(target.latitude, target.longitude);
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

    // Native tracking purged

    final target = LatLng(lat, lng);
    targetDestination = target;

    setAutoTracking(
        false); // 🚨 CRITICAL FIX: Stops the background GPS from snapping the camera back!
    notifyListeners();

    engine.setUIState(MapUIState.placeSelected);
    isFlying = true;
    notifyListeners(); // 🧭 Triggers Consumer → AnimatedMapPin overlay appears

    try {
      // 🚀 TASK 2: Execute a cinematic flight strictly to the destination pin
      Future.microtask(() async {
        if (controller != null) {
          await controller!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(
                    lat, lng), // strictly center on the PIN, not the user!
                zoom: _getClampedZoom(16.0), // Clean, immersive street-level zoom
                tilt: 0.0, // Clean flat cartographic angle
                bearing: 0.0, // North-up alignment
              ),
            ),
            duration:
                const Duration(milliseconds: 800), // Silky-smooth 60FPS glide
          );
        }
      });

      // Clear existing pin if any
      if (_droppedPinSymbol != null && controller != null) {
        await controller!.removeSymbol(_droppedPinSymbol!);
        _droppedPinSymbol = null;
      }

      if (controller != null && !isDropPinMode) {
        // 1. Drop the pin tilted slightly right
        _droppedPinSymbol = await controller!.addSymbol(
          SymbolOptions(
            geometry: target,
            iconImage: 'custom_pin',
            iconSize: 1.0 * mapItemScale,
            iconAnchor: 'bottom',
            iconRotate: 15.0, // Head tilted right
            zIndex: 998,
          ),
        );

        // 2. Sway Left
        Future.delayed(const Duration(milliseconds: 150), () async {
          if (_droppedPinSymbol != null && controller != null) {
            await controller!.updateSymbol(
                _droppedPinSymbol!, const SymbolOptions(iconRotate: -10.0));
          }
        });

        // 3. Sway slightly Right
        Future.delayed(const Duration(milliseconds: 300), () async {
          if (_droppedPinSymbol != null && controller != null) {
            await controller!.updateSymbol(
                _droppedPinSymbol!, const SymbolOptions(iconRotate: 5.0));
          }
        });

        // 4. Settle firmly in the center
        Future.delayed(const Duration(milliseconds: 450), () async {
          if (_droppedPinSymbol != null && controller != null) {
            await controller!.updateSymbol(
                _droppedPinSymbol!, const SymbolOptions(iconRotate: 0.0));
          }
        });
      }

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
      setAutoTracking(false);
      await controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: _getClampedZoom(zoom), tilt: tilt, bearing: 0),
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
              bottom: 380, // Prevent route from hiding behind the bottom sheet
            ),
            duration: const Duration(milliseconds: 1000),
          );
        } catch (e) {
          debugPrint(
              "⚠️ Bounds fit failed (screen too small), falling back to center focus: $e");
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          await controller!.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: LatLng(centerLat, centerLng), zoom: _getClampedZoom(12.0))));
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
          zoom: _getClampedZoom(18.0),
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

Map<String, dynamic> _buildPrimaryGeoJson(Map<String, dynamic> data) {
  final coords = data['coords'] as List<LatLng>;
  final congestionData = data['congestion'] as List<String>?;

  List<Map<String, dynamic>> features = [];

  if (congestionData != null && congestionData.isNotEmpty) {
    for (int i = 0; i < coords.length - 1; i++) {
      int congestionIndex = (i / coords.length * congestionData.length).floor();
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
            [coords[i].longitude, coords[i].latitude],
            [coords[i + 1].longitude, coords[i + 1].latitude]
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
        "coordinates": coords.map((p) => [p.longitude, p.latitude]).toList()
      },
    });
  }

  return {
    "type": "FeatureCollection",
    "features": features,
  };
}
