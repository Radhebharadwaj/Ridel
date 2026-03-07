import 'package:flutter/foundation.dart'; 
import 'package:flutter/animation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'map_mode_controller.dart';
import 'package:ridel/core/services/global_location_service.dart'; // 🚀 Central Brain

enum MapCameraState { free, follow, heading }
enum CameraMode { explore, driving, transit }

class MapCameraController {
  final MapLibreMapController map;
  final GlobalLocationService locService; // 🚀 Received from MapEngine

  MapCameraState state = MapCameraState.free;
  CameraMode currentMode = CameraMode.explore;

  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _lastPosition;
  String? _lastError;

  // 🚀 Constructor now requires locService
  MapCameraController(this.map, this.locService);

  Future<void> animateCameraCinematic({
    required LatLng center, double? zoom, double? pitch, double? bearing, int durationMs = 1200, Curve curve = Curves.easeOutCubic,
  }) async {
    try {
      final cam = map.cameraPosition;
      if (cam == null) return;
      await map.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: center, zoom: zoom ?? cam.zoom, tilt: pitch ?? cam.tilt, bearing: bearing ?? cam.bearing)),
        duration: Duration(milliseconds: durationMs),
      );
      _clearError();
    } catch (e) { _setError("Camera animation failed: $e"); }
  }

  // 🚀 No BuildContext needed anymore
  Future<void> setCameraForMode(CameraMode mode) async {
    currentMode = mode;
    final cam = map.cameraPosition;

    switch (mode) {
      case CameraMode.explore:
        state = MapCameraState.free;
        map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
        if (cam != null) await animateCameraCinematic(center: cam.target, zoom: 14.5, pitch: 0.0, bearing: 0.0, durationMs: 1500);
        break;

      case CameraMode.driving:
        state = MapCameraState.heading;
        if (cam != null) await animateCameraCinematic(center: cam.target, zoom: 17.8, pitch: 60.0, durationMs: 1200);

        map.updateMyLocationTrackingMode(kIsWeb ? MyLocationTrackingMode.tracking : MyLocationTrackingMode.trackingCompass);
        
        try {
          // 🚀 DIRECTLY USING CENTRAL BRAIN
          if (!locService.isLiveTracking) locService.startLiveTracking();
          
          Position? pos = locService.currentPosition;
          if (pos != null) {
            await animateCameraCinematic(center: LatLng(pos.latitude, pos.longitude), zoom: 17.8, pitch: 60.0, bearing: pos.heading, durationMs: 1000);
            _lastPosition = pos;
          }
        } catch (_) {}
        break;

      case CameraMode.transit:
        state = MapCameraState.free;
        map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
        if (cam != null) await animateCameraCinematic(center: cam.target, zoom: 13.5, pitch: 0.0, bearing: 0.0, durationMs: 1500);
        break;
    }
  }

  Future<void> processLocationUpdate(Position newPos) async {
    if (currentMode != CameraMode.driving || state != MapCameraState.heading) return;
    _lastUpdate = DateTime.now();
    _lastPosition = newPos;
  }

  void resetCompass() {
    try {
      map.animateCamera(CameraUpdate.bearingTo(0.0), duration: const Duration(milliseconds: 800));
      if (state == MapCameraState.heading) {
        state = MapCameraState.follow;
        map.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
      }
    } catch (_) { _setError("Compass reset failed"); }
  }

  Future<void> animateSearchFlight(LatLng target) async {
    try {
      final cam = map.cameraPosition;
      if (cam == null) return; 
      
      state = MapCameraState.free; 
      await map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);

      double southOffset = 0.0020;
      LatLng adjustedTarget = LatLng(target.latitude - southOffset, target.longitude);

      await map.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: adjustedTarget, 
            zoom: 16.5,   
            tilt: 55.0,   
            bearing: 0.0, 
          ),
        ),
        duration: const Duration(milliseconds: 2800), 
      );
      _clearError();
    } catch (e) {
      _setError("Search flight failed: $e");
    }
  }

  // 🚀 No BuildContext needed anymore
  Future<void> onLocateMeTapped(MapStyle style, bool isDriving) async {
    MapCameraState nextState = state == MapCameraState.free ? MapCameraState.follow : (state == MapCameraState.follow ? MapCameraState.heading : MapCameraState.free);
    state = nextState;

    if (nextState == MapCameraState.free) {
      map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
    } else {
      try {
        // 🚀 DIRECTLY USING CENTRAL BRAIN
        Position? position = locService.currentPosition;
        
        if (position == null) {
          await locService.forceRefreshLocation();
          position = locService.currentPosition;
        }
        
        if (position == null) return;
        
        LatLng target = LatLng(position.latitude, position.longitude);
        await map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
        
        double targetTilt = (style == MapStyle.mode3D || nextState == MapCameraState.heading) ? 60.0 : 0.0;
        await animateCameraCinematic(center: target, zoom: nextState == MapCameraState.heading ? 18.0 : 16.5, pitch: targetTilt, durationMs: 1200);

        map.updateMyLocationTrackingMode(
          (nextState == MapCameraState.heading && !kIsWeb) ? MyLocationTrackingMode.trackingCompass : MyLocationTrackingMode.tracking
        );
      } catch (_) {}
    }
  }

  String? get lastError => _lastError;
  void _setError(String error) => _lastError = error;
  void _clearError() => _lastError = null;
}