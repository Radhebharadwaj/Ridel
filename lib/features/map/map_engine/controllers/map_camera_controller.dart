import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:ridel/core/services/global_location_service.dart';

enum MapCameraState { free, follow, heading }

enum CameraMode { explore, driving, transit }

class MapCameraController {
  final MapLibreMapController map;
  final GlobalLocationService locService;
  final TickerProvider vsync;

  MapCameraState state = MapCameraState.free;
  CameraMode currentMode = CameraMode.explore;

  String? _lastError;

  Circle? _userLocationDot;
  Circle? _userLocationHalo;

  Ticker? _cameraTicker;
  Ticker? _blueDotTicker;

  double _elapsedTime = 0.0;
  DateTime? _lastCameraNativeUpdate;
  SpringSimulation? _latSim;
  SpringSimulation? _lngSim;
  SpringSimulation? _zoomSim;
  SpringSimulation? _tiltSim;
  SpringSimulation? _bearingSim;

  double _dotElapsedTime = 0.0;
  DateTime? _lastDotNativeUpdate;
  SpringSimulation? _dotLatSim;
  SpringSimulation? _dotLngSim;
  LatLng? _currentDotPos;

  MapCameraController(this.map, this.locService, this.vsync) {
    _cameraTicker = vsync.createTicker(_onCameraTick);
    _blueDotTicker = vsync.createTicker(_onBlueDotTick);
  }

  void onUserPanGesture() {
    cancelAnimations();
    state = MapCameraState.free;
  }

  void cancelAnimations() {
    if (_cameraTicker?.isActive ?? false) {
      _cameraTicker?.stop();
    }
    if (_blueDotTicker?.isActive ?? false) {
      _blueDotTicker?.stop();
    }
    
    _latSim = null;
    _lngSim = null;
    _zoomSim = null;
    _tiltSim = null;
    _bearingSim = null;
    _elapsedTime = 0.0;
    
    _dotLatSim = null;
    _dotLngSim = null;
    _dotElapsedTime = 0.0;
  }

  void dispose() {
    cancelAnimations();
    _cameraTicker?.dispose();
    _blueDotTicker?.dispose();
    _cameraTicker = null;
    _blueDotTicker = null;

    try {
      if (_userLocationHalo != null) {
        map.removeCircle(_userLocationHalo!);
      }
      if (_userLocationDot != null) {
        map.removeCircle(_userLocationDot!);
      }
    } catch (_) {}
  }

  SpringSimulation _createSim(double start, double end, double velocity, {double stiffness = 45.0, double damping = 12.0}) {
    return SpringSimulation(
      SpringDescription(mass: 1.0, stiffness: stiffness, damping: damping),
      start,
      end,
      velocity,
    );
  }

  void _onCameraTick(Duration elapsed) {
    // 🛡️ Capture all 5 simulations into local finals to prevent
    // mid-tick nullification from cancelAnimations() race condition.
    final latSim = _latSim;
    final lngSim = _lngSim;
    final zoomSim = _zoomSim;
    final tiltSim = _tiltSim;
    final bearingSim = _bearingSim;

    // All 5 must be non-null to animate
    if (latSim == null || lngSim == null || zoomSim == null ||
        tiltSim == null || bearingSim == null) {
      _cameraTicker?.stop();
      return;
    }

    _elapsedTime = elapsed.inMicroseconds / 1000000.0;

    final lat = latSim.x(_elapsedTime);
    final lng = lngSim.x(_elapsedTime);
    final zoom = (zoomSim.x(_elapsedTime)).clamp(2.0, 22.0);
    final tilt = tiltSim.x(_elapsedTime);
    
    double bearing = bearingSim.x(_elapsedTime);
    bearing = bearing % 360.0;
    if (bearing < 0) {
      bearing += 360.0;
    }

    final now = DateTime.now();
    if (_lastCameraNativeUpdate == null || now.difference(_lastCameraNativeUpdate!).inMilliseconds >= 16) {
      _lastCameraNativeUpdate = now;
      map.moveCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(lat, lng),
        zoom: zoom,
        tilt: tilt,
        bearing: bearing,
      )));
    }

    if (latSim.isDone(_elapsedTime) && 
        lngSim.isDone(_elapsedTime) && 
        zoomSim.isDone(_elapsedTime) &&
        bearingSim.isDone(_elapsedTime) &&
        tiltSim.isDone(_elapsedTime)) {
      _cameraTicker?.stop();
    }
  }

  void _onBlueDotTick(Duration elapsed) {
    if (_dotLatSim == null || _userLocationDot == null || _userLocationHalo == null) return;
    _dotElapsedTime = elapsed.inMicroseconds / 1000000.0;

    final lat = _dotLatSim!.x(_dotElapsedTime);
    final lng = _dotLngSim!.x(_dotElapsedTime);
    _currentDotPos = LatLng(lat, lng);

    final now = DateTime.now();
    if (_lastDotNativeUpdate == null || now.difference(_lastDotNativeUpdate!).inMilliseconds >= 16) {
      _lastDotNativeUpdate = now;
      try {
        map.updateCircle(_userLocationHalo!, CircleOptions(geometry: _currentDotPos));
        map.updateCircle(_userLocationDot!, CircleOptions(geometry: _currentDotPos));
      } catch (_) {}
    }

    if (_dotLatSim!.isDone(_dotElapsedTime) && _dotLngSim!.isDone(_dotElapsedTime)) {
      _blueDotTicker?.stop();
    }
  }

  Future<void> animateCameraCinematic({
    required LatLng center,
    double? zoom,
    double? pitch,
    double? bearing,
  }) async {
    try {
      final cam = map.cameraPosition;
      if (cam == null) return;

      final currentLat = _latSim?.x(_elapsedTime) ?? cam.target.latitude;
      final currentLng = _lngSim?.x(_elapsedTime) ?? cam.target.longitude;
      final currentZoom = _zoomSim?.x(_elapsedTime) ?? cam.zoom;
      final currentTilt = _tiltSim?.x(_elapsedTime) ?? cam.tilt;
      final currentBearing = _bearingSim?.x(_elapsedTime) ?? cam.bearing;

      final vLat = _latSim?.dx(_elapsedTime) ?? 0.0;
      final vLng = _lngSim?.dx(_elapsedTime) ?? 0.0;
      final vZoom = _zoomSim?.dx(_elapsedTime) ?? 0.0;
      final vTilt = _tiltSim?.dx(_elapsedTime) ?? 0.0;
      final vBearing = _bearingSim?.dx(_elapsedTime) ?? 0.0;

      _elapsedTime = 0.0;
      _lastCameraNativeUpdate = null; // force immediate first update

      _latSim = _createSim(currentLat, center.latitude, vLat);
      _lngSim = _createSim(currentLng, center.longitude, vLng);
      _zoomSim = _createSim(currentZoom, zoom ?? cam.zoom, vZoom);
      _tiltSim = _createSim(currentTilt, pitch ?? cam.tilt, vTilt);

      double targetBearing = bearing ?? cam.bearing;
      double diff = (targetBearing - currentBearing) % 360.0;
      if (diff > 180.0) {
        diff -= 360.0;
      } else if (diff < -180.0) {
        diff += 360.0;
      }
      
      _bearingSim = _createSim(currentBearing, currentBearing + diff, vBearing);

      if (_cameraTicker?.isActive == true) {
        _cameraTicker?.stop();
      }
      _cameraTicker?.start();
      _clearError();
    } catch (e) {
      _setError("Camera animation failed: $e");
    }
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000.0; // meters
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            (sin(dLon / 2) * sin(dLon / 2));
    return R * (2 * atan2(sqrt(a), sqrt(1 - a)));
  }

  Future<void> setCameraForMode(CameraMode mode) async {
    currentMode = mode;
    final cam = map.cameraPosition;

    switch (mode) {
      case CameraMode.explore:
      case CameraMode.transit:
        state = MapCameraState.free;
        if (!kIsWeb) {
          map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
        }
        if (cam != null) {
          await animateCameraCinematic(
              center: cam.target,
              zoom: mode == CameraMode.explore ? 14.5 : 13.5,
              pitch: 0.0,
              bearing: 0.0);
        }
        break;

      case CameraMode.driving:
        state = MapCameraState.heading;
        if (cam != null) {
          await animateCameraCinematic(
              center: cam.target, zoom: 17.8, pitch: 60.0);
        }

        if (!kIsWeb) {
          map.updateMyLocationTrackingMode(MyLocationTrackingMode.trackingCompass);
        }

        try {
          if (!locService.isLiveTracking) {
            locService.startLiveTracking();
          }
          Position? pos = locService.currentPosition;
          if (pos != null) {
            await animateCameraCinematic(
                center: LatLng(pos.latitude, pos.longitude),
                zoom: 17.8,
                pitch: 60.0,
                bearing: pos.heading);
          }
        } catch (_) {}
        break;
    }
  }

  Future<void> processLocationUpdate(Position newPos) async {
    final latLng = LatLng(newPos.latitude, newPos.longitude);

    bool shouldUpdatePos = true;
    if (_currentDotPos != null) {
      final dist = _haversineDistance(
          _currentDotPos!.latitude, _currentDotPos!.longitude, 
          latLng.latitude, latLng.longitude);
      if (dist < 2.5) {
        shouldUpdatePos = false;
      }
    }

    if (shouldUpdatePos) {
      await _drawOrUpdateCustomBlueDot(latLng);
    }

    if (currentMode != CameraMode.driving || state != MapCameraState.heading) {
      return;
    }

    final safeCenter = _currentDotPos ?? latLng;
    final targetCenter = shouldUpdatePos ? latLng : safeCenter;

    // Smooth camera follow update
    await animateCameraCinematic(
       center: targetCenter,
       bearing: newPos.heading,
       zoom: 17.8,
       pitch: 60.0
    );
  }

  void resetCompass() {
    try {
      final cam = map.cameraPosition;
      if (cam != null) {
        animateCameraCinematic(center: cam.target, bearing: 0.0);
      }
      
      if (state == MapCameraState.heading) {
        state = MapCameraState.follow;
        if (!kIsWeb) {
          map.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
        }
      }
    } catch (_) {
      _setError("Compass reset failed");
    }
  }

  Future<void> animateSearchFlight(LatLng target) async {
    try {
      state = MapCameraState.free;
      if (!kIsWeb) {
        await map.updateMyLocationTrackingMode(MyLocationTrackingMode.none);
      }

      double southOffset = 0.0015;
      LatLng adjustedTarget = LatLng(target.latitude - southOffset, target.longitude);

      await animateCameraCinematic(
          center: adjustedTarget, zoom: 17.5, pitch: 60.0, bearing: 0.0);
    } catch (e) {
      _setError("Search flight failed: $e");
    }
  }

  void onLocateMeTapped(bool is3DMode, bool isDrivingMode) async {
    if (locService.currentPosition == null) {
      debugPrint("Location not available yet.");
      return;
    }

    final userPos = LatLng(locService.currentPosition!.latitude, locService.currentPosition!.longitude);
    await _drawOrUpdateCustomBlueDot(userPos, ignoreThrottle: true);

    double targetTilt = is3DMode ? 45.0 : 0.0;

    if (state == MapCameraState.free || state == MapCameraState.heading) {
      await animateCameraCinematic(center: userPos, zoom: 16.5, pitch: targetTilt, bearing: 0.0);
      state = MapCameraState.follow;
      if (!kIsWeb) {
        map.updateMyLocationTrackingMode(MyLocationTrackingMode.tracking);
      }
    } else if (state == MapCameraState.follow) {
      await animateCameraCinematic(center: userPos, zoom: 17.5, pitch: 50.0);
      state = MapCameraState.heading;
      if (!kIsWeb) {
        map.updateMyLocationTrackingMode(MyLocationTrackingMode.trackingCompass);
      }
    }
  }

  Future<void> _drawOrUpdateCustomBlueDot(LatLng pos, {bool ignoreThrottle = false}) async {
    if (_userLocationDot == null || _userLocationHalo == null) {
      _currentDotPos = pos;
      try {
        _userLocationHalo = await map.addCircle(CircleOptions(
          geometry: pos,
          circleRadius: 18.0,
          circleColor: "#007AFF",
          circleOpacity: 0.25,
        ));

        _userLocationDot = await map.addCircle(CircleOptions(
          geometry: pos,
          circleRadius: 7.0,
          circleColor: "#007AFF",
          circleStrokeWidth: 2.5,
          circleStrokeColor: "#FFFFFF",
        ));
      } catch (e) {
        debugPrint("Failed to draw custom blue dot: $e");
      }
      return;
    }

    if (ignoreThrottle) {
       _currentDotPos = pos;
       try {
         await map.updateCircle(_userLocationHalo!, CircleOptions(geometry: pos));
         await map.updateCircle(_userLocationDot!, CircleOptions(geometry: pos));
       } catch (_) {}
       return;
    }

    // Continuous Frame Interpolation for Blue Dot
    final currentLat = _dotLatSim?.x(_dotElapsedTime) ?? _currentDotPos!.latitude;
    final currentLng = _dotLngSim?.x(_dotElapsedTime) ?? _currentDotPos!.longitude;
    final vLat = _dotLatSim?.dx(_dotElapsedTime) ?? 0.0;
    final vLng = _dotLngSim?.dx(_dotElapsedTime) ?? 0.0;

    _dotElapsedTime = 0.0;
    _lastDotNativeUpdate = null;

    _dotLatSim = _createSim(currentLat, pos.latitude, vLat, stiffness: 60.0, damping: 15.0);
    _dotLngSim = _createSim(currentLng, pos.longitude, vLng, stiffness: 60.0, damping: 15.0);

    if (_blueDotTicker?.isActive == true) {
      _blueDotTicker?.stop();
    }
    _blueDotTicker?.start();
  }

  String? get lastError => _lastError;
  void _setError(String error) => _lastError = error;
  void _clearError() => _lastError = null;
}
