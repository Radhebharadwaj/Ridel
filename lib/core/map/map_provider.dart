import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart'; 
import 'package:ridel/core/services/global_location_service.dart'; 
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/core/services/ola_navigation_service.dart';
import 'dart:math' as math; 

class MapProvider extends ChangeNotifier {
  MapLibreMapController? _controller;
  
  Circle? _currentMarker;
  Circle? _originMarker; 

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

  void setController(MapLibreMapController controller) {
    _controller = controller;
    _clearError();       
    notifyListeners();  
  }

  // 🚀 THE MAGIC FIX: Web-Safe Mathematical Decoder (Never Overflows on Chrome)
  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        // Bitwise ki jagah Math use kiya hai jisse Web par Spiderweb na bane
        result += (b & 0x1f) * math.pow(2, shift).toInt();
        shift += 5;
      } while (b >= 0x20);
      
      int dlat = (result & 1) != 0 ? -(result ~/ 2) - 1 : (result ~/ 2);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result += (b & 0x1f) * math.pow(2, shift).toInt();
        shift += 5;
      } while (b >= 0x20);
      
      int dlng = (result & 1) != 0 ? -(result ~/ 2) - 1 : (result ~/ 2);
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }

    // 🛡️ Auto-Correction for OSRM 1E6 precision
    if (poly.isNotEmpty) {
      if (poly[0].latitude > 90.0 || poly[0].latitude < -90.0 || poly[0].longitude > 180.0 || poly[0].longitude < -180.0) {
        poly = poly.map((p) => LatLng(p.latitude / 10.0, p.longitude / 10.0)).toList();
      }
    }
    return poly;
  }

  // 🔥 1. Start Navigation & Draw Route (Perfect Google Maps Style)
  Future<void> startStationNavigation(LatLng currentLoc, LatLng stationLoc, String stationName) async {
    _setLoading(true);
    targetStationLocation = stationLoc;
    targetStationName = stationName;
    isNavigatingToStation = true;
    notifyListeners();

    try {
      // 🚀 Aapki OLA API Key
      final String apiKey = "LXLK4nwQMwacpTZhol7QHc3RPet3tUOkb76reivs"; 
      
      final String url = "https://api.olamaps.io/routing/v1/directions?"
          "origin=${currentLoc.latitude},${currentLoc.longitude}&"
          "destination=${stationLoc.latitude},${stationLoc.longitude}&"
          "api_key=$apiKey";

      print("🌐 ROUTING URL CALLING...");

      final response = await http.post(
        Uri.parse(url),
        headers: {"Accept": "application/json"}
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          
          String encodedPolyline = "";
          if (route['overview_polyline'] != null) {
            encodedPolyline = route['overview_polyline'] is String 
                ? route['overview_polyline'] 
                : route['overview_polyline']['points'] ?? "";
          }

          if (encodedPolyline.isEmpty) {
            await _fallbackFlyTo(stationLoc);
            return;
          }

          if (route['legs'] != null && route['legs'].isNotEmpty) {
            currentRouteDistance = "${(route['legs'][0]['distance'] / 1000).toStringAsFixed(1)} km";
            currentRouteETA = "${(route['legs'][0]['duration'] / 60).ceil()} mins";
            print("✅ ROUTE DATA READY: $currentRouteDistance, $currentRouteETA");
          }
          
          List<LatLng> routePoints = decodePolyline(encodedPolyline);

          // 🧹 Purani Layers aur Markers hatao
          await clearRouteData(); 

          // 📍 1. Add Origin Marker (Red)
          _originMarker = await _controller?.addCircle(
            CircleOptions(
              geometry: currentLoc,
              circleRadius: 7.0,
              circleColor: "#FF3B30", 
              circleStrokeWidth: 2.5,
              circleStrokeColor: "#FFFFFF",
            ),
          );

          // 📍 2. Add Destination Marker (Cyan)
          _currentMarker = await _controller?.addCircle(
            CircleOptions(
              geometry: stationLoc,
              circleRadius: 7.0,
              circleColor: "#00E5FF", 
              circleStrokeWidth: 2.5,
              circleStrokeColor: "#FFFFFF",
            ),
          );

          // 🛣️ 3. Native GeoJSON Route Drawing
          final geojsonData = {
            "type": "FeatureCollection",
            "features": [
              {
                "type": "Feature",
                "properties": {},
                "geometry": {
                  "type": "LineString",
                  // GeoJSON strictly needs [Lng, Lat] format
                  "coordinates": routePoints.map((p) => [p.longitude, p.latitude]).toList() 
                }
              }
            ]
          };

          await _controller?.addGeoJsonSource("route-source", geojsonData);
          await _controller?.addLineLayer(
            "route-source",
            "route-layer",
            const LineLayerProperties(
              lineColor: "#2864f0", // Premium Blue
              lineWidth: 6.0,
              lineJoin: "round",
              lineCap: "round",
            ),
          );

          // 📷 4. Camera Zoom perfectly fitted
          double minLat = math.min(currentLoc.latitude, stationLoc.latitude);
          double maxLat = math.max(currentLoc.latitude, stationLoc.latitude);
          double minLng = math.min(currentLoc.longitude, stationLoc.longitude);
          double maxLng = math.max(currentLoc.longitude, stationLoc.longitude);

          await _controller?.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat - 0.005, minLng - 0.005), 
                northeast: LatLng(maxLat + 0.005, maxLng + 0.005), 
              ),
              left: 50, top: 100, right: 50, bottom: 250, 
            ),
            duration: const Duration(milliseconds: 1500),
          );
          
          print("✅ PREMIUM GEOJSON ROUTE DRAWN!");
        } else {
          await _fallbackFlyTo(stationLoc);
        }
      } else {
        await _fallbackFlyTo(stationLoc);
      }
    } catch (e) {
      print("❌ CRITICAL ERROR: $e");
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

  // 🏁 AUTO-ARRIVAL CHECKER (Error Fixed!)
  void checkIfArrived(double currentLat, double currentLng, Function onArrived) {
    if (!isNavigatingToStation || targetStationLocation == null) return;
    var p = 0.017453292519943295; 
    var c = math.cos;
    var a = 0.5 - c((targetStationLocation!.latitude - currentLat) * p)/2 + 
          c(currentLat * p) * c(targetStationLocation!.latitude * p) * (1 - c((targetStationLocation!.longitude - currentLng) * p))/2;
    double distanceInMeters = 12742 * math.asin(math.sqrt(a)) * 1000;
    
    if (distanceInMeters <= 50.0) {
      stopStationNavigation();
      onArrived(); 
    }
  }

  // 🧹 CORE CLEANUP FUNCTION
  Future<void> clearRouteData() async {
    try {
      if (_controller != null) {
        await _controller?.removeLayer("route-layer");
        await _controller?.removeSource("route-source");
      }
    } catch (e) {}

    try {
      if (_currentMarker != null && _controller != null) {
        await _controller?.removeCircle(_currentMarker!);
        _currentMarker = null;
      }
      if (_originMarker != null && _controller != null) {
        await _controller?.removeCircle(_originMarker!);
        _originMarker = null;
      }
    } catch (e) {}
  }

  void stopStationNavigation() async {
    isNavigatingToStation = false;
    targetStationLocation = null;
    targetStationName = null;
    await clearRouteData();
    notifyListeners();
  }

  Future<void> markCurrentPosition(BuildContext context) async {
    if (_controller == null) return;
    _setLoading(true);
    try {
      final locService = Provider.of<GlobalLocationService>(context, listen: false);
      if (!locService.hasValidLocation) await locService.initializeEcoLocation();
      final pos = locService.currentPosition;
      if (pos == null) return;
      final target = LatLng(pos.latitude, pos.longitude);
      await clearRouteData();
      await flyTo(target, zoom: 17.0, tilt: 45.0);
    } catch (e) {} finally {
      _setLoading(false);
    }
  }

  Future<void> searchAndNavigate(String query) async {
    if (_controller == null) return;
    final now = DateTime.now();
    if (_lastSearchTime != null && now.difference(_lastSearchTime!) < _searchDebounce) return; 
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
    } catch (e) {} finally {
      _setLoading(false);
    }
  }

  void clearTargetLocation() {
    targetLocation = null;
    isCinematicSearch = false;
  }

  Future<void> flyTo(LatLng target, {double zoom = 16.0, double tilt = 60.0}) async {
    if (_controller == null) return;
    try {
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: zoom, tilt: tilt, bearing: 0)),
        duration: const Duration(milliseconds: 1500),
      );
      await _dropMarker(target);
    } catch (e) {}
  }

  Future<void> _dropMarker(LatLng target) async {
    try {
      _currentMarker = await _controller?.addCircle(
        CircleOptions(
          geometry: target,
          circleRadius: 7.0,
          circleColor: "#00E5FF", 
          circleStrokeWidth: 2.5,
          circleStrokeColor: "#FFFFFF",
        ),
      );
      notifyListeners();
    } catch (e) {}
  }

  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  void _setLoading(bool loading) { _isLoading = loading; notifyListeners(); }
  void _clearError() { _lastError = null; notifyListeners(); }
  void clearError() => _clearError();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}