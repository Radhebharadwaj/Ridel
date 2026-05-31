import 'dart:math' as math;
import 'dart:math' show Point;

import 'package:flutter/material.dart';
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
import 'package:ridel/features/map/services/route_engine_service.dart';

class MapProvider extends ChangeNotifier {
  final MapEngine engine = MapEngine();
  final RouteEngineService _routingService = RouteEngineService();


  MapLibreMapController? get controller => engine.mapController;
  bool get _isMapReady => controller != null;

  Circle? _currentMarker;
  Circle? _originMarker;
  Circle? _currentDroppedPin;

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
    if (isNavigatingToStation &&
        targetStationLocation != null &&
        _lastRouteData != null) {
      if (controller != null) {
        RouteVisualizer.drawRoute(controller, _lastRouteData!.coordinates, _currentTheme);
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
      await autoDrawRouteTo(targetDestination!, context);
    }
  }

  void setDestinationSelected(bool value) {
    if (_isDestinationSelected != value) {
      _isDestinationSelected = value;

      // 🧭 State Machine: place selected → placeSelected, deselected → idle
      if (value && engine.mapUIState.value == MapUIState.idle) {
        engine.setUIState(MapUIState.placeSelected);
      } else if (!value && engine.mapUIState.value == MapUIState.placeSelected) {
        engine.setUIState(MapUIState.idle);
      }

      notifyListeners();
    }
  }

  void startTurnByTurnNavigation() {
    if (_lastRouteData != null) {
      engine.navigation.startNavigation(_lastRouteData!);
      AppHaptics.success();
    }
  }

  // 🚨 MULTIPLE NEARBY PINS TRACKER
  final List<Circle> _nearbyCircles = [];
  final List<Symbol> _nearbyLabels = [];

  MapProvider() {
    engine.state.addListener(() {
      notifyListeners();
    });

    // 🧭 Forward UI state machine changes to ChangeNotifier listeners
    engine.mapUIState.addListener(() {
      notifyListeners();
    });
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

    engine.layers?.showSearchPin(latLng);

    await drawDroppedPin(latLng);

    AppHaptics.lightImpact();

    try {
      final PlaceModel place = await PlaceEnrichmentService().reverseGeocode(
          latLng.latitude, latLng.longitude);
      setTappedPlace(place);
    } catch (e) {
      debugPrint("Tap Handler Error: $e");
    }
  }

  Future<void> drawDroppedPin(LatLng latLng) async {
    if (_currentDroppedPin != null) {
      await controller?.removeCircle(_currentDroppedPin!);
    }
    _currentDroppedPin = await controller?.addCircle(
      CircleOptions(
        geometry: latLng,
        circleColor: '#FF3B30', // Premium Apple Red
        circleRadius: 8.0,
        circleStrokeWidth: 3.0,
        circleStrokeColor: '#FFFFFF', // White border for contrast
      ),
    );
  }

  Future<void> clearSearchSession(BuildContext context) async {
    targetDestination = null;
    setDestinationSelected(false);
    
    if (controller != null) {
      // 1. Clear the visual polyline layers completely
      await RouteVisualizer.clearRoute(controller);
      
      // 2. Remove the manual dropped pin or search symbol layer
      await engine.layers?.removeSearchPin();

      if (_currentDroppedPin != null) {
        await controller?.removeCircle(_currentDroppedPin!);
        _currentDroppedPin = null;
      }
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

    final locService =
        Provider.of<GlobalLocationService>(context, listen: false);
    final currentLocation = locService.currentPosition;

    // 🧠 SMART DESTINATION LOGIC: Check both Tapped Places AND Search Targets
    LatLng? destinationCoords;
    if (tappedPlaceFromMap != null) {
      destinationCoords =
          LatLng(tappedPlaceFromMap!.latitude, tappedPlaceFromMap!.longitude);
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
          "❌ Routing Error: Destination missing! Neither tappedPlace nor targetLocation is set.");
      AppHaptics.error();
      return;
    }

    _setLoading(true);
    AppHaptics.lightImpact(); // Processing Start

    try {
      final origin =
          LatLng(currentLocation.latitude, currentLocation.longitude);
      debugPrint("🛣️ Fetching route from $origin to $destinationCoords...");

      // Fetch from Routing API
      final routeData = await _routingService.getRoute(
        origin,
        destinationCoords,
      );

      if (routeData != null && routeData.coordinates.isNotEmpty) {
        _lastRouteData = routeData;
        List<LatLng> routePoints = routeData.coordinates;
            
        if (routePoints.isNotEmpty) {
          debugPrint("🔍 MAP PROVIDER AUDIT (1st Point): Lat=${routePoints.first.latitude}, Lng=${routePoints.first.longitude}");
        }

        debugPrint("✅ Route decoded successfully. Drawing on map...");

        // 🚀 2. Seedha draw kar de, koi FLIP ki zarurat nahi hai!
        await engine.layers?.drawRoute(routePoints);
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
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      if (locService.currentPosition == null) {
        await locService.forceRefreshLocation();
      }
      final pos = locService.currentPosition;
      if (pos == null) throw Exception("GPS Unavailable");

      final MasterSearchService searchService = MasterSearchService();
      final places = await searchService.getNearbyPlaces(
          LatLng(pos.latitude, pos.longitude), category);

      await clearNearbyPins();

      if (places.isNotEmpty) {
        double minLat = pos.latitude, maxLat = pos.latitude;
        double minLng = pos.longitude, maxLng = pos.longitude;

        for (var place in places) {
          minLat = math.min(minLat, place.latitude);
          maxLat = math.max(maxLat, place.latitude);
          minLng = math.min(minLng, place.longitude);
          maxLng = math.max(maxLng, place.longitude);

          final circle = await controller?.addCircle(CircleOptions(
              geometry: LatLng(place.latitude, place.longitude),
              circleRadius: 8.0,
              circleColor: "#00E5FF",
              circleStrokeWidth: 2.5,
              circleStrokeColor: "#FFFFFF"));
          if (circle != null) _nearbyCircles.add(circle);

          final label = await controller?.addSymbol(SymbolOptions(
            geometry: LatLng(place.latitude, place.longitude),
            textField: place.name,
            textOffset: const Offset(0, 1.5),
            textColor:
                _currentTheme == MapThemeType.light ? '#000000' : '#FFFFFF',
            textHaloColor:
                _currentTheme == MapThemeType.light ? '#FFFFFF' : '#000000',
            textHaloWidth: 1.5,
            textSize: 13.0,
          ));
          if (label != null) _nearbyLabels.add(label);
        }

        await controller?.animateCamera(
          CameraUpdate.newLatLngBounds(
              LatLngBounds(
                  southwest: LatLng(minLat - 0.005, minLng - 0.005),
                  northeast: LatLng(maxLat + 0.005, maxLng + 0.005)),
              left: 50,
              top: 100,
              right: 50,
              bottom: 250),
          duration: const Duration(milliseconds: 1500),
        );
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
      LatLng currentLoc, LatLng stationLoc, String stationName) async {
    if (!_isMapReady) return;
    _setLoading(true);
    targetStationLocation = stationLoc;
    targetStationName = stationName;
    isNavigatingToStation = true;
    notifyListeners();

    try {
      RouteResult? routeData =
          await _routingService.getRoute(currentLoc, stationLoc);

      if (routeData != null) {
        currentRouteDistance = "${routeData.distanceKm.toStringAsFixed(1)} km";
        currentRouteETA = "${routeData.durationMins} mins";

        await clearRouteData();

        _originMarker = await controller?.addCircle(CircleOptions(
            geometry: currentLoc,
            circleRadius: 7.0,
            circleColor: "#FF3B30",
            circleStrokeWidth: 2.5,
            circleStrokeColor: "#FFFFFF"));
        _currentMarker = await controller?.addCircle(CircleOptions(
            geometry: stationLoc,
            circleRadius: 7.0,
            circleColor: "#00E5FF",
            circleStrokeWidth: 2.5,
            circleStrokeColor: "#FFFFFF"));

        if (controller != null) {
          await RouteVisualizer.drawRoute(controller, routeData.coordinates, _currentTheme);
        }

        engine.navigation.startNavigation(routeData);

        double minLat = math.min(currentLoc.latitude, stationLoc.latitude);
        double maxLat = math.max(currentLoc.latitude, stationLoc.latitude);
        double minLng = math.min(currentLoc.longitude, stationLoc.longitude);
        double maxLng = math.max(currentLoc.longitude, stationLoc.longitude);

        await controller?.animateCamera(
          CameraUpdate.newLatLngBounds(
              LatLngBounds(
                  southwest: LatLng(minLat - 0.005, minLng - 0.005),
                  northeast: LatLng(maxLat + 0.005, maxLng + 0.005)),
              left: 50,
              top: 100,
              right: 50,
              bottom: 250),
          duration: const Duration(milliseconds: 1500),
        );
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
      double currentLat, double currentLng, Function onArrived) {
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
      final locService =
          Provider.of<GlobalLocationService>(context, listen: false);
      if (!locService.hasValidLocation) {
        await locService.initializeEcoLocation();
      }
      final pos = locService.currentPosition;
      if (pos == null) return;
      await clearRouteData();
      await flyTo(LatLng(pos.latitude, pos.longitude), zoom: 17.0, tilt: 45.0);
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
      await controller?.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16.0),
      );
      
      AppHaptics.mediumImpact();
    } catch (e) {
      debugPrint("⚠️ flyToPlace Error: $e");
    } finally {
      isFlying = false; 
      notifyListeners(); // 🚀 Force a fresh frame notify so the UI perfectly syncs when camera stops
    }
  }

  Future<void> flyTo(LatLng target,
      {double zoom = 16.0, double tilt = 60.0}) async {
    if (!_isMapReady) return;
    try {
      await controller?.animateCamera(
          CameraUpdate.newCameraPosition(CameraPosition(
              target: target, zoom: zoom, tilt: tilt, bearing: 0)),
          duration: const Duration(milliseconds: 1500));
      await _dropMarker(target);
    } catch (e) {
      debugPrint("FlyTo Error: $e");
    }
  }

  Future<void> _dropMarker(LatLng target) async {
    try {
      _currentMarker = await controller?.addCircle(CircleOptions(
          geometry: target,
          circleRadius: 7.0,
          circleColor: "#00E5FF",
          circleStrokeWidth: 2.5,
          circleStrokeColor: "#FFFFFF"));
      notifyListeners();
    } catch (e) {
      debugPrint("Drop Marker Error: $e");
    }
  }

  Future<void> triggerDirectionsFlow(BuildContext context) async {
    if (targetDestination == null || controller == null) return;

    // 1. Fetch Current Location (Origin)
    final locService = Provider.of<GlobalLocationService>(context, listen: false);
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

        // 3. Draw the Route on the Map
        await RouteVisualizer.drawRoute(controller, route.coordinates, _currentTheme);

        // 🧭 State Machine: Route drawn successfully
        engine.setUIState(MapUIState.routeDrawn);

        // 4. Smoothly animate camera to fit the entire route bounds
        final double minLat = math.min(originLoc.latitude, targetDestination!.latitude);
        final double maxLat = math.max(originLoc.latitude, targetDestination!.latitude);
        final double minLng = math.min(originLoc.longitude, targetDestination!.longitude);
        final double maxLng = math.max(originLoc.longitude, targetDestination!.longitude);

        await controller!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            left: 50, right: 50, top: 100, bottom: 400, // padding to account for the UI sheet
          ),
          duration: const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      debugPrint("Routing Error: $e");
    }
  }

  bool isActiveNavigation = false;

  Future<void> startActiveNavigation(BuildContext context) async {
    if (controller == null || targetDestination == null) return;

    final locService = Provider.of<GlobalLocationService>(context, listen: false);
    final pos = locService.currentPosition;
    if (pos == null) {
      debugPrint("Cannot start navigation: User location unknown.");
      return;
    }

    // Use existing route data or fetch a new one
    if (_lastRouteData == null) {
      final originLoc = LatLng(pos.latitude, pos.longitude);
      _lastRouteData = await _routingService.getRoute(
        originLoc,
        targetDestination!,
        mode: currentNavMode,
      );
    }

    if (_lastRouteData == null) {
      debugPrint("Cannot start navigation: No route data.");
      return;
    }

    // Set state
    isActiveNavigation = true;
    notifyListeners();

    AppHaptics.heavyImpact();

    // 🚀 Delegate to MapEngine's active navigation lifecycle
    await engine.startActiveNavigation(_lastRouteData!, targetDestination!);
  }

  Future<void> autoDrawRouteTo(LatLng destination, BuildContext context) async {
    if (controller == null) return;

    // 1. Get current location
    final locService = Provider.of<GlobalLocationService>(context, listen: false);
    final currentPos = locService.currentPosition;

    if (currentPos == null) {
      debugPrint('Auto-Route failed: User location not available.');
      return;
    }

    final originLoc = LatLng(currentPos.latitude, currentPos.longitude);

    // 2. Fetch and draw the route silently
    try {
      final route = await _routingService.getRoute(originLoc, destination, mode: currentNavMode);

      if (route != null) {
        _lastRouteData = route;
        targetDestination = destination;
        await RouteVisualizer.drawRoute(controller, route.coordinates, _currentTheme);

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

  void _clearError() {
    _lastError = null;
    notifyListeners();
  }

  void clearError() => _clearError();

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }
}
