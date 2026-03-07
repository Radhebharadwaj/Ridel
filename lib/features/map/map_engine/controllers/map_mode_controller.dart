import 'package:flutter/foundation.dart';

enum MapMode { explore, driving, transit } 
enum MapStyle { mode2D, mode3D }           

class MapModeController extends ChangeNotifier {
  MapMode _currentMode = MapMode.explore; 
  MapStyle _currentStyle = MapStyle.mode2D;

  MapMode get currentMode => _currentMode;
  MapStyle get currentStyle => _currentStyle;

  void setMode(MapMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      notifyListeners(); // ⚡ Instantly updates the UI cards
    }
  }
  
  void toggle3D() {
    _currentStyle = _currentStyle == MapStyle.mode2D ? MapStyle.mode3D : MapStyle.mode2D;
    notifyListeners();
  }

  bool get isExploreMode => _currentMode == MapMode.explore;
  bool get isDrivingMode => _currentMode == MapMode.driving;
  bool get isTransitMode => _currentMode == MapMode.transit;
  bool get is3D => _currentStyle == MapStyle.mode3D;
}