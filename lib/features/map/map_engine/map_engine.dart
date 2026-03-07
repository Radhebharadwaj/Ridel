import 'dart:convert';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:ridel/core/services/global_location_service.dart'; 

import 'controllers/map_camera_controller.dart';
import 'controllers/map_layer_controller.dart';
import 'controllers/map_mode_controller.dart';
import 'controllers/map_navigation_controller.dart';

enum EngineState { idle, switchingMode, animatingCamera, updatingLayers, error }

class MapEngine extends ChangeNotifier {
  MapLibreMapController? mapController;
  EngineState _state = EngineState.idle;
  String? _lastError;
  
  late MapModeController mode;
  MapLayerController? layers;
  MapCameraController? camera;
  MapNavigationController navigation = MapNavigationController(); 

  // 🚀 Hold reference to Central Brain
  GlobalLocationService? locService;

  double realTimeSpeedKmph = 0.0;
  StreamSubscription<Position>? _positionStream;
  bool isDarkTheme = true;
  bool isSwitchingMode = false;

  DateTime? _lastDebounceTime;
  static const Duration _debounceInterval = Duration(milliseconds: 300);

  MapEngine() {
    mode = MapModeController();
  }

  // 🚀 Accept GlobalLocationService DIRECTLY instead of BuildContext
  Future<void> onMapCreated(MapLibreMapController controller, bool isDark, GlobalLocationService locationService) async {
    mapController = controller;
    isDarkTheme = isDark;
    locService = locationService; // Save reference
    
    layers = MapLayerController(controller);
    // 🚀 Pass the Brain directly to Camera Controller
    camera = MapCameraController(controller, locService!); 
    navigation.init(controller);

    if (kIsWeb) {
      try { await mapController?.clearAmbientCache(); } catch (_) {}
    }

    try {
      const String transparentPng = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";
      final Uint8List transparentBytes = base64Decode(transparentPng);
      
      final missingIcons = [
        'empty-pixel', 'Arrow', 
        'hospitals', 'universities', 'mall', 'hotel', 'supermarket', 
        'petrol_pump', 'food', 'national_highway', 'bank', 'theatre', 
        'ice_cream', 'ola-hypercharger', 'ola-mobility-fastcharger', 'ola-mbo',
        'state_highway', 'police', 'default_poi'
      ];

      for (String icon in missingIcons) {
        try {
          await mapController?.addImage(icon, transparentBytes);
        } catch (e) {
          debugPrint("Ignored image load error for $icon");
        }
      }
    } catch (e) {
      debugPrint("Silent catch for image injection: $e");
    }

    await Future.delayed(const Duration(milliseconds: 300));
    
    try {
      await layers?.initLayerSystem();
      _initGPS(); // 🚀 No Context needed anymore!
      syncEngineState();
      _setState(EngineState.idle);
    } catch (e) {
      _setError('Failed to initialize layers: $e');
    }
  }

  CameraMode _getCameraModeForMapMode(MapMode mapMode) {
    switch (mapMode) {
      case MapMode.explore: return CameraMode.explore;
      case MapMode.driving: return CameraMode.driving;
      case MapMode.transit: return CameraMode.transit;
    }
  }

  // 🚀 Pure Logic. No UI Context.
  Future<void> _initGPS() async {
    if (locService == null) return;
    
    if (locService!.currentPosition != null) {
      camera?.state = MapCameraState.follow;
      await camera?.animateCameraCinematic(
        center: LatLng(locService!.currentPosition!.latitude, locService!.currentPosition!.longitude), 
        zoom: 16.0
      );
    }

    locService!.startLiveTracking(); 
    _positionStream = locService!.engineLocationStream.listen((newPos) {
      realTimeSpeedKmph = locService!.currentSpeedKmph; 
      camera?.processLocationUpdate(newPos);
      notifyListeners();
    });
  }

  Future<void> setMode(MapMode newMode) async {
    if (_shouldDebounce() || isSwitchingMode || mode.currentMode == newMode) return;
    
    isSwitchingMode = true; 
    _setState(EngineState.switchingMode);

    try {
      await layers?.resetAllLayers();
      await layers?.applyModePreset(newMode);
      await camera?.setCameraForMode(_getCameraModeForMapMode(newMode)); // 🚀 Safe call
      
      mode.setMode(newMode); 

      if (newMode != MapMode.driving && mode.currentStyle == MapStyle.mode3D) {
        await layers?.toggle3DVisibility(true);
        final camPos = mapController?.cameraPosition;
        if (camPos != null) {
          await camera?.animateCameraCinematic(center: camPos.target, pitch: 60.0, durationMs: 800);
        }
      }
      _clearError();
    } finally {
      isSwitchingMode = false; 
      _setState(EngineState.idle);
    }
  }

  Future<void> executeSearchFlight(LatLng target) async {
    if (mapController == null || camera == null || layers == null) return;

    _setState(EngineState.animatingCamera);
    
    await layers!.showSearchPin(target);
    await camera!.animateSearchFlight(target);
    await layers!.fadePOIsTemporarily();
    _setState(EngineState.idle);
  }

  void toggle3D() async {
    if (_state != EngineState.idle || isSwitchingMode) return;
    mode.toggle3D();
    
    final camPos = mapController?.cameraPosition;
    if (camPos != null && mode.currentMode != MapMode.driving) {
      double targetPitch = mode.currentStyle == MapStyle.mode3D ? 60.0 : 0.0;
      camera?.animateCameraCinematic(center: camPos.target, pitch: targetPitch, durationMs: 800);
    }

    if (mode.currentStyle == MapStyle.mode3D) {
      await layers?.toggle3DVisibility(true);
    } else {
      await layers?.toggle3DVisibility(false);
    }
    notifyListeners();
  }

  void onLocateMeTapped() {
    camera?.onLocateMeTapped(mode.currentStyle, mode.currentMode == MapMode.driving); // 🚀 Safe call
    notifyListeners();
  }

  void onCompassTapped() {
    camera?.resetCompass();
    notifyListeners();
  }

  void onUserPannedMap() {
    if (camera?.state != MapCameraState.free) {
      camera?.state = MapCameraState.free;
      notifyListeners();
    }
  }

  void updateExtrusionProgress(double progress) {
    layers?.updateBuildingExtrusion(progress, isDarkTheme);
    if (progress == 0.0 && mode.currentStyle == MapStyle.mode2D) {
      layers?.toggle3DVisibility(false);
    }
  }

  Future<void> syncEngineState() async {
    if (isSwitchingMode) return;
    try {
      await layers?.applyModePreset(mode.currentMode);
      await camera?.setCameraForMode(_getCameraModeForMapMode(mode.currentMode));
      if (mode.currentStyle == MapStyle.mode3D) await layers?.toggle3DVisibility(true);
    } catch (_) {}
    notifyListeners(); 
  }

  String? get lastError => _lastError;
  bool get hasError => _lastError != null;
  EngineState get state => _state;
  
  void _setError(String error) { _lastError = error; _setState(EngineState.error); notifyListeners(); }
  void _clearError() { _lastError = null; notifyListeners(); }
  void _setState(EngineState newState) { _state = newState; notifyListeners(); }
  
  bool _shouldDebounce() {
    final now = DateTime.now();
    if (_lastDebounceTime != null && now.difference(_lastDebounceTime!) < _debounceInterval) return true;
    _lastDebounceTime = now; return false;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    mapController?.dispose();
    super.dispose();
  }
}